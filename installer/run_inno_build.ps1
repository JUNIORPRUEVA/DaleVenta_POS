param(
  [Parameter(Mandatory = $true)]
  [string]$ScriptName,
  [Parameter(Mandatory = $true)]
  [string]$LogName,
  [string]$Version = '1.0.3+120',
  [string]$VersionInfo = '1.0.3.120',
  [string]$SourceDir = '..\apps\fulltech_app\build\windows\x64\runner\Release'
)

$ErrorActionPreference = 'Stop'
$installerDir = $PSScriptRoot
$isccCandidates = @(
  "$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe",
  'C:\Program Files (x86)\Inno Setup 6\ISCC.exe',
  'C:\Program Files\Inno Setup 6\ISCC.exe'
)
$iscc = $isccCandidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
$scriptPath = Join-Path $installerDir $ScriptName
$logPath = Join-Path $installerDir $LogName
$expectedApiHost = 'daleventapos-backend.gcdndd.easypanel.host'
$forbiddenApiHost = 'ventas-fullpos-backend.gcdndd.easypanel.host'

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

if (-not $iscc) {
  throw 'ISCC.exe no encontrado. Instala Inno Setup 6 o agrega ISCC.exe a una ruta conocida.'
}

if (-not (Test-Path -LiteralPath $scriptPath)) {
  throw "Script Inno no existe en $scriptPath"
}

Assert-DaleVentasReleaseSource -Path (Join-Path $installerDir $SourceDir)

Set-Location $installerDir
$args = @(
  $scriptPath,
  "/DMyAppVersion=$Version",
  "/DMyAppVersionInfo=$VersionInfo",
  "/DMyAppSourceDir=$SourceDir"
)

& $iscc @args *> $logPath
exit $LASTEXITCODE
