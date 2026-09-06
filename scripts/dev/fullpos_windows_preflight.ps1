$ErrorActionPreference = 'Stop'

$processes = Get-Process fullpos_cloud -ErrorAction SilentlyContinue

if ($processes) {
  $processes | Select-Object Id, Path, StartTime | Format-List
  Write-Error 'Close every running FullPOS window before launching from VS Code, then press F5 again. This preflight does not delete data or kill processes.'
  exit 1
}

Write-Host 'FullPOS Windows preflight OK: no running fullpos_cloud.exe process found.'
