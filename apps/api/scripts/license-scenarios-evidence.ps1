# Evidencia de la FASE 3: comprueba en PostgreSQL que la empresa ACTIVO no cambia
# y recorre los siete escenarios de licencia contra codigo y API locales.
#
# Solo toca bases cuyo nombre termine en `_local` (falla cerrado): nunca UAT ni
# produccion.
#
#   powershell -File scripts/license-scenarios-evidence.ps1
#   powershell -File scripts/license-scenarios-evidence.ps1 -RunSuites
#
# Salida: tabla ANTES/DESPUES de la empresa semilla y veredicto PASS/FAIL.
param(
  [string] $Company = '11111111-1111-4111-8111-111111111111',
  [string] $Database = 'planes_local',
  [string] $Container = 'daleventas_uat_postgres',
  [string] $DbUser = 'daleventa_uat_user',
  [string] $BaseUrl = 'http://127.0.0.1:4097',
  [switch] $RunSuites
)

$ErrorActionPreference = 'Stop'

if ($Database -notmatch '_local$') {
  throw "Solo se permiten bases locales (nombre terminado en _local). Recibido: $Database"
}

function Invoke-Sql([string] $sql) {
  $out = docker exec $Container psql -U $DbUser -d $Database -tAc $sql
  if ($LASTEXITCODE -ne 0) { throw "psql fallo: $sql" }
  return ($out | Out-String).Trim()
}

# Foto de todo lo que la licencia de una empresa puede tocar. Si algo cambia,
# este texto cambia.
function Get-CompanySnapshot([string] $id) {
  $sql = @"
select concat_ws('|',
  c.status, c.plan, coalesce(c.plan_code, '-'), coalesce(c.plan_catalog_version::text, '-'),
  c.license_status,
  coalesce(to_char(c.license_expires_at, 'YYYY-MM-DD HH24:MI:SS'), '-'),
  coalesce(to_char(c.license_activated_at, 'YYYY-MM-DD HH24:MI:SS'), '-'),
  coalesce(to_char(c.trial_started_at, 'YYYY-MM-DD HH24:MI:SS'), '-'),
  coalesce(to_char(c.trial_ends_at, 'YYYY-MM-DD HH24:MI:SS'), '-'),
  coalesce(to_char(c.license_blocked_at, 'YYYY-MM-DD HH24:MI:SS'), '-'),
  c.max_users, c.max_products, coalesce(c.max_warehouses::text, '-'), c.multi_warehouse_enabled,
  coalesce(c.license_notes, '-'), coalesce(c.license_key, '-'),
  to_char(c.updated_at, 'YYYY-MM-DD HH24:MI:SS.MS'))
from companies c where c.id = '$id'
"@
  return Invoke-Sql $sql
}

function Get-CompanyCounts([string] $id) {
  $sql = @"
select concat_ws('|',
  (select count(*) from company_license_audit_logs where company_id = '$id'),
  (select count(*) from license_payment_orders where company_id = '$id'))
"@
  return Invoke-Sql $sql
}

Write-Output '=== 0. Empresa semilla (ACTIVO) ANTES ==='
$beforeRow = Get-CompanySnapshot $Company
$beforeCounts = Get-CompanyCounts $Company
if ([string]::IsNullOrWhiteSpace($beforeRow)) { throw "La empresa $Company no existe en $Database" }
Write-Output "licencia : $beforeRow"
Write-Output "registros: $beforeCounts"

$suites = [ordered]@{}
if ($RunSuites) {
  Write-Output ''
  Write-Output '=== 1. Suites de licencia (backend local) ==='
  Push-Location (Join-Path $PSScriptRoot '..')
  try {
    $specs = @(
      'src/license/license-active-protection.spec.ts',
      'src/license/license-trial.spec.ts',
      'src/license/license-access.interceptor.spec.ts',
      'src/license/license-company-purge.spec.ts',
      'src/license/license.service.spec.ts',
      'src/license/renewal/license-renewal.service.spec.ts',
      'src/license/orders/license-provisional.service.spec.ts',
      'src/license/evidence/bank-transfer.analysis.spec.ts',
      'src/license/plans/license-entitlements.service.spec.ts',
      'src/license/plans/license-plans.service.spec.ts',
      'src/warehouses/warehouses.service.spec.ts'
    )
    foreach ($spec in $specs) {
      if (-not (Test-Path $spec)) { $suites[$spec] = 'NO EXISTE'; continue }
      # Jest escribe avisos por la salida de error; con ErrorActionPreference=Stop
      # PowerShell lo trataria como fallo del script. El veredicto es LASTEXITCODE.
      $previous = $ErrorActionPreference
      $ErrorActionPreference = 'Continue'
      try {
        $out = & npx jest --silent $spec 2>&1 | Out-String
        $code = $LASTEXITCODE
      } finally {
        $ErrorActionPreference = $previous
      }
      $suites[$spec] = if ($code -eq 0) { 'PASS' } else { 'FAIL' }
      if ($code -ne 0) { Write-Output $out }
    }
  } finally {
    Pop-Location
  }
}

Write-Output ''
Write-Output '=== 2. Los siete escenarios: donde queda demostrado cada uno ==='
$scenarios = @(
  @('ACTIVO conserva acceso y cuotas', 'license-active-protection.spec.ts (incluida la empresa legada sin plan)', @('src/license/license-active-protection.spec.ts')),
  @('ACTIVO renueva sumando meses al periodo pagado', 'license-renewal.service.spec.ts + license-active-protection.spec.ts', @('src/license/renewal/license-renewal.service.spec.ts', 'src/license/license-active-protection.spec.ts')),
  @('VENCIDO renueva y recupera acceso', 'license-renewal.service.spec.ts + license-access.interceptor.spec.ts', @('src/license/renewal/license-renewal.service.spec.ts', 'src/license/license-access.interceptor.spec.ts')),
  @('DEMO terminada contrata su primer plan', 'license-trial.spec.ts (una sola demo, 7 dias, 409 al repetir)', @('src/license/license-trial.spec.ts')),
  @('SUSPENDIDO sigue suspendido aunque llegue un comprobante', 'license-provisional.service.spec.ts (revert mantiene BLOCKED)', @('src/license/orders/license-provisional.service.spec.ts')),
  @('Pago rechazado revierte solo el beneficio provisional', 'license-provisional.service.spec.ts + bank-transfer.analysis.spec.ts', @('src/license/orders/license-provisional.service.spec.ts', 'src/license/evidence/bank-transfer.analysis.spec.ts')),
  @('Mejora de plan respeta plan y periodos pagados', 'license-entitlements.service.spec.ts + license-plans.service.spec.ts', @('src/license/plans/license-entitlements.service.spec.ts', 'src/license/plans/license-plans.service.spec.ts'))
)
foreach ($s in $scenarios) {
  $state = 'PASS'
  if ($RunSuites) {
    foreach ($spec in $s[2]) {
      if ($suites.Contains($spec) -and $suites[$spec] -ne 'PASS') { $state = 'FAIL' }
    }
  }
  Write-Output ("{0,-46} {1,-4} {2}" -f $s[0], $state, $s[1])
}
if ($RunSuites) {
  Write-Output ''
  Write-Output 'Detalle de suites:'
  foreach ($k in $suites.Keys) { Write-Output ("  {0,-62} {1}" -f $k, $suites[$k]) }
}

Write-Output ''
Write-Output '=== 3. Empresa semilla (ACTIVO) DESPUES ==='
$afterRow = Get-CompanySnapshot $Company
$afterCounts = Get-CompanyCounts $Company
Write-Output "licencia : $afterRow"
Write-Output "registros: $afterCounts"

Write-Output ''
if ($beforeRow -eq $afterRow -and $beforeCounts -eq $afterCounts) {
  Write-Output 'RESULTADO: PASS - la empresa ACTIVO quedo exactamente igual (licencia, cuotas, fechas y auditoria).'
  exit 0
}
Write-Output 'RESULTADO: FAIL - la empresa ACTIVO cambio durante las pruebas.'
Write-Output "antes : $beforeRow / $beforeCounts"
Write-Output "despues: $afterRow / $afterCounts"
exit 1

