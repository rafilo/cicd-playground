$ErrorActionPreference = 'Stop'
Set-Location (Split-Path $PSScriptRoot -Parent)
docker info | Out-Null
if ($LASTEXITCODE -ne 0) { throw '请启动 Docker Linux 容器运行时' }
kubectl cluster-info --request-timeout=10s
if ($LASTEXITCODE -eq 0) { Write-Host '复用当前 kubeconfig 集群'; exit 0 }
if (!(Get-Command kind -ErrorAction SilentlyContinue)) { throw '安装 kind v0.33.0，参考 README 官方下载步骤' }
kind create cluster --name cicd-gitops --config cluster/kind.yaml --wait 120s
if ($LASTEXITCODE -ne 0) { throw 'kind 创建失败' }
