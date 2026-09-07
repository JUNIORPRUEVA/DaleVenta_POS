param(
  [string]$ApiBaseUrl = 'http://31.97.99.70:4001',
  [string]$AppBaseUrl = 'http://31.97.99.70:4001',
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

function Test-DriveLetterAvailable {
  param([char]$Letter)

  $driveRoot = "${Letter}:\"
  $driveName = "${Letter}:"
  if (Get-PSDrive -Name ([string]$Letter) -ErrorAction SilentlyContinue) {
    return $false
  }
  if (Test-Path -LiteralPath $driveRoot) {
    return $false
  }
  $substLines = @(cmd /c subst 2>$null)
  foreach ($line in $substLines) {
    if ($line.TrimStart().StartsWith($driveName, [StringComparison]::OrdinalIgnoreCase)) {
      return $false
    }
  }
  return $true
}

function Get-AvailableDriveLetter {
  $preferred = @('X', 'Y', 'Z', 'W', 'V', 'U', 'T', 'S', 'R', 'Q', 'P', 'O', 'N', 'M', 'L', 'K')
  foreach ($letter in $preferred) {
    if (Test-DriveLetterAvailable -Letter $letter) {
      return $letter
    }
  }
  throw 'No unused drive letter is available for the temporary short-path build mapping.'
}

if ([string]::IsNullOrWhiteSpace($ApiBaseUrl) -or [string]::IsNullOrWhiteSpace($AppBaseUrl)) {
  throw 'UAT API/App URLs are required.'
}
if ($ApiBaseUrl -like '*daleventapos-backend.gcdndd.easypanel.host*' -or
    $AppBaseUrl -like '*daleventapos-backend.gcdndd.easypanel.host*') {
  throw 'Refusing to build a UAT client with the production DaleVentas backend.'
}

$repoRoot = Get-RepoRoot
$appRelativePath = 'apps\fulltech_app'
$appRoot = Join-Path $repoRoot $appRelativePath

if (-not (Test-Path -LiteralPath (Join-Path $appRoot 'pubspec.yaml'))) {
  throw "Flutter app root not found: $appRoot"
}

$letter = Get-AvailableDriveLetter
$driveName = "${letter}:"
$driveRoot = "${driveName}\"
$mappedAppRoot = "$driveRoot$appRelativePath"
$createdMapping = $false
$exitCode = 1

try {
  Write-Step "Repo root: $repoRoot"
  Write-Step "UAT API_BASE_URL: $ApiBaseUrl"
  Write-Step "Creating temporary mapping $driveName => $repoRoot"
  & subst $driveName $repoRoot
  if ($LASTEXITCODE -ne 0) {
    throw "subst failed with exit code $LASTEXITCODE"
  }
  $createdMapping = $true

  Push-Location -LiteralPath $mappedAppRoot
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
      --dart-define=APP_BASE_URL=$AppBaseUrl
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
} finally {
  if ($createdMapping) {
    Write-Step "Removing temporary mapping $driveName"
    & subst $driveName /D
    if ($LASTEXITCODE -ne 0) {
      Write-Warning "Could not remove temporary mapping $driveName; run 'subst $driveName /D' manually."
      if ($exitCode -eq 0) {
        $exitCode = 1
      }
    }
  }
}

exit $exitCode
