$ErrorActionPreference = 'Stop'
Set-Location (Split-Path $PSScriptRoot -Parent)
docker info | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Start the Docker Linux container runtime' }
kubectl cluster-info --request-timeout=10s
if ($LASTEXITCODE -eq 0) { Write-Host 'Reusing the cluster in the current kubeconfig context'; exit 0 }
if (!(Get-Command kind -ErrorAction SilentlyContinue)) { throw 'Install kind v0.33.0 using the official download instructions in README' }
kind create cluster --name cicd-gitops --config cluster/kind.yaml --wait 120s
if ($LASTEXITCODE -ne 0) { throw 'kind cluster creation failed' }
