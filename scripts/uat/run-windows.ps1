. "$PSScriptRoot\_common.ps1"

Assert-UatEnvironment
Write-UatBanner

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
  flutter run -d windows --dart-define=API_BASE_URL="http://127.0.0.1:$env:PORT"
} finally {
  Pop-Location
}
