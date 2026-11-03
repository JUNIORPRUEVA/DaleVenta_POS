# Prueba de acceso al portal de certificación con una cuenta REAL de FULLTECH SRL.
#
# La ejecuta el responsable desde su equipo: el script pide las credenciales por
# variables de entorno (o por parámetro) y NUNCA las imprime, ni el ticket, ni la
# sesión. No abre postulaciones, no carga certificados, no paga y no emite.
#
# Uso:
#   $env:FULLPOS_SMOKE_EMAIL = 'cuenta-admin-de-fulltech'
#   $env:FULLPOS_SMOKE_PASSWORD = '...'        # no se escribe en el chat
#   pwsh -File scripts/ops/dosa-portal-smoke.ps1
#
# Qué comprueba:
#   1. login del administrador
#   2. emisión del ticket de un solo uso
#   3. canje del ticket por sesión
#   4. identidad devuelta == companyId del piloto (FULLTECH SRL)
#   5. el asistente está "listo para montar" (el portal lo montará en el navegador)
#   6. cierre de sesión y rechazo posterior
#
# Lo que NO puede comprobar este script: el `cert:ready` del componente DOSA, que
# solo ocurre en el navegador. Para eso hay que abrir la URL del portal que el
# script imprime al final.

[CmdletBinding()]
param(
  [string] $ApiBase = 'https://fullposcloud.fulltechrd.com/api',
  [string] $Email = $env:FULLPOS_SMOKE_EMAIL,
  [string] $Password = $env:FULLPOS_SMOKE_PASSWORD,
  [string] $ExpectedCompanyId = '165e3fca-6225-479b-8805-d2205f10536c'
)

$ErrorActionPreference = 'Stop'
$results = New-Object System.Collections.Generic.List[string]
function Ok($m) { $results.Add("OK   $m"); Write-Host ("OK   " + $m) -ForegroundColor Green }
function Bad($m) { $results.Add("FALLO $m"); Write-Host ("FALLO " + $m) -ForegroundColor Red }

if ([string]::IsNullOrWhiteSpace($Email) -or [string]::IsNullOrWhiteSpace($Password)) {
  Write-Error 'Falta la cuenta de prueba: define FULLPOS_SMOKE_EMAIL y FULLPOS_SMOKE_PASSWORD.'
  exit 1
}

function Post($path, $body, $token) {
  $headers = @{ 'Content-Type' = 'application/json' }
  if ($token) { $headers['Authorization'] = "Bearer $token" }
  try {
    $r = Invoke-WebRequest -Uri "$ApiBase$path" -Method POST -Headers $headers `
      -Body ($body | ConvertTo-Json -Compress) -UseBasicParsing -TimeoutSec 30
    return @{ ok = $true; status = [int]$r.StatusCode; body = ($r.Content | ConvertFrom-Json) }
  } catch {
    $status = 0
    if ($_.Exception.Response) { $status = [int]$_.Exception.Response.StatusCode }
    return @{ ok = $false; status = $status; body = $null }
  }
}

# 1. Login
$login = Post '/auth/login' @{ email = $Email; password = $Password } $null
if (-not $login.ok) { Bad "login (HTTP $($login.status))"; exit 1 }
$token = $login.body.accessToken
if (-not $token) { $token = $login.body.access_token }
if (-not $token) { Bad 'login sin token'; exit 1 }
Ok 'login del administrador'

# 2. Ticket
$t = Post '/ecf/certification-portal/tickets' @{} $token
if (-not $t.ok) {
  if ($t.status -eq 403) { Bad 'ticket rechazado (403): la empresa no está en el piloto o falta permiso' }
  else { Bad "ticket (HTTP $($t.status))" }
  exit 1
}
$ticket = $t.body.ticket
Ok ("ticket emitido (longitud " + $ticket.Length + ", no se muestra)")

# 3. Canje
$s = Post '/ecf/certification-portal/sessions' @{ ticket = $ticket } $null
if (-not $s.ok) { Bad "canje del ticket (HTTP $($s.status))"; exit 1 }
$portalToken = $s.body.token
Ok 'ticket canjeado por sesión del portal'

# 4. Contexto e identidad
try {
  $c = Invoke-WebRequest -Uri "$ApiBase/ecf/certification-portal/context" `
    -Headers @{ 'x-fullpos-portal' = $portalToken } -UseBasicParsing -TimeoutSec 30
  $ctx = ($c.Content | ConvertFrom-Json).context
} catch {
  Bad "contexto (HTTP $([int]$_.Exception.Response.StatusCode))"
  exit 1
}

$companyId = "$($ctx.company.id)"
$nombre = "$($ctx.company.commercialName)"
$rnc = "$($ctx.company.taxId)"
$rncMasked = if ($rnc.Length -ge 3) { ('*' * ($rnc.Length - 3)) + $rnc.Substring($rnc.Length - 3) } else { '***' }

Write-Host ("     empresa: $nombre · RNC: $rncMasked · companyId: $companyId")
Write-Host ("     recorrido: " + $ctx.milestones.application + ' / ' + $ctx.milestones.tests + ' / ' + $ctx.milestones.certification)
Write-Host ("     e-CF habilitado: " + $ctx.ecfEnabled)
if ($ctx.postulation) { Write-Host ("     intento: " + $ctx.postulation.attemptNo + ' · ' + $ctx.postulation.status) }

if ($companyId -eq $ExpectedCompanyId) { Ok 'la identidad corresponde a FULLTECH SRL' }
else { Bad "identidad distinta de la esperada ($companyId)" }

if ($ctx.ecfEnabled -eq $false) { Ok 'e-CF sigue desactivado (preparar no habilita emisión)' }
else { Bad 'e-CF aparece habilitado: revisar' }

# 5. Cierre y rechazo posterior
try {
  Invoke-WebRequest -Uri "$ApiBase/ecf/certification-portal/sessions" -Method DELETE `
    -Headers @{ 'x-fullpos-portal' = $portalToken } -UseBasicParsing -TimeoutSec 20 | Out-Null
  Ok 'sesión del portal cerrada'
} catch { Bad 'no se pudo cerrar la sesión' }

try {
  Invoke-WebRequest -Uri "$ApiBase/ecf/certification-portal/context" `
    -Headers @{ 'x-fullpos-portal' = $portalToken } -UseBasicParsing -TimeoutSec 20 | Out-Null
  Bad 'la sesión revocada sigue aceptándose'
} catch {
  if ([int]$_.Exception.Response.StatusCode -eq 401) { Ok 'la sesión revocada ya no sirve (401)' }
  else { Bad 'respuesta inesperada al reutilizar la sesión revocada' }
}

Write-Host ''
Write-Host 'Siguiente paso (en el navegador, con la cuenta de FULLTECH):'
Write-Host '  1. Entra en FullPOS Cloud.'
Write-Host '  2. Configuración → Facturación electrónica → Seguimiento.'
Write-Host '  3. Pulsa «Iniciar o continuar certificación».'
Write-Host '  4. En el portal, pulsa «Iniciar o continuar certificación» para montar el asistente.'
Write-Host '     Debe aparecer el asistente DOSA y en la consola el evento cert:ready.'
Write-Host ''
$failed = @($results | Where-Object { $_ -like 'FALLO*' })
if ($failed.Count -eq 0) { Write-Host 'RESULTADO: OK' -ForegroundColor Green; exit 0 }
Write-Host ("RESULTADO: " + $failed.Count + " comprobaciones fallidas") -ForegroundColor Red
exit 1
