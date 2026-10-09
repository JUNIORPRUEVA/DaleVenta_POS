param(
  [string]$Version,
  [int]$BuildNumber,
  [string]$VersionInfo,
  [string]$SourceDir = '..\apps\fulltech_app\build\windows\x64\runner\Release'
)

$ErrorActionPreference = 'Stop'

$installerDir = $PSScriptRoot
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $installerDir '..')).Path
$setupScript = Join-Path $installerDir 'setup.iss'
$reportPath = Join-Path $installerDir 'inno-build-report.txt'
$expectedApiHost = 'daleventapos-backend.gcdndd.easypanel.host'
$forbiddenApiHost = 'ventas-fullpos-backend.gcdndd.easypanel.host'

function Read-FlutterPubspecVersion {
  $pubspecPath = Join-Path $repoRoot 'apps\fulltech_app\pubspec.yaml'
  $line = Get-Content -LiteralPath $pubspecPath | Where-Object { $_ -match '^\s*version:\s*(\S+)\s*$' } | Select-Object -First 1
  if (-not $line -or $line -notmatch '^\s*version:\s*(\d+\.\d+\.\d+)\+([1-9][0-9]*)\s*$') {
    throw "Invalid Flutter version in $pubspecPath. Expected format x.y.z+build."
  }

  return [pscustomobject]@{
    Version = $Matches[1]
    BuildNumber = [int]$Matches[2]
    VersionInfo = "$($Matches[1]).$($Matches[2])"
  }
}

function Assert-DaleVentasReleaseSource {
  param([string]$Path)

  $resolved = Resolve-Path -LiteralPath $Path -ErrorAction Stop
  if (-not (Get-Command rg -ErrorAction SilentlyContinue)) {
    throw 'rg no encontrado. No se puede verificar el backend del Release antes de empaquetar.'
  }

  & rg -a --fixed-strings $expectedApiHost $resolved.Path --quiet
  if ($LASTEXITCODE -ne 0) {
    throw "Release source no contiene el backend oficial de DaleVentas: $expectedApiHost"
  }

  & rg -a --fixed-strings $forbiddenApiHost $resolved.Path --quiet
  if ($LASTEXITCODE -eq 0) {
    throw "Release source contiene backend prohibido de FullPOS Owner: $forbiddenApiHost"
  }
}

function Find-IsccPath {
  $candidates = [System.Collections.Generic.List[string]]::new()

  foreach ($path in @(
    'C:\Program Files (x86)\Inno Setup 6\ISCC.exe',
    'C:\Program Files\Inno Setup 6\ISCC.exe',
    'C:\Program Files\Inno Setup 5\ISCC.exe',
    'C:\Program Files (x86)\Inno Setup 5\ISCC.exe',
    "$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe"
  )) {
    if (Test-Path -LiteralPath $path) { $candidates.Add($path) }
  }

  foreach ($root in @(
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
    'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall'
  )) {
    Get-ChildItem $root -ErrorAction SilentlyContinue | ForEach-Object {
      try {
        $item = Get-ItemProperty $_.PSPath -ErrorAction Stop
        if (($item.DisplayName -as [string]) -like '*Inno Setup*') {
          foreach ($possible in @($item.InstallLocation, (Split-Path ($item.DisplayIcon -as [string]) -Parent))) {
            if ($possible) {
              $iscc = Join-Path $possible 'ISCC.exe'
              if (Test-Path -LiteralPath $iscc) { $candidates.Add($iscc) }
            }
          }
        }
      } catch {}
    }
  }

  foreach ($dir in @('C:\Program Files', 'C:\Program Files (x86)')) {
    Get-ChildItem $dir -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -like 'Inno Setup*' } | ForEach-Object {
      $iscc = Join-Path $_.FullName 'ISCC.exe'
      if (Test-Path -LiteralPath $iscc) { $candidates.Add($iscc) }
    }
  }

  return $candidates | Select-Object -Unique | Select-Object -First 1
}

$pubspecVersion = Read-FlutterPubspecVersion
if (-not $Version) { $Version = $pubspecVersion.Version }
if (-not $BuildNumber) { $BuildNumber = $pubspecVersion.BuildNumber }
if (-not $VersionInfo) { $VersionInfo = "$Version.$BuildNumber" }

if ($Version -notmatch '^\d+\.\d+\.\d+$') {
  throw "Invalid Version '$Version'. Expected x.y.z."
}
if ($BuildNumber -le 0) {
  throw "Invalid BuildNumber '$BuildNumber'. Expected a positive integer."
}
if ($VersionInfo -notmatch '^\d+\.\d+\.\d+\.\d+$') {
  throw "Invalid VersionInfo '$VersionInfo'. Expected x.y.z.build."
}
if ($Version -ne $pubspecVersion.Version -or $BuildNumber -ne $pubspecVersion.BuildNumber) {
  throw "Installer version $Version+$BuildNumber does not match pubspec.yaml $($pubspecVersion.Version)+$($pubspecVersion.BuildNumber). Update pubspec.yaml first."
}

$outputExe = Join-Path $installerDir "output\FullPOS-Setup-$Version-$BuildNumber.exe"

Set-Location $installerDir
$isccPath = Find-IsccPath

if (-not $isccPath) {
  @(
    'RESULT=ISCC_NOT_FOUND',
    "SETUP_SCRIPT=$setupScript",
    "OUTPUT_EXE=$outputExe"
  ) | Set-Content -Path $reportPath -Encoding UTF8
  exit 2
}

Assert-DaleVentasReleaseSource -Path (Join-Path $installerDir $SourceDir)

$before = if (Test-Path $outputExe) { (Get-Item $outputExe).LastWriteTimeUtc.ToString('o') } else { '' }

& $isccPath $setupScript "/DMyAppVersion=$Version" "/DMyAppBuildNumber=$BuildNumber" "/DMyAppVersionInfo=$VersionInfo" "/DMyAppSourceDir=$SourceDir" *> $reportPath

$afterExists = Test-Path $outputExe
$after = if ($afterExists) { (Get-Item $outputExe).LastWriteTimeUtc.ToString('o') } else { '' }

Add-Content -Path $reportPath -Value "`nRESULT=OK"
Add-Content -Path $reportPath -Value "ISCC_PATH=$isccPath"
Add-Content -Path $reportPath -Value "VERSION=$Version"
Add-Content -Path $reportPath -Value "BUILD_NUMBER=$BuildNumber"
Add-Content -Path $reportPath -Value "VERSION_INFO=$VersionInfo"
Add-Content -Path $reportPath -Value "OUTPUT_EXE=$outputExe"
Add-Content -Path $reportPath -Value "BEFORE_UTC=$before"
Add-Content -Path $reportPath -Value "AFTER_EXISTS=$afterExists"
Add-Content -Path $reportPath -Value "AFTER_UTC=$after"
