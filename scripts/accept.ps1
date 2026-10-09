$ErrorActionPreference='Stop'
$p = kubectl get pods -n cicd-demo -l app=demo -o json | ConvertFrom-Json
if ($LASTEXITCODE -ne 0) { throw 'Query failed' }
$ready=@($p.items | Where-Object { @($_.status.conditions | Where-Object {$_.type -eq 'Ready' -and $_.status -eq 'True'}).Count -eq 1 })
if ($ready.Count -ne 3) { throw "Expected 3 Ready application pods; found: $($ready.Count)" }
$a=kubectl get application cicd-demo -n argocd -o json | ConvertFrom-Json
if ($LASTEXITCODE -ne 0 -or $a.status.sync.status -ne 'Synced' -or $a.status.health.status -ne 'Healthy') { throw 'ArgoCD is not Synced/Healthy' }
Write-Host 'Acceptance passed: 3 application pods Ready; ArgoCD Synced/Healthy'
