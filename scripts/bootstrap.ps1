param([Parameter(Mandatory=$true)][string]$RepoUrl)
$ErrorActionPreference = 'Stop'
Set-Location (Split-Path $PSScriptRoot -Parent)
if ($RepoUrl -notmatch '^https://github.com/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+\.git$') { throw '需要精确 GitHub 仓库 HTTPS URL' }
if ((Get-Content k8s/overlays/dev/kustomization.yaml -Raw) -match 'OWNER|sha256:0{64}') { throw '请先合并真实镜像 digest PR，再引导 GitOps' }
function K { & kubectl @args; if ($LASTEXITCODE -ne 0) { throw 'kubectl 失败' } }
K create namespace cicd-demo --dry-run=client -o yaml | kubectl apply -f -
if ($LASTEXITCODE -ne 0) { throw 'namespace 失败' }
K create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
if ($LASTEXITCODE -ne 0) { throw 'namespace 失败' }
K apply --server-side --force-conflicts -k argocd/install
K wait --for=condition=Established crd/applications.argoproj.io --timeout=120s
foreach ($p in @('argocd/project.yaml','argocd/application.yaml')) {
  (Get-Content $p -Raw).Replace('https://github.com/OWNER/cicd-gitops.git',$RepoUrl) | kubectl apply -f -
  if ($LASTEXITCODE -ne 0) { throw 'Argo 引导失败' }
}
K rollout status deployment/argocd-server -n argocd --timeout=300s
