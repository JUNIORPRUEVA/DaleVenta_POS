<#
.SYNOPSIS
  Audita el aislamiento de red de los artefactos UAT ATRIBUYENDO cada conexión
  al proceso que la posee.

.DESCRIPTION
  El problema que resuelve: una comprobación global («¿hay conexiones al host de
  producción?») confunde la instalación comercial de DaleVentas POS con el
  ejecutable UAT. Este script no juzga direcciones en abstracto: resuelve cada
  conexión establecida a su PID, la ruta del ejecutable y la clasifica.

  Reglas:
    - Solo una conexión propiedad de un artefacto UAT hacia algo que no sea
      127.0.0.1/localhost es FAIL.
    - Una conexión de la instalación COMERCIAL u de OTRO proceso se informa como
      referencia y NUNCA bloquea: no se debe cerrar ni modificar esa instalación.
    - Si no hay ningún proceso UAT en ejecución, el script devuelve NOT_APPLICABLE:
      no se puede demostrar aislamiento de algo que no está corriendo.

  Es de SOLO LECTURA: consulta sockets y procesos. No abre, no cierra y no
  modifica ninguna aplicación.

.PARAMETER UatPathFragment
  Fragmento de ruta que identifica un artefacto UAT. Por defecto contempla el
  directorio de distribución y el árbol de compilación corto.

.PARAMETER ProductionHost
  Dirección del host productivo, solo para etiquetar la conexión en el informe.

.PARAMETER OutFile
  Ruta donde guardar el resumen en texto. Opcional.

.EXAMPLE
  pwsh scripts/visual-uat/uat-connection-audit.ps1
#>
[CmdletBinding()]
param(
  [string[]]$UatPathFragment = @('ecf-uat-dist', 'C:\b\ecf\'),
  [string]$ProductionHost = '31.97.99.70',
  [string]$CommercialPathFragment = 'DaleVentas POS',
  [string]$OutFile
)

$ErrorActionPreference = 'Stop'

function Get-OwningProcessInfo {
  param([int]$ProcessId)

  $info = [ordered]@{
    ProcessId = $ProcessId
    ProcessName = $null
    Path = $null
    PathAccessible = $false
  }
  if ($ProcessId -le 0) { return [pscustomobject]$info }
  try {
    $proc = Get-Process -Id $ProcessId -ErrorAction Stop
    $info.ProcessName = $proc.ProcessName
    try {
      $path = $proc.Path
      if ($path) {
        $info.Path = $path
        $info.PathAccessible = $true
      }
    } catch {
      # Acceso denegado a procesos de otro usuario o elevados: se informa sin ruta.
    }
  } catch {
    $info.ProcessName = '(no encontrado)'
  }
  return [pscustomobject]$info
}

function Get-Classification {
  param([string]$Path, [string]$ProcessName)

  if (-not $Path) {
    # Sin ruta no se puede atribuir: se trata como desconocido, nunca como UAT.
    return 'DESCONOCIDO'
  }
  foreach ($fragment in $UatPathFragment) {
    if ($Path -like "*$fragment*") { return 'UAT' }
  }
  if ($Path -like "*$CommercialPathFragment*") { return 'COMERCIAL' }
  return 'OTRO'
}

function Test-Loopback {
  param([string]$Address)
  return ($Address -eq '127.0.0.1' -or $Address -eq '::1' -or $Address -eq 'localhost' -or $Address -eq '0.0.0.0' -or $Address -eq '::')
}

$lines = New-Object System.Collections.Generic.List[string]
function Write-Line {
  param([string]$Text)
  $lines.Add($Text)
  Write-Output $Text
}

Write-Line '=== AUDITORÍA DE AISLAMIENTO UAT (por proceso/path/PID) ==='
Write-Line ("Fecha: " + (Get-Date).ToString('yyyy-MM-dd HH:mm:ss'))
Write-Line ''

# --- 1. Conexiones establecidas, atribuidas a su proceso ---
$rows = @()
try {
  $connections = Get-NetTCPConnection -State Established -ErrorAction Stop
} catch {
  Write-Line ('ERROR al enumerar conexiones: ' + $_.Exception.Message)
  exit 1
}

foreach ($conn in $connections) {
  $owner = Get-OwningProcessInfo -ProcessId $conn.OwningProcess
  $class = Get-Classification -Path $owner.Path -ProcessName $owner.ProcessName
  $remote = $conn.RemoteAddress
  $rows += [pscustomobject]@{
    PID          = $owner.ProcessId
    Proceso      = $owner.ProcessName
    Clase        = $class
    Local        = "$($conn.LocalAddress):$($conn.LocalPort)"
    Remoto       = "$remote`:$($conn.RemotePort)"
    RemotoLocal  = (Test-Loopback -Address $remote)
    Produce      = ($remote -eq $ProductionHost)
    Ruta         = $owner.Path
  }
}

# --- 2. Procesos UAT y COMERCIALES detectados ---
$uatRows = @($rows | Where-Object { $_.Clase -eq 'UAT' })
$commercialRows = @($rows | Where-Object { $_.Clase -eq 'COMERCIAL' })
$unknownRows = @($rows | Where-Object { $_.Clase -eq 'DESCONOCIDO' })

# Procesos UAT vivos aunque no tengan conexiones establecidas.
$uatProcesses = @()
foreach ($fragment in $UatPathFragment) {
  try {
    $uatProcesses += Get-Process -ErrorAction SilentlyContinue | Where-Object {
      try { $_.Path -and $_.Path -like "*$fragment*" } catch { $false }
    }
  } catch {
    # Sin permiso para leer rutas: se omite este fragmento.
  }
}
$uatProcesses = @($uatProcesses | Sort-Object Id -Unique)

Write-Line '--- Procesos UAT detectados ---'
if ($uatProcesses.Count -eq 0) {
  Write-Line 'ninguno en ejecución'
} else {
  foreach ($proc in $uatProcesses) {
    $path = $null
    try { $path = $proc.Path } catch { }
    Write-Line ("PID " + $proc.Id + "  " + $proc.ProcessName + "  " + $path)
  }
}

Write-Line ''
Write-Line '--- Conexiones establecidas por clase ---'
foreach ($class in @('UAT', 'COMERCIAL', 'OTRO', 'DESCONOCIDO')) {
  $group = @($rows | Where-Object { $_.Clase -eq $class })
  if ($group.Count -eq 0) { continue }
  Write-Line ("[$class] " + $group.Count + " conexión(es)")
  foreach ($row in $group) {
    $flag = ''
    if ($row.Produce) { $flag += ' <-- HOST PRODUCTIVO' }
    if (-not $row.RemotoLocal) { $flag += ' <-- NO loopback' }
    Write-Line ("  PID " + $row.PID + " " + $row.Proceso + "  " + $row.Local + " -> " + $row.Remoto + $flag)
    if ($row.Ruta) { Write-Line ("        " + $row.Ruta) }
  }
}

# --- 3. Servicios locales esperados (listeners) ---
Write-Line ''
Write-Line '--- Listeners locales esperados ---'
foreach ($port in @(4004, 56551)) {
  $listener = Get-NetTCPConnection -State Listen -LocalPort $port -ErrorAction SilentlyContinue |
    Select-Object -First 1
  if ($listener) {
    $owner = Get-OwningProcessInfo -ProcessId $listener.OwningProcess
    Write-Line ("puerto " + $port + " ESCUCHANDO en " + $listener.LocalAddress + "  PID " + $owner.ProcessId + "  " + $owner.ProcessName)
  } else {
    Write-Line ("puerto " + $port + " sin listener")
  }
}

# --- 4. Veredicto ---
Write-Line ''
$uatToExternal = @($uatRows | Where-Object { -not $_.RemotoLocal })
$uatToProduction = @($uatRows | Where-Object { $_.Produce })
$verdict = 'PASS'
$exitCode = 0
$reason = ''

if ($uatToProduction.Count -gt 0) {
  $verdict = 'FAIL'
  $exitCode = 1
  $reason = 'un proceso UAT tiene conexión al host productivo'
} elseif ($uatToExternal.Count -gt 0) {
  $verdict = 'FAIL'
  $exitCode = 1
  $reason = 'un proceso UAT tiene conexiones fuera de loopback'
} elseif ($uatProcesses.Count -eq 0) {
  $verdict = 'NOT_APPLICABLE'
  $exitCode = 2
  $reason = 'no hay ningún proceso UAT en ejecución: no hay nada que aislar todavía'
} else {
  $reason = 'los procesos UAT solo usan loopback (o no tienen conexiones)'
}

Write-Line ("--- Conexiones de la instalación COMERCIAL: " + $commercialRows.Count + " (informativas, NO bloquean) ---")
if ($commercialRows.Count -gt 0) {
  Write-Line 'La instalación comercial no se cierra ni se modifica: queda fuera del alcance de la UAT.'
}

Write-Line ''
Write-Line ("VEREDICTO: " + $verdict + " — " + $reason)

if ($OutFile) {
  $lines | Set-Content $OutFile -Encoding UTF8
}

exit $exitCode
