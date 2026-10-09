param(
  [switch]$SkipPubGet,
  [switch]$SkipInstaller,
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

function Read-FlutterPubspecVersion {
  param([string]$AppRoot)

  $pubspecPath = Join-Path $AppRoot 'pubspec.yaml'
  $line = Get-Content -LiteralPath $pubspecPath | Where-Object { $_ -match '^\s*version:\s*(\S+)\s*$' } | Select-Object -First 1
  if (-not $line -or $line -notmatch '^\s*version:\s*(\d+\.\d+\.\d+)\+([1-9][0-9]*)\s*$') {
    throw "Invalid Flutter version in $pubspecPath. Expected format x.y.z+build."
  }

  return [pscustomobject]@{
    Version = $Matches[1]
    BuildNumber = [int]$Matches[2]
    VersionInfo = "$($Matches[1]).$($Matches[2])"
    PubspecValue = "$($Matches[1])+$($Matches[2])"
  }
}

function Get-GitCommitSha {
  param([string]$RepoRoot)

  & git -C $RepoRoot rev-parse HEAD
  if ($LASTEXITCODE -ne 0) {
    throw 'Unable to resolve git commit SHA for release metadata.'
  }
}

function Get-InstallerMetadata {
  param(
    [string]$InstallerPath,
    [string]$Version,
    [int]$BuildNumber,
    [string]$CommitSha
  )

  $item = Get-Item -LiteralPath $InstallerPath -ErrorAction Stop
  $hash = Get-FileHash -LiteralPath $InstallerPath -Algorithm SHA256
  $signature = Get-AuthenticodeSignature -LiteralPath $InstallerPath

  return [pscustomobject]@{
    Version = $Version
    BuildNumber = $BuildNumber
    CommitSha = $CommitSha
    Installer = $item.FullName
    SizeBytes = $item.Length
    Sha256 = $hash.Hash
    SignatureStatus = $signature.Status
    SignerSubject = $signature.SignerCertificate.Subject
  }
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
$installerScript = Join-Path $repoRoot 'installer\find_and_build_inno.ps1'

if (-not (Test-Path -LiteralPath (Join-Path $appRoot 'pubspec.yaml'))) {
  throw "Flutter app root not found: $appRoot"
}
if (-not $SkipInstaller -and -not (Test-Path -LiteralPath $installerScript)) {
  throw "Installer build script not found: $installerScript"
}

$createdBuildEnv = $false
$exitCode = 1

try {
  $version = Read-FlutterPubspecVersion -AppRoot $appRoot
  $commitSha = Get-GitCommitSha -RepoRoot $repoRoot

  Write-Step "Repo root: $repoRoot"
  Write-Step "Flutter app root: $appRoot"
  Write-Step "Version source: $appRelativePath\pubspec.yaml -> $($version.PubspecValue)"
  Write-Step "Commit SHA: $commitSha"
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
      --build-name=$($version.Version) `
      --build-number=$($version.BuildNumber) `
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

  if (-not $SkipInstaller) {
    Write-Step 'Running Inno Setup packaging'
    & $installerScript `
      -Version $version.Version `
      -BuildNumber $version.BuildNumber `
      -VersionInfo $version.VersionInfo
    $exitCode = $LASTEXITCODE
    if ($exitCode -ne 0) {
      throw "Inno Setup packaging failed with exit code $exitCode"
    }

    $installerPath = Join-Path $repoRoot "installer\output\FullPOS-Setup-$($version.Version)-$($version.BuildNumber).exe"
    $metadata = Get-InstallerMetadata `
      -InstallerPath $installerPath `
      -Version $version.Version `
      -BuildNumber $version.BuildNumber `
      -CommitSha $commitSha

    Write-Step 'Windows Release artifact metadata:'
    $metadata | Format-List
  } else {
    Write-Step 'Skipping installer packaging by request.'
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
