$ErrorActionPreference='Stop'
$p = kubectl get pods -n cicd-demo -l app=demo -o json | ConvertFrom-Json
if ($LASTEXITCODE -ne 0) { throw '查询失败' }
$ready=@($p.items | Where-Object { @($_.status.conditions | Where-Object {$_.type -eq 'Ready' -and $_.status -eq 'True'}).Count -eq 1 })
if ($ready.Count -ne 3) { throw "业务 Ready Pod 数不是 3：$($ready.Count)" }
$a=kubectl get application cicd-demo -n argocd -o json | ConvertFrom-Json
if ($LASTEXITCODE -ne 0 -or $a.status.sync.status -ne 'Synced' -or $a.status.health.status -ne 'Healthy') { throw 'ArgoCD 未达到 Synced/Healthy' }
Write-Host '验收通过：3 个业务 Pod Ready，ArgoCD Synced/Healthy'
