$ErrorActionPreference = 'Stop'
$taskRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$taskApp = Join-Path $taskRoot 'apps/fulltech_app'
$evidence = Join-Path $taskRoot '.uat/product-lifecycle/windows'
$fixture = Join-Path $taskRoot '.uat/product-lifecycle/native-fixture.json'
if ((Get-Content -LiteralPath $fixture -Raw | ConvertFrom-Json).api -ne 'http://127.0.0.1:4017') {
  throw 'Only the dedicated loopback product lifecycle fixture is permitted.'
}
New-Item -ItemType Directory -Path $evidence -Force | Out-Null
$resultFile = Join-Path $evidence 'native-result.json'
$previousRunId = if (Test-Path -LiteralPath $resultFile) { (Get-Content -LiteralPath $resultFile -Raw | ConvertFrom-Json).runId } else { $null }
$previousRoot = $env:DALEVENTAS_POS_UAT_MAYOREO_ROOT
$env:DALEVENTAS_POS_UAT_MAYOREO_ROOT = Join-Path $taskRoot '.uat/product-lifecycle/windows-data'
Push-Location $taskApp
try {
  # Env's existing UAT guard requires 4004. The integration repository uses its
  # explicit, dedicated loopback 4017 API; no service on host 4004 is modified.
  flutter test integration_test/product_lifecycle_native_test.dart -d windows --no-pub `
    --dart-define=FULLPOS_UAT_BUILD=true --dart-define=FULLPOS_UAT_PROFILE=true `
    --dart-define=API_BASE_URL=http://127.0.0.1:4004 --dart-define=APP_BASE_URL=http://127.0.0.1:4004 `
    --dart-define=UAT_API_BASE=http://127.0.0.1:4004 --dart-define=DISABLE_APP_UPDATES=true `
    "--dart-define=PRODUCT_LIFECYCLE_AUTH_FILE=$fixture" "--dart-define=PRODUCT_LIFECYCLE_EVIDENCE_DIR=$evidence"
  if ($LASTEXITCODE -ne 0) { throw 'Windows acceptance failed; preserve all evidence.' }
  $currentResult = Get-Content -LiteralPath $resultFile -Raw | ConvertFrom-Json
  if ($currentResult.result -ne 'PASS' -or $currentResult.platform -ne 'windows' -or
      [string]::IsNullOrWhiteSpace($currentResult.runId) -or $currentResult.runId -eq $previousRunId) {
    throw 'Windows result is missing, failed or stale; it cannot be used as current evidence.'
  }
} finally {
  Pop-Location
  $env:DALEVENTAS_POS_UAT_MAYOREO_ROOT = $previousRoot
}
