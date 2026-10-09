param([Parameter(Mandatory=$true)][string]$RepoUrl)
$ErrorActionPreference = 'Stop'
Set-Location (Split-Path $PSScriptRoot -Parent)
if ($RepoUrl -notmatch '^https://github.com/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+\.git$') { throw 'An exact GitHub repository HTTPS URL is required' }
if ((Get-Content k8s/overlays/dev/kustomization.yaml -Raw) -match 'OWNER|sha256:0{64}') { throw 'Merge the real image digest PR before bootstrapping GitOps' }
function K { & kubectl @args; if ($LASTEXITCODE -ne 0) { throw 'kubectl failed' } }
K create namespace cicd-demo --dry-run=client -o yaml | kubectl apply -f -
if ($LASTEXITCODE -ne 0) { throw 'Namespace setup failed' }
K create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
if ($LASTEXITCODE -ne 0) { throw 'Namespace setup failed' }
K apply --server-side --force-conflicts -k argocd/install
K wait --for=condition=Established crd/applications.argoproj.io --timeout=120s
foreach ($p in @('argocd/project.yaml','argocd/application.yaml')) {
  (Get-Content $p -Raw).Replace('https://github.com/OWNER/cicd-gitops.git',$RepoUrl) | kubectl apply -f -
  if ($LASTEXITCODE -ne 0) { throw 'ArgoCD bootstrap failed' }
}
K rollout status deployment/argocd-server -n argocd --timeout=300s
