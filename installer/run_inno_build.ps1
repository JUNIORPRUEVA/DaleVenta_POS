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

if (-not $iscc) {
  throw 'ISCC.exe no encontrado. Instala Inno Setup 6 o agrega ISCC.exe a una ruta conocida.'
}

if (-not (Test-Path -LiteralPath $scriptPath)) {
  throw "Script Inno no existe en $scriptPath"
}

Set-Location $installerDir
$args = @(
  $scriptPath,
  "/DMyAppVersion=$Version",
  "/DMyAppVersionInfo=$VersionInfo",
  "/DMyAppSourceDir=$SourceDir"
)

& $iscc @args *> $logPath
exit $LASTEXITCODE
