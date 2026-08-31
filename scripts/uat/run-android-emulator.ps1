. "$PSScriptRoot\_common.ps1"

Assert-UatEnvironment
Write-UatBanner

$androidApi = "http://10.0.2.2:$env:PORT"
$hostHealthUrl = "http://127.0.0.1:$env:PORT/health"
try {
  $health = Invoke-WebRequest -UseBasicParsing -TimeoutSec 5 $hostHealthUrl
  if ($health.StatusCode -lt 200 -or $health.StatusCode -ge 300) {
    throw "Unexpected health status $($health.StatusCode)"
  }
} catch {
  throw "Refusing Android emulator UAT: local backend is not reachable at $hostHealthUrl. $($_.Exception.Message)"
}

Push-Location (Join-Path $RepoRoot "apps\fulltech_app")
try {
  flutter run -d emulator --dart-define=API_BASE_URL="$androidApi"
} finally {
  Pop-Location
}
