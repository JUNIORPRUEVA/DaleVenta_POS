. "$PSScriptRoot\_common.ps1"

Assert-UatEnvironment
Write-UatBanner

$WindowsAppRoot = Join-Path $RepoRoot ".uat\windows-app-root"
[Environment]::SetEnvironmentVariable("DALEVENTAS_POS_ROOT", $WindowsAppRoot, "Process")
[Environment]::SetEnvironmentVariable("FULLPOS_UAT_MODE", "offline-safe-48h", "Process")

$healthUrl = "http://127.0.0.1:$env:PORT/health"
try {
  $health = Invoke-WebRequest -UseBasicParsing -TimeoutSec 5 $healthUrl
  if ($health.StatusCode -lt 200 -or $health.StatusCode -ge 300) {
    throw "Unexpected health status $($health.StatusCode)"
  }
} catch {
  throw "Refusing to run Windows UAT: local backend is not reachable at $healthUrl. $($_.Exception.Message)"
}

Push-Location (Join-Path $RepoRoot "apps\fulltech_app")
try {
  Write-Host "WINDOWS_UAT_ROOT: $WindowsAppRoot"
  Write-Host "UPDATER: DISABLED"
  flutter run -d windows `
    --dart-define=API_BASE_URL="http://127.0.0.1:$env:PORT" `
    --dart-define=APP_BASE_URL="http://127.0.0.1:$env:PORT" `
    --dart-define=DISABLE_APP_UPDATES=true `
    --dart-define=ALLOW_UNSIGNED_UPDATES_FOR_UAT=false `
    --dart-define=ALLOW_UNSIGNED_UPDATES_FOR_PRODUCTION=false
} finally {
  Pop-Location
}
