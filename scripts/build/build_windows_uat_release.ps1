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

function Assert-UatUrlSafe {
  param(
    [Parameter(Mandatory = $true)][string]$Name,
    [Parameter(Mandatory = $true)][string]$Url
  )

  if ([string]::IsNullOrWhiteSpace($Url)) {
    throw "$Name is required for an isolated UAT build."
  }

  try {
    $uri = [Uri]$Url
  } catch {
    throw "$Name is not a valid absolute URL: $Url"
  }

  if (-not $uri.IsAbsoluteUri -or ($uri.Scheme -ne 'http' -and $uri.Scheme -ne 'https') -or [string]::IsNullOrWhiteSpace($uri.Host)) {
    throw "$Name must be an absolute http/https URL: $Url"
  }

  $urlHost = $uri.Host.ToLowerInvariant()
  $blockedHosts = @(
    'daleventapos-backend.gcdndd.easypanel.host',
    'ventas-fullpos-backend.gcdndd.easypanel.host',
    '31.97.99.70'
  )
  if ($blockedHosts -contains $urlHost -or
      $urlHost.Contains('easypanel') -or
      $urlHost.Contains('gcdndd') -or
      $urlHost.Contains('daleventapos-backend') -or
      $urlHost.Contains('ventas-fullpos-backend')) {
    throw "Refusing to build Windows UAT Mayoreo with a production/shared host in ${Name}: $urlHost"
  }
}

Assert-UatUrlSafe -Name 'API_BASE_URL' -Url $ApiBaseUrl
Assert-UatUrlSafe -Name 'APP_BASE_URL' -Url $AppBaseUrl

$repoRoot = Get-RepoRoot
$appRelativePath = 'apps\fulltech_app'
$appRoot = Join-Path $repoRoot $appRelativePath

if (-not (Test-Path -LiteralPath (Join-Path $appRoot 'pubspec.yaml'))) {
  throw "Flutter app root not found: $appRoot"
}

$exitCode = 1
$previousWindowsChannel = $env:FULLPOS_WINDOWS_CHANNEL
$previousWindowsRoot = $env:DALEVENTAS_POS_UAT_MAYOREO_ROOT

try {
  Write-Step "Repo root: $repoRoot"
  Write-Step "UAT API_BASE_URL: $ApiBaseUrl"
  Write-Step 'Windows identity: UAT Mayoreo (fullpos_cloud_uat_mayoreo.exe)'
  $env:FULLPOS_WINDOWS_CHANNEL = 'uat-mayoreo'
  if (-not [string]::IsNullOrWhiteSpace($WindowsAppRoot)) {
    $resolvedWindowsAppRoot = (New-Item -ItemType Directory -Force -Path $WindowsAppRoot).FullName
    $env:DALEVENTAS_POS_UAT_MAYOREO_ROOT = $resolvedWindowsAppRoot
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
    $releaseOutput = Join-Path $appRoot 'build\windows\x64\runner\Release'
    if (Test-Path -LiteralPath (Join-Path $releaseOutput 'fullpos_cloud.exe')) {
      throw 'Production executable found in output. Use a fresh short UAT worktree.'
    }

    & flutter build windows --release `
      --dart-define=FULLPOS_UAT_BUILD=true `
      --dart-define=FULLPOS_UAT_NAME=MAYOREO `
      --dart-define=API_BASE_URL=$ApiBaseUrl `
      --dart-define=APP_BASE_URL=$AppBaseUrl `
      --dart-define=DISABLE_APP_UPDATES=true `
      --dart-define=ALLOW_UNSIGNED_UPDATES_FOR_UAT=false `
      --dart-define=ALLOW_UNSIGNED_UPDATES_FOR_PRODUCTION=false
    $exitCode = $LASTEXITCODE
    if ($exitCode -ne 0) {
      throw "flutter build windows --release failed with exit code $exitCode"
    }

    $expectedExe = Join-Path $releaseOutput 'fullpos_cloud_uat_mayoreo.exe'
    if (-not (Test-Path -LiteralPath $expectedExe)) {
      throw "Expected isolated UAT executable was not created: $expectedExe"
    }
  } finally {
    Pop-Location
  }

  Write-Step 'Windows UAT Release build completed successfully.'
  $exitCode = 0
} catch {
  Write-Error $_ -ErrorAction Continue
} finally {
  $env:DALEVENTAS_POS_UAT_MAYOREO_ROOT = $previousWindowsRoot
  if ($null -eq $previousWindowsChannel) {
    Remove-Item Env:\FULLPOS_WINDOWS_CHANNEL -ErrorAction SilentlyContinue
  } else {
    $env:FULLPOS_WINDOWS_CHANNEL = $previousWindowsChannel
  }
}

exit $exitCode
