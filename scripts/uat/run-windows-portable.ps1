param(
  [switch]$SkipBuild,
  [switch]$SkipPubGet
)

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
  throw "Refusing to run Windows portable UAT: local backend is not reachable at $healthUrl. $($_.Exception.Message)"
}

$windowsAppRoot = Join-Path $RepoRoot ".uat\windows-app-root"
$apiBaseUrl = "http://127.0.0.1:$env:PORT"
$releaseDir = Join-Path $RepoRoot "apps\fulltech_app\build\windows\x64\runner\Release"

if (-not $SkipBuild) {
  $buildScript = Join-Path $RepoRoot "scripts\build\build_windows_uat_release.ps1"
  $args = @(
    "-ExecutionPolicy", "Bypass",
    "-File", $buildScript,
    "-ApiBaseUrl", $apiBaseUrl,
    "-AppBaseUrl", $apiBaseUrl,
    "-WindowsAppRoot", $windowsAppRoot
  )
  if ($SkipPubGet) {
    $args += "-SkipPubGet"
  }
  & powershell @args
  if ($LASTEXITCODE -ne 0) {
    throw "Windows UAT build failed with exit code $LASTEXITCODE."
  }
}

$exeCandidates = @(
  (Join-Path $releaseDir "fullpos_cloud.exe"),
  (Join-Path $releaseDir "daleventa_pos.exe")
)
$exePath = $exeCandidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
if ([string]::IsNullOrWhiteSpace($exePath)) {
  throw "Windows UAT executable not found in: $releaseDir"
}

New-Item -ItemType Directory -Force -Path $windowsAppRoot | Out-Null
[Environment]::SetEnvironmentVariable("DALEVENTAS_POS_ROOT", $windowsAppRoot, "Process")
[Environment]::SetEnvironmentVariable("FULLPOS_UAT_MODE", "offline-safe-48h", "Process")

Write-Host "WINDOWS_UAT_EXE: $exePath"
Write-Host "WINDOWS_UAT_ROOT: $windowsAppRoot"
Write-Host "API_BASE_URL: $apiBaseUrl"
Write-Host "UPDATER: DISABLED at compile time"
Write-Host "Starting isolated Windows UAT app. Close the app window when UAT is complete."

& $exePath
