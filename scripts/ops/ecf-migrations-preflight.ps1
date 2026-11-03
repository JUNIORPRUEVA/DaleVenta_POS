# Preflight de migraciones e-CF contra produccion. SOLO LECTURA.
#
# Compara lo que el repositorio espera con lo que produccion tiene registrado y
# se detiene si algo no cuadra. No modifica la base, no aplica migraciones y no
# toca `_prisma_migrations`.
#
# Uso:
#   pwsh -File scripts/ops/ecf-migrations-preflight.ps1
#   pwsh -File scripts/ops/ecf-migrations-preflight.ps1 -ExpectedCount 25
#
# Salida: 0 = listo para autorizar; 1 = hay divergencia, NO migrar.

[CmdletBinding()]
param(
  [string] $SshHost = 'root@31.97.99.70',
  [string] $SshKey = "$env:USERPROFILE\.ssh\daleventas_codex",
  [string] $DbFilter = 'daleventapos_database',
  [int] $ExpectedCount = 25
)

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$migrationsDir = Join-Path $repoRoot 'apps/api/prisma/migrations'
if (-not (Test-Path $migrationsDir)) { throw "No se encontro $migrationsDir" }

function Invoke-Remote([string] $command) {
  return & ssh -i $SshKey -o BatchMode=yes -o ConnectTimeout=15 $SshHost $command 2>&1
}

Write-Host 'Leyendo el historial de produccion (solo lectura)...'

$container = ((Invoke-Remote "docker ps --filter name=$DbFilter --format '{{.Names}}' | head -n 1") -join "`n").Trim()
if (-not $container) { Write-Error 'No se encontro el contenedor de la base de datos de produccion.'; exit 2 }

$sql = "SELECT migration_name FROM _prisma_migrations WHERE finished_at IS NOT NULL AND rolled_back_at IS NULL ORDER BY migration_name;`n"
$localSql = Join-Path $env:TEMP 'ecf-preflight-migrations.sql'
Set-Content -Path $localSql -Value $sql -Encoding utf8 -NoNewline

& scp -i $SshKey -o BatchMode=yes $localSql "${SshHost}:/tmp/ecf-preflight.sql" 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) { Write-Error 'No se pudo copiar el SQL de preflight al servidor.'; exit 2 }

$remote = "docker cp /tmp/ecf-preflight.sql ${container}:/tmp/ecf-preflight.sql && docker exec -i ${container} sh -c 'psql -U `$POSTGRES_USER -d `$POSTGRES_DB -q -t -A -f /tmp/ecf-preflight.sql' ; docker exec ${container} rm -f /tmp/ecf-preflight.sql ; rm -f /tmp/ecf-preflight.sql"
$output = Invoke-Remote $remote
if ($LASTEXITCODE -ne 0) { Write-Error "No se pudo leer produccion: $output"; exit 2 }

$applied = @($output | ForEach-Object { "$_".Trim() } | Where-Object { $_ -match '^\d{14}_' })
if ($applied.Count -eq 0) { Write-Error 'Produccion no devolvio ninguna migracion aplicada.'; exit 2 }

$folders = @(Get-ChildItem $migrationsDir -Directory | Select-Object -ExpandProperty Name)
$pending = @($folders | Where-Object { $applied -notcontains $_ } | Sort-Object)
$legacy = @($applied | Where-Object { $folders -notcontains $_ })

Write-Host ''
Write-Host ("Aplicadas y vigentes en produccion : " + $applied.Count)
Write-Host ("Migraciones en el repositorio      : " + $folders.Count)
Write-Host ("Pendientes de aplicar              : " + $pending.Count)
Write-Host ("Historial antiguo sin carpeta      : " + $legacy.Count)
Write-Host ''

if ($pending.Count -eq 0) {
  Write-Host 'No hay migraciones pendientes: nada que desplegar.' -ForegroundColor Green
  exit 0
}

Write-Host 'Pendientes, en orden:' -ForegroundColor Yellow
$pending | ForEach-Object { Write-Host ("  - " + $_) }

$noEcf = @($pending | Where-Object { $_ -notmatch 'ecf|portal' })
$risky = @()
foreach ($name in $pending) {
  $file = Join-Path $migrationsDir (Join-Path $name 'migration.sql')
  if (-not (Test-Path $file)) { continue }
  $text = Get-Content $file -Raw
  if ([regex]::IsMatch($text, 'ALTER TABLE "(?!ecf)[^"]+"')) { $risky += $name }
}

Write-Host ''
if ($noEcf.Count -gt 0) {
  Write-Host 'AVISO: hay pendientes que no parecen del modulo e-CF:' -ForegroundColor Yellow
  $noEcf | ForEach-Object { Write-Host ('  ! ' + $_) }
}
if ($risky.Count -gt 0) {
  Write-Host 'AVISO: estas tocan tablas EXISTENTES (revisar antes de aplicar):' -ForegroundColor Yellow
  $risky | ForEach-Object { Write-Host ('  ! ' + $_) }
} else {
  Write-Host 'Ninguna pendiente altera tablas existentes fuera de e-CF.' -ForegroundColor Green
}

Write-Host ''
if ($pending.Count -ne $ExpectedCount) {
  Write-Host ("NO-GO: se esperaban $ExpectedCount pendientes y hay " + $pending.Count + '.') -ForegroundColor Red
  Write-Host 'Revisa antes de migrar: puede haber cambios de rama o migraciones nuevas.' -ForegroundColor Red
  exit 1
}

Write-Host ("GO del preflight: $ExpectedCount migraciones pendientes, tal y como se esperaba.") -ForegroundColor Green
Write-Host 'Nada se ha modificado. La ejecucion requiere scripts/ops/ecf-deploy-migrations.ps1 -Apply.'
exit 0
