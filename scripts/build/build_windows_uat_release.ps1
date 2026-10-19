param(
  [string]$ApiBaseUrl = 'http://127.0.0.1:46548',
  [string]$AppBaseUrl = 'http://127.0.0.1:46548',
  [string]$WindowsAppRoot = '',
  [switch]$SkipPubGet
)

$ErrorActionPreference = 'Stop'

function Write-Step {
  param([string]$Message)
  Write-Host "[daleventas-uat-build] $Message"
}

function Get-RepoRoot {
  $scriptDir = Split-Path -Parent $PSCommandPath
  return (Resolve-Path -LiteralPath (Join-Path $scriptDir '..\..')).Path
}

if ([string]::IsNullOrWhiteSpace($ApiBaseUrl) -or [string]::IsNullOrWhiteSpace($AppBaseUrl)) {
  throw 'UAT API/App URLs are required.'
}
if ($ApiBaseUrl -like '*daleventapos-backend.gcdndd.easypanel.host*' -or
    $AppBaseUrl -like '*daleventapos-backend.gcdndd.easypanel.host*' -or
    $ApiBaseUrl -like '*31.97.99.70*' -or
    $AppBaseUrl -like '*31.97.99.70*') {
  throw 'Refusing to build a UAT client with the production DaleVentas backend.'
}

$repoRoot = Get-RepoRoot
$appRelativePath = 'apps\fulltech_app'
$appRoot = Join-Path $repoRoot $appRelativePath

if (-not (Test-Path -LiteralPath (Join-Path $appRoot 'pubspec.yaml'))) {
  throw "Flutter app root not found: $appRoot"
}

$exitCode = 1

try {
  Write-Step "Repo root: $repoRoot"
  Write-Step "UAT API_BASE_URL: $ApiBaseUrl"
  if (-not [string]::IsNullOrWhiteSpace($WindowsAppRoot)) {
    $resolvedWindowsAppRoot = (New-Item -ItemType Directory -Force -Path $WindowsAppRoot).FullName
    [Environment]::SetEnvironmentVariable("DALEVENTAS_POS_ROOT", $resolvedWindowsAppRoot, "Process")
    [Environment]::SetEnvironmentVariable("FULLPOS_UAT_MODE", "offline-safe-48h", "Process")
    Write-Step "Windows UAT data root for launched child processes: $resolvedWindowsAppRoot"
  }
  Write-Step "Building from physical short worktree path: $appRoot"

  Push-Location -LiteralPath $appRoot
  try {
    if (-not $SkipPubGet) {
      Write-Step 'Running flutter pub get'
      & flutter pub get
      if ($LASTEXITCODE -ne 0) {
        $exitCode = $LASTEXITCODE
        throw "flutter pub get failed with exit code $exitCode"
      }
    }

    Write-Step 'Running flutter build windows --release for UAT'
    & flutter build windows --release `
      --dart-define=API_BASE_URL=$ApiBaseUrl `
      --dart-define=APP_BASE_URL=$AppBaseUrl `
      --dart-define=DISABLE_APP_UPDATES=true `
      --dart-define=ALLOW_UNSIGNED_UPDATES_FOR_UAT=false `
      --dart-define=ALLOW_UNSIGNED_UPDATES_FOR_PRODUCTION=false
    $exitCode = $LASTEXITCODE
    if ($exitCode -ne 0) {
      throw "flutter build windows --release failed with exit code $exitCode"
    }
  } finally {
    Pop-Location
  }

  Write-Step 'Windows UAT Release build completed successfully.'
  $exitCode = 0
} catch {
  Write-Error $_
}

exit $exitCode
