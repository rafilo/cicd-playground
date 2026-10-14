param(
  [Parameter(Mandatory)][string]$Context,
  [string]$Namespace = 'cicd-demo',
  [string]$BaseUrl = 'http://localhost:8081',
  [Parameter(Mandatory)][ValidatePattern('^[a-f0-9]{40}$')][string]$ExpectedVersion,
  [string]$ArgoApplication = ''
)
$ErrorActionPreference = 'Stop'
foreach ($deployment in @('demo', 'demo-web')) {
  & kubectl --context $Context -n $Namespace rollout status "deployment/$deployment" --timeout=300s
  if ($LASTEXITCODE -ne 0) { throw "Rollout failed: $deployment" }
}
if ($ArgoApplication) {
  $app = & kubectl --context $Context -n argocd get application $ArgoApplication -o json
  if ($LASTEXITCODE -ne 0) { throw 'Unable to read Argo CD application' }
  $state = $app | ConvertFrom-Json
  if ($state.status.sync.status -ne 'Synced' -or $state.status.health.status -ne 'Healthy') {
    throw 'Argo CD application is not Synced/Healthy'
  }
}
foreach ($endpoint in @('healthz', 'readyz')) {
  if ((Invoke-RestMethod "$BaseUrl/$endpoint").status -ne 'ok') { throw "Failed $endpoint" }
}
$pods = @{}
1..30 | ForEach-Object {
  $identity = Invoke-RestMethod "$BaseUrl/api/whoami"
  if ($identity.version -ne $ExpectedVersion -or -not $identity.pod) { throw 'Unexpected release identity' }
  $pods[$identity.pod] = 1 + $pods[$identity.pod]
}
$pods | ConvertTo-Json
Write-Host "Release verification passed: 30 successful requests for $ExpectedVersion. Distribution is observational."
