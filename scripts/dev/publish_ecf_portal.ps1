# Publica el portal de certificación DOSA en el dominio autorizado.
#
# El portal es UNA página estática que ocupa `/ecf/certificacion` dentro del
# nginx que ya sirve la PWA. No reemplaza la app, no reconstruye la imagen, no
# reinicia el servicio y no toca el backend.
#
# La página no lleva credenciales: la clave publicable de DOSA y la base de la
# API se inyectan aquí, desde `apps/fulltech_app/.env.dosa.local` (ignorado por
# git), y nunca se escriben en el repositorio.
#
# Uso (dry-run por defecto; solo ejecuta con -Apply y autorización):
#   pwsh -File scripts/dev/publish_ecf_portal.ps1
#   pwsh -File scripts/dev/publish_ecf_portal.ps1 -Apply
#
# Reversión: borrar la carpeta remota. Ver docs/ECF_DOSA_AUTHORIZED_DOMAIN_TEST.md.

[CmdletBinding()]
param(
  [string] $SshHost = 'root@31.97.99.70',
  [string] $SshKey = "$env:USERPROFILE\.ssh\daleventas_codex",
  [string] $ServiceFilter = 'daleventapos_pwa',
  [string] $RemoteRoot = '/usr/share/nginx/html/ecf/certificacion',
  # En produccion la API vive en el mismo origen, bajo /api.
  [string] $ApiBase = '/api',
  [switch] $Apply
)

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$template = Join-Path $repoRoot 'deploy/ecf-certificacion/index.html'
$localEnv = Join-Path $repoRoot 'apps/fulltech_app/.env.dosa.local'

if (-not (Test-Path $template)) { throw "No se encontro la plantilla: $template" }
if (-not (Test-Path $localEnv)) { throw "Falta la clave publicable local: $localEnv" }

$line = Get-Content $localEnv | Where-Object { $_ -match '^\s*DOSA_ASSISTANT_PUBLISHABLE_KEY\s*=' } | Select-Object -First 1
if (-not $line) { throw 'El archivo local no define DOSA_ASSISTANT_PUBLISHABLE_KEY.' }
$key = (($line -split '=', 2)[1]).Trim().Trim('"').Trim("'")

if ($key.StartsWith('sk_')) { throw 'Se detecto una clave secreta: el portal solo admite la publicable (pk_).' }
if (-not $key.StartsWith('pk_')) { throw 'La clave publicable debe empezar por pk_.' }

$masked = $key.Substring(0, 8) + '...'
Write-Host "Clave publicable: $masked (longitud $($key.Length))"
Write-Host "API base:          $ApiBase"

$rendered = (Get-Content $template -Raw).
  Replace('__DOSA_PUBLISHABLE_KEY__', $key).
  Replace('__API_BASE__', $ApiBase)

$staging = Join-Path $env:TEMP 'ecf-portal-publish'
New-Item -ItemType Directory -Force -Path $staging | Out-Null
$renderedFile = Join-Path $staging 'index.html'
Set-Content -Path $renderedFile -Value $rendered -Encoding utf8

Write-Host "Pagina preparada: $renderedFile"
Write-Host "Destino remoto:   $SshHost : $RemoteRoot/index.html"
Write-Host ''

$resolver = "docker ps --filter name=$ServiceFilter --format '{{.Names}}' | head -n 1"

Write-Host '--- PLAN (nada de esto se ha ejecutado) ---'
Write-Host "  1) resolver contenedor: ssh $SshHost `"$resolver`""
Write-Host "  2) mkdir -p $RemoteRoot dentro del contenedor"
Write-Host "  3) copiar SOLO index.html a $RemoteRoot"
Write-Host '  4) verificar: curl -I https://fullposcloud.fulltechrd.com/ecf/certificacion/'
Write-Host "  5) reversion: docker exec <container> rm -rf /usr/share/nginx/html/ecf"
Write-Host ''
Write-Host 'RESTRICCION DE ACCESO: el portal exige un ticket de un solo uso emitido'
Write-Host 'por la API para un administrador con manageEcfOnboarding. Sin ticket no'
Write-Host 'muestra nada. Si ademas se quiere cerrar el acceso a nivel de red, hace'
Write-Host 'falta un bloque location con auth_basic (ver docs).'
Write-Host ''

if (-not $Apply) {
  Write-Host 'DRY-RUN: para ejecutar hace falta -Apply y autorizacion explicita.' -ForegroundColor Yellow
  exit 0
}

Write-Host 'APLICANDO (autorizacion asumida y registrada).' -ForegroundColor Yellow

function Invoke-Remote([string] $command) {
  & ssh -i $SshKey -o BatchMode=yes $SshHost $command
  if ($LASTEXITCODE -ne 0) { throw "Fallo el comando remoto: $command" }
}

$container = (& ssh -i $SshKey -o BatchMode=yes $SshHost $resolver).Trim()
if (-not $container) { throw "No se pudo resolver el contenedor con filtro '$ServiceFilter'." }
Write-Host "Contenedor: $container"

Invoke-Remote "docker exec $container mkdir -p $RemoteRoot"
$remoteTmp = '/tmp/ecf-portal-index.html'
& scp -i $SshKey -o BatchMode=yes $renderedFile "${SshHost}:$remoteTmp"
if ($LASTEXITCODE -ne 0) { throw 'No se pudo copiar la pagina al servidor.' }
Invoke-Remote "docker cp $remoteTmp ${container}:$RemoteRoot/index.html && rm -f $remoteTmp"

Write-Host 'Publicado. Verifica con: curl -I https://fullposcloud.fulltechrd.com/ecf/certificacion/'
Write-Host "Reversion: ssh -i `"$SshKey`" $SshHost `"docker exec $container rm -rf /usr/share/nginx/html/ecf`""
