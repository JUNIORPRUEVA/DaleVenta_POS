param([switch]$CheckOnly)

$ErrorActionPreference = 'Stop'
$repositoryRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
$releaseDirectory = Join-Path $repositoryRoot 'apps\fulltech_app\build\windows\x64\runner\Release'
$executable = Join-Path $releaseDirectory 'fullpos_cloud_uat_mayoreo.exe'
$storageRoot = Join-Path $repositoryRoot '.uat-windows-storage\mayoreo'

if (-not (Test-Path -LiteralPath $executable -PathType Leaf)) {
  throw 'Falta compilar la app UAT Mayoreo. Consulta docs/MAYOREO_PRICE_LISTS_RUNBOOK.md.'
}

try {
  $health = Invoke-WebRequest -Uri 'http://127.0.0.1:4001/health' -UseBasicParsing -TimeoutSec 5
  if ($health.StatusCode -ne 200) { throw 'Respuesta de salud inesperada.' }
} catch {
  throw 'La API UAT local no responde en 127.0.0.1:4001. Inicia primero la API aislada.'
}

if ($CheckOnly) {
  Write-Output 'PASS: ejecutable UAT disponible y API local HTTP 200.'
  return
}

$rootVariable = 'DALEVENTAS_POS_UAT_MAYOREO_ROOT'
$previousRoot = [Environment]::GetEnvironmentVariable($rootVariable, 'Process')
try {
  [Environment]::SetEnvironmentVariable($rootVariable, $storageRoot, 'Process')
  Start-Process -FilePath $executable -WorkingDirectory $releaseDirectory -WindowStyle Normal
  Write-Output 'FullPOS Cloud UAT - Mayoreo iniciado con almacenamiento aislado.'
} finally {
  [Environment]::SetEnvironmentVariable($rootVariable, $previousRoot, 'Process')
}
