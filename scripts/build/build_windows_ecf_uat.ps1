<#
.SYNOPSIS
  Compila la UAT Windows de FullPOS e-CF con el perfil blindado.

.DESCRIPTION
  Este script existe porque un build con solo `--dart-define=APP_ENV=uat`
  terminó hablando con PRODUCCIÓN. Aquí:

    - se comprueba rama y repositorio;
    - se rechaza cualquier URL que no sea local (127.0.0.1:4004);
    - se compila SIEMPRE con FULLPOS_UAT_PROFILE=true;
    - se construye en una ruta corta para evitar MSB3491 (MAX_PATH);
    - se verifica que `app.so` se regeneró (no se reutiliza un artefacto);
    - se copia el resultado a una carpeta identificada como UAT;
    - se escribe un manifiesto de build SIN secretos.

  No toca el script de compilación comercial ni configuración de clientes.

.EXAMPLE
  pwsh scripts/build/build_windows_ecf_uat.ps1
#>
param(
  [string]$ApiBaseUrl = 'http://127.0.0.1:4004',
  [string]$AppBaseUrl = 'http://127.0.0.1:4004',
  [string]$ShortRoot  = 'C:\b\ecf',
  [string]$DistRoot   = 'C:\b\ecf-uat-dist',
  [switch]$SkipSync
)

$ErrorActionPreference = 'Stop'

function Fail([string]$message) {
  Write-Host "BLOQUEADO: $message" -ForegroundColor Red
  exit 1
}

function Assert-LocalUrl([string]$url, [string]$name) {
  $uri = $null
  if (-not [Uri]::TryCreate($url, [UriKind]::Absolute, [ref]$uri)) {
    Fail "$name no es una URL absoluta válida: '$url'."
  }
  if ($uri.Scheme -notin @('http', 'https')) { Fail "$name debe usar http o https." }

  $host_ = $uri.Host.ToLowerInvariant()
  $forbidden = @('easypanel.host', 'gcdndd', '31.97.99.70', 'hostinger', 'phytoemagry')
  foreach ($marker in $forbidden) {
    if ($url.ToLowerInvariant().Contains($marker)) {
      Fail "$name apunta a infraestructura productiva ('$marker'). Un build UAT no puede usarla."
    }
  }
  if ($host_ -notin @('127.0.0.1', 'localhost', '::1')) {
    Fail "$name debe ser local (127.0.0.1/localhost). Valor recibido: '$host_'."
  }
  if (-not $uri.IsDefaultPort -and $uri.Port -ne 4004) {
    Fail "$name debe usar el puerto 4004. Valor recibido: $($uri.Port)."
  }
  if ($uri.IsDefaultPort) {
    Fail "$name debe declarar el puerto explícito 4004."
  }
  return $url.TrimEnd('/')
}

# --- 1. Repositorio y rama -------------------------------------------------
$repoRoot = (Get-Location).Path
if (-not (Test-Path (Join-Path $repoRoot 'apps\fulltech_app\pubspec.yaml'))) {
  Fail "Ejecuta este script desde la raíz del repositorio FULLPOS-ECF-ALANUBE."
}
$branch = (git rev-parse --abbrev-ref HEAD 2>$null)
if ($branch -ne 'feature/ecf-alanube') {
  Write-Host "AVISO: rama actual '$branch' (esperada 'feature/ecf-alanube')." -ForegroundColor Yellow
}
$commit = (git rev-parse --short HEAD 2>$null)

# --- 2. Parámetros UAT -----------------------------------------------------
$ApiBaseUrl = Assert-LocalUrl $ApiBaseUrl 'API_BASE_URL'
$AppBaseUrl = Assert-LocalUrl $AppBaseUrl 'APP_BASE_URL'
Write-Host "UAT -> API=$ApiBaseUrl APP=$AppBaseUrl"

# --- 3. Copia en ruta corta (MAX_PATH) -------------------------------------
$appSrc = Join-Path $repoRoot 'apps\fulltech_app'
if (-not $SkipSync) {
  Write-Host "Sincronizando a ruta corta $ShortRoot ..."
  $null = robocopy $appSrc $ShortRoot /MIR /NFL /NDL /NJH /NJS /NP /XD build .dart_tool .git /XF *.log
  if ($LASTEXITCODE -ge 8) { Fail "robocopy falló con código $LASTEXITCODE." }
} elseif (-not (Test-Path (Join-Path $ShortRoot 'pubspec.yaml'))) {
  Fail "La copia corta no existe; ejecuta sin -SkipSync."
}

$appSo = Join-Path $ShortRoot 'build\windows\x64\runner\Release\data\app.so'
$exe   = Join-Path $ShortRoot 'build\windows\x64\runner\Release\fullpos_cloud.exe'
$before = if (Test-Path $appSo) { (Get-Item $appSo).LastWriteTimeUtc } else { [DateTime]::MinValue }
$started = Get-Date

# --- 4. Compilación --------------------------------------------------------
Push-Location $ShortRoot
try {
  Write-Host "Compilando UAT blindado..."
  & flutter build windows --release `
    --dart-define=APP_ENV=uat `
    --dart-define=FULLPOS_UAT_PROFILE=true `
    --dart-define=API_BASE_URL=$ApiBaseUrl `
    --dart-define=APP_BASE_URL=$AppBaseUrl
  $buildExit = $LASTEXITCODE
} finally {
  Pop-Location
}
if ($buildExit -ne 0) { Fail "flutter build falló con código $buildExit." }

# --- 5. Verificar artefactos frescos ---------------------------------------
if (-not (Test-Path $appSo)) { Fail "No se generó app.so." }
if (-not (Test-Path $exe))   { Fail "No se generó el ejecutable." }
$exeAfter = (Get-Item $exe).LastWriteTimeUtc
$after = (Get-Item $appSo).LastWriteTimeUtc

# `app.so` es el snapshot AOT de Dart: solo se reescribe cuando cambia Dart. Un
# cambio EXCLUSIVAMENTE nativo (por ejemplo `windows/runner/main.cpp`) reconstruye
# el .exe pero deja `app.so` intacto a propósito, y eso NO es un artefacto
# obsoleto. Se exige frescura de lo que realmente cambió, sin relajar la garantía
# de que nunca se publica un snapshot Dart viejo.
$dartNewest = Get-ChildItem (Join-Path $ShortRoot 'lib'), (Join-Path $ShortRoot 'pubspec.yaml') `
  -Recurse -File -ErrorAction SilentlyContinue |
  Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 1
$dartChangedSinceSnapshot = $dartNewest -and ($dartNewest.LastWriteTimeUtc -gt $before)

if ($dartChangedSinceSnapshot) {
  if ($after -le $before) {
    Fail "app.so NO se regeneró aunque cambió Dart (artefacto antiguo reutilizado)."
  }
  if ($after -lt $started.AddSeconds(-5)) {
    Fail "app.so es anterior al inicio del build: artefacto obsoleto."
  }
} else {
  if ($exeAfter -le $before) {
    Fail "El ejecutable no se regeneró: el build no produjo binario nuevo."
  }
  Write-Host "  app.so sin cambios (no cambió Dart): se valida la frescura del .exe."
}

# --- 6. Copia identificada como UAT ----------------------------------------
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$dist = Join-Path $DistRoot "FullPOS-UAT-$stamp"
New-Item -ItemType Directory -Path $dist -Force | Out-Null
Copy-Item -Path (Join-Path $ShortRoot 'build\windows\x64\runner\Release\*') -Destination $dist -Recurse -Force

# --- 7. Manifiesto sin secretos -------------------------------------------
$manifest = [ordered]@{
  generatedAtUtc = (Get-Date).ToUniversalTime().ToString('o')
  type           = 'FULLPOS_ECF_UAT'
  branch         = $branch
  commit         = $commit
  appEnv         = 'uat'
  uatProfile     = $true
  apiBaseUrl     = $ApiBaseUrl
  appBaseUrl     = $AppBaseUrl
  appSoSha256    = (Get-FileHash $appSo -Algorithm SHA256).Hash
  exeSha256      = (Get-FileHash (Join-Path $ShortRoot 'build\windows\x64\runner\Release\fullpos_cloud.exe') -Algorithm SHA256).Hash
  distPath       = $dist
  warnings       = @(
    'Verifica el tráfico real con Get-NetTCPConnection antes de usar la app.',
    'Solo 127.0.0.1:4004 es un destino válido.'
  )
}
$manifestPath = Join-Path $dist 'UAT_BUILD_MANIFEST.json'
$manifest | ConvertTo-Json -Depth 5 | Set-Content -Path $manifestPath -Encoding UTF8

Write-Host ""
Write-Host "OK: build UAT blindado" -ForegroundColor Green
Write-Host "  app.so     : $appSo ($($after.ToString('u')))"
Write-Host "  distribuible: $dist"
Write-Host "  manifiesto : $manifestPath"
Write-Host "  Verifica el tráfico antes de usar la app (solo 127.0.0.1:4004)."
