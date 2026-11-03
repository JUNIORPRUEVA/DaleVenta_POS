# Despliegue de las migraciones e-CF en produccion. DRY-RUN POR DEFECTO.
#
# No hace nada sin -Apply y sin un texto de autorizacion explicito. No toca el
# servicio de la API (eso es un paso aparte, deliberadamente manual).
#
# Secuencia:
#   1. preflight (recalcula pendientes; aborta si no son exactamente las esperadas)
#   2. backup completo + verificacion de que el dump se puede leer
#   3. migraciones en un contenedor desechable de la imagen candidata,
#      con lock_timeout para no congelar la aplicacion si hay una transaccion viva
#   4. verificacion del esquema resultante
#
# Uso:
#   pwsh -File scripts/ops/ecf-deploy-migrations.ps1                 # solo muestra el plan
#   pwsh -File scripts/ops/ecf-deploy-migrations.ps1 -Apply `
#        -Authorization "Autorizado por <nombre>, <fecha>, alcance: ..."
#
# Requiere que la imagen candidata YA contenga las 25 migraciones.

[CmdletBinding()]
param(
  [string] $SshHost = 'root@31.97.99.70',
  [string] $SshKey = "$env:USERPROFILE\.ssh\daleventas_codex",
  [string] $DbFilter = 'daleventapos_database',
  [string] $ApiFilter = 'daleventapos_backend',
  [string] $ApiImage = 'easypanel/daleventapos/api:latest',
  [int] $ExpectedCount = 25,
  [string] $LockTimeout = '5s',
  [string] $Authorization,
  [switch] $Apply
)

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$preflight = Join-Path $repoRoot 'scripts/ops/ecf-migrations-preflight.ps1'
if (-not (Test-Path $preflight)) { throw "Falta $preflight" }

function Invoke-Remote([string] $command) {
  return & ssh -i $SshKey -o BatchMode=yes -o ConnectTimeout=15 $SshHost $command 2>&1
}

Write-Host '=== 1. Preflight (solo lectura) ===' -ForegroundColor Cyan
& pwsh -NoProfile -File $preflight -SshHost $SshHost -SshKey $SshKey -DbFilter $DbFilter -ExpectedCount $ExpectedCount
if ($LASTEXITCODE -ne 0) {
  Write-Error 'El preflight no dio GO. No se hace nada.'
  exit 1
}

if (-not $Apply) {
  Write-Host ''
  Write-Host 'DRY-RUN. Lo que haria con -Apply:' -ForegroundColor Yellow
  Write-Host '  2. pg_dump -Fc completo de la base + pg_restore --list para verificar el dump'
  Write-Host "  3. docker run --rm --network <red> -e DATABASE_URL=<desde el backend> -e PGOPTIONS='-c lock_timeout=$LockTimeout' $ApiImage npx prisma migrate deploy"
  Write-Host '  4. verificacion: 24 tablas ecf_*, columna item_type_snapshot, 0 migraciones fallidas'
  Write-Host ''
  Write-Host 'No se ha ejecutado nada. Falta -Apply y -Authorization "<texto>".' -ForegroundColor Yellow
  exit 0
}

if ([string]::IsNullOrWhiteSpace($Authorization) -or $Authorization.Trim().Length -lt 20) {
  Write-Error 'Falta -Authorization con el texto de autorizacion explicita (>= 20 caracteres).'
  exit 1
}
Write-Host ''
Write-Host ('AUTORIZACION REGISTRADA: ' + $Authorization.Trim()) -ForegroundColor Green

# --- Resolver contenedores -------------------------------------------------
$db = ((Invoke-Remote "docker ps --filter name=$DbFilter --format '{{.Names}}' | head -n 1") -join "`n").Trim()
$api = ((Invoke-Remote "docker ps --filter name=$ApiFilter --format '{{.Names}}' | head -n 1") -join "`n").Trim()
if (-not $db) { Write-Error 'No se encontro el contenedor de base de datos.'; exit 1 }
if (-not $api) { Write-Error 'No se encontro el contenedor de la API.'; exit 1 }
Write-Host "BD: $db"
Write-Host "API: $api"

$net = ((Invoke-Remote "docker inspect $api --format '{{range `$k,`$v := .NetworkSettings.Networks}}{{`$k}} {{end}}'") -join "`n").Trim().Split(' ')[0]
if (-not $net) { Write-Error 'No se pudo determinar la red de la API.'; exit 1 }
Write-Host "Red: $net"

# --- 2. Backup -------------------------------------------------------------
Write-Host ''
Write-Host '=== 2. Backup completo ===' -ForegroundColor Cyan
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$dumpName = "daleventa-pre-ecf-$stamp.dump"
$backupCmd = "set -e; docker exec $db sh -c 'pg_dump -U `$POSTGRES_USER -d `$POSTGRES_DB -Fc -f /tmp/$dumpName'; " +
  "docker cp ${db}:/tmp/$dumpName /root/$dumpName; " +
  "docker exec $db rm -f /tmp/$dumpName; " +
  "docker exec $db sh -c 'pg_restore --list /dev/stdin < /dev/null' >/dev/null 2>&1 || true; " +
  "docker run --rm -v /root:/b postgres:17 sh -c 'pg_restore --list /b/$dumpName | head -n 5 && pg_restore --list /b/$dumpName | wc -l'"
$backupOut = Invoke-Remote $backupCmd
if ($LASTEXITCODE -ne 0) { Write-Error "El backup fallo: $backupOut"; exit 1 }
Write-Host ($backupOut -join "`n")
Write-Host "Backup en /root/$dumpName" -ForegroundColor Green

# --- 3. Migraciones --------------------------------------------------------
Write-Host ''
Write-Host '=== 3. Migraciones (lock_timeout=' + $LockTimeout + ') ===' -ForegroundColor Cyan
$migrateCmd = "set -e; DBURL=`$(docker exec $api printenv DATABASE_URL); test -n `"`$DBURL`" || { echo SIN_DATABASE_URL; exit 4; }; " +
  "docker run --rm --network $net -e DATABASE_URL=`"`$DBURL`" -e PGOPTIONS='-c lock_timeout=$LockTimeout' $ApiImage npx prisma migrate deploy"
$migrateOut = Invoke-Remote $migrateCmd
$migrateExit = $LASTEXITCODE
Write-Host ($migrateOut -join "`n")
if ($migrateExit -ne 0) {
  Write-Host ''
  Write-Error "Las migraciones fallaron (exit $migrateExit). No se toco el servicio de la API."
  Write-Host 'Si el error es lock timeout, no se aplico nada: reintenta en un momento de menos trafico.'
  Write-Host "Reversion: el backup esta en /root/$dumpName (no hace falta restaurarlo si no se aplico nada)."
  exit 1
}

# --- 4. Verificacion -------------------------------------------------------
Write-Host ''
Write-Host '=== 4. Verificacion del esquema ===' -ForegroundColor Cyan
$verifySql = @'
\pset pager off
SELECT 'tablas_ecf' AS k, count(*)::text AS v FROM pg_tables WHERE schemaname='public' AND tablename LIKE 'ecf%'
UNION ALL SELECT 'columna_saleitem', count(*)::text FROM information_schema.columns
  WHERE table_schema='public' AND table_name='SaleItem' AND column_name='item_type_snapshot'
UNION ALL SELECT 'migraciones_fallidas', count(*)::text FROM _prisma_migrations
  WHERE finished_at IS NULL AND rolled_back_at IS NULL
UNION ALL SELECT 'portal_tickets', (to_regclass('public.ecf_certification_portal_tickets') IS NOT NULL)::text
UNION ALL SELECT 'portal_sessions', (to_regclass('public.ecf_certification_portal_sessions') IS NOT NULL)::text;
'@
$verifyFile = Join-Path $env:TEMP 'ecf-verify.sql'
Set-Content -Path $verifyFile -Value $verifySql -Encoding utf8
& scp -i $SshKey -o BatchMode=yes $verifyFile "${SshHost}:/tmp/ecf-verify.sql" 2>&1 | Out-Null
$verifyCmd = "docker cp /tmp/ecf-verify.sql ${db}:/tmp/ecf-verify.sql && docker exec -i ${db} sh -c 'psql -U `$POSTGRES_USER -d `$POSTGRES_DB -q -t -A -F=| -f /tmp/ecf-verify.sql'; docker exec ${db} rm -f /tmp/ecf-verify.sql; rm -f /tmp/ecf-verify.sql"
$verifyOut = Invoke-Remote $verifyCmd
Write-Host ($verifyOut -join "`n")

$failed = ($verifyOut | Where-Object { $_ -match '^migraciones_fallidas\|(\d+)' } | ForEach-Object { [int]($_.Split('|')[1]) })
if ($failed -ne 0) {
  Write-Error 'Hay migraciones sin terminar. Detente y revisa antes de desplegar la API.'
  exit 1
}

Write-Host ''
Write-Host '=== 5. Siguiente paso (manual, deliberado) ===' -ForegroundColor Cyan
Write-Host 'Desplegar la imagen nueva de la API y comprobar:'
Write-Host '  /health -> 200'
Write-Host '  /ecf/certification-portal/context -> 401 (ruta viva y cerrada)'
Write-Host 'Luego, y solo si se autoriza el piloto:'
Write-Host '  ECF_PORTAL_PILOT_COMPANY_IDS=165e3fca-6225-479b-8805-d2205f10536c'
Write-Host '  pwsh -File scripts/dev/publish_ecf_portal.ps1 -Apply'
Write-Host ''
Write-Host 'Reversion: volver a la imagen anterior por tag. El esquema nuevo es'
Write-Host 'compatible hacia atras. NO revertir migraciones ni hacer DROP.'
Write-Host "Backup disponible en /root/$dumpName" -ForegroundColor Green
