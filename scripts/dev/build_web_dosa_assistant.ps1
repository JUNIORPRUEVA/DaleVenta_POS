# Construye el PWA de Flutter Web con el asistente DOSA habilitado.
#
# Uso:
#   pwsh -File scripts/dev/build_web_dosa_assistant.ps1
#   pwsh -File scripts/dev/build_web_dosa_assistant.ps1 -ApiBaseUrl https://fullposcloud.fulltechrd.com/api
#
# La clave publicable se resuelve en este orden:
#   1. -PublishableKey (parametro, no queda en el historial del repo)
#   2. variable de entorno DOSA_ASSISTANT_PUBLISHABLE_KEY
#   3. apps/fulltech_app/.env.dosa.local  (ignorado por git) con la linea
#      DOSA_ASSISTANT_PUBLISHABLE_KEY=pk_...
#
# La clave es publica por diseno, pero NO se versiona: se inyecta en el build
# con --dart-define y nunca se imprime en claro. Una clave `sk_` (secreta) se
# rechaza aqui: el cliente solo admite la publicable.
#
# Requisitos previos: `flutter pub get` en apps/fulltech_app.
# Este script no despliega nada y no toca produccion.

[CmdletBinding()]
param(
  [string] $ApiBaseUrl = 'http://127.0.0.1:3999',
  [string] $DosaBaseUrl = 'https://dosasystem.com',
  [string] $PublishableKey,
  [switch] $AllowMissingKey
)

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$appDir = Join-Path $repoRoot 'apps/fulltech_app'
$localEnv = Join-Path $appDir '.env.dosa.local'

if (-not (Test-Path $appDir)) {
  Write-Error "No se encontro apps/fulltech_app en $repoRoot"
  exit 1
}

function Read-LocalKey {
  param([string] $Path)
  if (-not (Test-Path $Path)) { return $null }
  $line = Get-Content $Path -ErrorAction SilentlyContinue |
    Where-Object { $_ -match '^\s*DOSA_ASSISTANT_PUBLISHABLE_KEY\s*=' } |
    Select-Object -First 1
  if (-not $line) { return $null }
  return ($line -replace '^\s*DOSA_ASSISTANT_PUBLISHABLE_KEY\s*=\s*', '').Trim().Trim('"').Trim("'")
}

$key = $PublishableKey
if ([string]::IsNullOrWhiteSpace($key)) { $key = $env:DOSA_ASSISTANT_PUBLISHABLE_KEY }
if ([string]::IsNullOrWhiteSpace($key)) { $key = Read-LocalKey -Path $localEnv }
$key = ($key ?? '').Trim()

if ($key -like 'sk_*') {
  Write-Error 'Se recibio una clave secreta (sk_). El cliente solo acepta la clave publicable (pk_).'
  exit 1
}

$hasKey = -not [string]::IsNullOrWhiteSpace($key)
if ($hasKey -and -not $key.StartsWith('pk_')) {
  Write-Error 'La clave publicable debe empezar por pk_.'
  exit 1
}

if (-not $hasKey) {
  if (-not $AllowMissingKey) {
    Write-Error @"
No hay clave publicable de DOSA configurada.

Definela en una de estas ubicaciones (no se versiona):
  - parametro -PublishableKey pk_...
  - variable de entorno DOSA_ASSISTANT_PUBLISHABLE_KEY
  - archivo $localEnv con la linea DOSA_ASSISTANT_PUBLISHABLE_KEY=pk_...

Sin clave el asistente no se monta (bloqueo missingSessionSource).
Usa -AllowMissingKey solo para compilar una UI sin asistente.
"@
    exit 1
  }
  Write-Warning 'Compilando SIN clave publicable: el asistente quedara bloqueado (missingSessionSource).'
}

$flutterArgs = @(
  'build', 'web', '--release',
  "--dart-define=API_BASE_URL=$ApiBaseUrl",
  '--dart-define=DOSA_ASSISTANT_ENABLED=true',
  "--dart-define=DOSA_ASSISTANT_BASE_URL=$DosaBaseUrl"
)

if ($hasKey) {
  $masked = if ($key.Length -le 8) { 'pk_...' } else { $key.Substring(0, 8) + '...' }
  Write-Host "Clave publicable detectada: $masked (longitud $($key.Length))"
  $flutterArgs += "--dart-define=DOSA_ASSISTANT_PUBLISHABLE_KEY=$key"
} else {
  Write-Host 'Clave publicable: ausente'
}

Write-Host "API_BASE_URL=$ApiBaseUrl"
Write-Host "DOSA base-url=$DosaBaseUrl"
Write-Host 'Compilando Flutter Web (release)...'

Push-Location $appDir
try {
  & flutter @flutterArgs
  $code = $LASTEXITCODE
} finally {
  Pop-Location
}

if ($code -ne 0) {
  Write-Error "flutter build web fallo con codigo $code"
  exit $code
}

Write-Host 'Build listo en apps/fulltech_app/build/web'
