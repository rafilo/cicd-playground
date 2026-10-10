$ErrorActionPreference = 'Stop'
$dev = Get-Content (Join-Path $PSScriptRoot '../k8s/overlays/dev/kustomization.yaml') -Raw
$prodPath = Join-Path $PSScriptRoot '../k8s/overlays/prod/kustomization.yaml'
$match = [regex]::Match($dev, 'digest: (sha256:[a-f0-9]{64})')
if (-not $match.Success) { throw 'Development image digest is missing or invalid.' }
$prod = Get-Content $prodPath -Raw
$prod = [regex]::Replace($prod, 'digest: sha256:[a-f0-9]{64}', 'digest: ' + $match.Groups[1].Value)
[IO.File]::WriteAllText($prodPath, $prod, [Text.UTF8Encoding]::new($false))
Write-Host 'Production digest updated. Commit this change on a branch and open a reviewed promotion PR.'
