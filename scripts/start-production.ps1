$ErrorActionPreference = 'Stop'
Set-Location (Split-Path $PSScriptRoot -Parent)
$context = 'kind-cicd-production'
function K { & kubectl --context $context @args; if ($LASTEXITCODE -ne 0) { throw 'Production kubectl command failed.' } }
function Invoke-ProductionHelm { & helm @args; if ($LASTEXITCODE -ne 0) { throw 'Production Helm command failed.' } }
$clusters = & ./tools/kind.exe get clusters
if ($LASTEXITCODE -ne 0) { throw 'Unable to list kind clusters.' }
if ($clusters -notcontains 'cicd-production') {
  & ./tools/kind.exe create cluster --name cicd-production --config cluster/kind-production.yaml --image kindest/node:v1.36.4@sha256:099e049362a1526b2db71494e1947aae99bd16290d7c895f2b7ea312e3cbfaed --wait 180s
  if ($LASTEXITCODE -ne 0) { throw 'Production cluster creation failed.' }
} else {
  $nodes = & ./tools/kind.exe get nodes --name cicd-production
  foreach ($node in $nodes) { & docker start $node | Out-Null; if ($LASTEXITCODE -ne 0) { throw 'Unable to start production node.' } }
  & ./tools/kind.exe export kubeconfig --name cicd-production
  if ($LASTEXITCODE -ne 0) { throw 'Unable to export production kubeconfig.' }
}
K wait --for=condition=Ready nodes --all --timeout=180s
foreach ($namespace in @('cicd-prod', 'argocd', 'cicd-prod-observe')) {
  & kubectl --context $context create namespace $namespace --dry-run=client -o yaml | & kubectl --context $context apply -f -
  if ($LASTEXITCODE -ne 0) { throw 'Production namespace creation failed.' }
}
Invoke-ProductionHelm repo add traefik https://traefik.github.io/charts
Invoke-ProductionHelm repo update traefik
Invoke-ProductionHelm upgrade --install traefik traefik/traefik --version 41.7.1 --kube-context $context --namespace traefik --create-namespace --values cluster/traefik-production.yaml --wait --timeout 300s
K apply --server-side --force-conflicts -k argocd/install
K wait --for=condition=Established crd/applications.argoproj.io --timeout=120s
K apply -f argocd/prod/project.yaml
K apply -f argocd/prod/application.yaml
K apply -f ops/prod/prometheus.yaml
K apply -f ops/prod/service.yaml
K rollout status deployment/argocd-server -n argocd --timeout=300s
Write-Host 'Production GitOps bootstrap completed. Application ingress: http://localhost:18080'
Write-Host 'Wait for cicd-production to become Synced and Healthy in ArgoCD before acceptance.'
