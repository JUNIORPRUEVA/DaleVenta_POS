param(
  [switch]$SkipPubGet,
  [string]$ApiBaseUrl = 'https://daleventapos-backend.gcdndd.easypanel.host',
  [string]$AppBaseUrl = 'https://daleventapos-backend.gcdndd.easypanel.host',
  [int]$ApiTimeoutMs = 15000
)

$ErrorActionPreference = 'Stop'

function Write-Step {
  param([string]$Message)
  Write-Host "[fullpos-build] $Message"
}

function Get-RepoRoot {
  $scriptDir = Split-Path -Parent $PSCommandPath
  return (Resolve-Path -LiteralPath (Join-Path $scriptDir '..\..')).Path
}

function Assert-ShortRealWindowsBuildPath {
  param([string]$AppRoot)

  $maxAppRootLength = 60
  if ($AppRoot.Length -le $maxAppRootLength) {
    return
  }

  throw @"
Windows build path is too long for the native plugin toolchain.
Current app path length: $($AppRoot.Length)
Maximum supported app path length: $maxAppRootLength

Create a real short Git worktree and run the build there, for example:
  git worktree add C:\src\fullpos-release <branch-or-commit>

Do not rely on subst for release builds; Flutter, CMake and MSBuild can mix
physical and mapped paths in generated files.
"@
}

function New-BuildEnvIfMissing {
  param(
    [string]$AppRoot,
    [string]$ApiBaseUrl,
    [string]$AppBaseUrl,
    [int]$ApiTimeoutMs
  )

  $envPath = Join-Path $AppRoot '.env'
  if (Test-Path -LiteralPath $envPath) {
    Write-Step 'Using existing local .env asset.'
    return $false
  }

  Write-Step 'Creating temporary non-secret .env asset for Windows build.'
  @(
    "API_BASE_URL=$ApiBaseUrl",
    "APP_BASE_URL=$AppBaseUrl",
    "API_TIMEOUT_MS=$ApiTimeoutMs"
  ) | Set-Content -LiteralPath $envPath -Encoding UTF8
  return $true
}

$repoRoot = Get-RepoRoot
$appRelativePath = 'apps\fulltech_app'
$appRoot = Join-Path $repoRoot $appRelativePath

if (-not (Test-Path -LiteralPath (Join-Path $appRoot 'pubspec.yaml'))) {
  throw "Flutter app root not found: $appRoot"
}

$createdBuildEnv = $false
$exitCode = 1

try {
  Write-Step "Repo root: $repoRoot"
  Write-Step "Flutter app root: $appRoot"
  Assert-ShortRealWindowsBuildPath -AppRoot $appRoot
  $createdBuildEnv = New-BuildEnvIfMissing `
    -AppRoot $appRoot `
    -ApiBaseUrl $ApiBaseUrl `
    -AppBaseUrl $AppBaseUrl `
    -ApiTimeoutMs $ApiTimeoutMs

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

    Write-Step 'Running flutter build windows --release'
    & flutter build windows --release `
      --dart-define=FULLPOS_PRODUCTION_BUILD=true `
      --dart-define=API_BASE_URL=$ApiBaseUrl `
      --dart-define=APP_BASE_URL=$AppBaseUrl `
      --dart-define=API_TIMEOUT_MS=$ApiTimeoutMs
    $exitCode = $LASTEXITCODE
    if ($exitCode -ne 0) {
      throw "flutter build windows --release failed with exit code $exitCode"
    }
  } finally {
    Pop-Location
  }

  Write-Step 'Windows Release build completed successfully.'
  $exitCode = 0
} catch {
  Write-Error $_
} finally {
  if ($createdBuildEnv) {
    Write-Step 'Removing temporary .env asset.'
    Remove-Item -LiteralPath (Join-Path $appRoot '.env') -Force
  }
}

exit $exitCode
