# Pone una empresa de la base LOCAL en el estado de licencia que se quiera
# probar, para recorrer en la app las pantallas de vencida, demo terminada y
# cuenta suspendida con datos reales (no simulados).
#
# Solo toca bases cuyo nombre termine en `_local` (falla cerrado): nunca UAT ni
# produccion.
#
#   powershell -File scripts/license-state.ps1 -State blocked
#   powershell -File scripts/license-state.ps1 -State trial-expired
#   powershell -File scripts/license-state.ps1 -State expired
#   powershell -File scripts/license-state.ps1 -State active
#
# Despues de cambiarlo, reinicia la app (o pulsa actualizar en Planes) para que
# vuelva a pedir `GET /license`.
param(
  [Parameter(Mandatory = $true)]
  [ValidateSet('active', 'expired', 'trial-expired', 'blocked')]
  [string] $State,
  [string] $Company = '11111111-1111-4111-8111-111111111111',
  [string] $Database = 'planes_local',
  [string] $Container = 'daleventas_uat_postgres',
  [string] $DbUser = 'daleventa_uat_user'
)

if ($Database -notmatch '_local$') {
  throw "Solo se permiten bases locales (nombre terminado en _local). Recibido: $Database"
}

$common = @"
  license_key = null,
  license_activated_at = null,
  max_users = 20,
  max_products = 1000
"@

switch ($State) {
  'active' {
    $set = "$common, status = 'ACTIVE', license_status = 'ACTIVE', license_expires_at = now() + interval '20 days', trial_started_at = null, trial_ends_at = null, license_blocked_at = null"
  }
  'expired' {
    # Plan pagado que vencio: pantalla «Tu plan ... vencio».
    $set = "$common, status = 'ACTIVE', license_status = 'ACTIVE', license_expires_at = now() - interval '3 days', trial_started_at = null, trial_ends_at = null, license_blocked_at = null"
  }
  'trial-expired' {
    # Demo de 7 dias terminada: pantalla «Tu demo de 7 dias termino».
    $set = "$common, status = 'ACTIVE', license_status = 'TRIAL', license_expires_at = null, trial_started_at = now() - interval '10 days', trial_ends_at = now() - interval '3 days', license_blocked_at = null"
  }
  'blocked' {
    # Cuenta suspendida: pantalla «Tu cuenta esta suspendida».
    $set = "$common, status = 'SUSPENDED', license_status = 'BLOCKED', license_expires_at = null, trial_started_at = null, trial_ends_at = null, license_blocked_at = now()"
  }
}

$sql = "update companies set $set where id = '$Company' returning license_status, status, coalesce(license_expires_at::text, 'sin vencimiento'), coalesce(trial_ends_at::text, 'sin demo')"
$result = docker exec $Container psql -U $DbUser -d $Database -tAc $sql
if ($LASTEXITCODE -ne 0) { throw "No se pudo actualizar la empresa $Company" }
Write-Output "Estado aplicado ('$State'): $result"
Write-Output 'Reinicia la app para que vuelva a pedir GET /license.'
