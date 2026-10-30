. "$PSScriptRoot\_common.ps1"

Assert-IsolatedEnvironment
Assert-ApiPortAvailable
$env:APPYRA_USAGE_TELEMETRY_ENABLED = 'false'
$env:ECF_EMISSION_ENABLED = 'false'
$env:ECF_ALANUBE_AUTH_TESTS_ENABLED = 'false'
$env:ALANUBE_HTTP_TRANSPORT_ENABLED = 'false'
Remove-Item Env:ALANUBE_SANDBOX_TOKEN -ErrorAction SilentlyContinue
Write-IsolatedBanner
Push-Location $ApiRoot
try {
  npm run start:dev
} finally {
  Pop-Location
}
