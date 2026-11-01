#requires -Version 5.1
<#
  Preflight de fuente para desplegar el backend de FullPOS Cloud desde EasyPanel.

  Uso:
    powershell -NoProfile -ExecutionPolicy Bypass -File scripts\deploy\preflight_backend_source.ps1 `
      -SourcePath 'C:\ruta\al\code' [-ExpectedCommit 3842b84e5864ae578a0c09fccfe44c43b087284b]

  Devuelve:
    READY FOR MANUAL DEPLOY: YES | NO   (y exit code 0 / 1)

  Diseño fail-closed: si falta cualquier evidencia obligatoria, el resultado es NO.
  Solo lectura: no modifica ni compila nada.
#>
param(
  [Parameter(Mandatory = $true)][string]$SourcePath,
  [string]$ExpectedVersion = '1.0.7+151',
  [string]$ExpectedCommit = '3842b84e5864ae578a0c09fccfe44c43b087284b',
  [string]$ExpectedBranch = 'production-main',
  [int]$ExpectedMigrations = 43
)

$ErrorActionPreference = 'Stop'
$failures = New-Object System.Collections.Generic.List[string]
$passes = New-Object System.Collections.Generic.List[string]

function Check {
  param([bool]$Condition, [string]$OkMessage, [string]$FailMessage)
  if ($Condition) { $passes.Add($OkMessage) } else { $failures.Add($FailMessage) }
}

if (-not (Test-Path -LiteralPath $SourcePath)) {
  Write-Host "READY FOR MANUAL DEPLOY: NO"
  Write-Host "  - La ruta indicada no existe: $SourcePath"
  exit 1
}
$root = (Resolve-Path -LiteralPath $SourcePath).Path

# 1) Version declarada
$pubspec = Join-Path $root 'apps\fulltech_app\pubspec.yaml'
$version = $null
if (Test-Path -LiteralPath $pubspec) {
  $line = Get-Content -LiteralPath $pubspec | Where-Object { $_ -match '^\s*version:\s*(\S+)\s*$' } | Select-Object -First 1
  if ($line -match '^\s*version:\s*(\S+)\s*$') { $version = $Matches[1] }
}
Check ($version -eq $ExpectedVersion) "Version $ExpectedVersion" "Version esperada $ExpectedVersion, encontrada '$version'"

# 2) Funciones obligatorias
$required = @(
  'apps\api\src\sales\sale-reconciliation-obligation.service.ts',
  'apps\api\src\sales\sales.controller.ts',
  'apps\api\src\guardian\guardian.auto-enrollment.service.ts',
  'apps\api\src\guardian\guardian.ai.balance.monitor.ts',
  'apps\api\src\guardian\guardian.diagnosis.service.ts',
  'apps\api\src\guardian\guardian.alert.channels.ts',
  'apps\api\src\guardian\guardian.config.ts',
  'apps\api\src\app-updates\app-update-releases.controller.ts',
  'apps\api\Dockerfile',
  'apps\api\prisma\schema.prisma'
)
foreach ($rel in $required) {
  Check (Test-Path -LiteralPath (Join-Path $root $rel)) "Existe $rel" "FALTA $rel"
}

# 3) Rutas de recuperacion V2 en el controlador
$salesCtl = Join-Path $root 'apps\api\src\sales\sales.controller.ts'
if (Test-Path -LiteralPath $salesCtl) {
  $text = Get-Content -LiteralPath $salesCtl -Raw
  Check ($text -match 'reconciliation-obligations') "Rutas de obligaciones presentes" "No hay rutas 'reconciliation-obligations' en sales.controller.ts"
  Check ($text -match 'attempts/:clientRequestId/declaration') 'Ruta de declaracion presente' "No hay ruta de declaracion en sales.controller.ts"
}

# 4) Migraciones del repositorio (el repo lleva 43 carpetas; la base tiene 183 filas aplicadas)
$migDir = Join-Path $root 'apps\api\prisma\migrations'
if (Test-Path -LiteralPath $migDir) {
  $migCount = (Get-ChildItem -LiteralPath $migDir -Directory | Measure-Object).Count
  Check ($migCount -eq $ExpectedMigrations) "$migCount carpetas de migracion (repo)" "Se esperaban $ExpectedMigrations carpetas de migracion, hay $migCount"
  foreach ($m in @('20261029190000_sale_reconciliation_obligations', '20261029210000_reconciliation_single_active_obligation')) {
    Check (Test-Path -LiteralPath (Join-Path $migDir $m)) "Migracion $m presente" "FALTA la migracion $m"
  }
} else {
  $failures.Add("FALTA el directorio de migraciones")
}

# 5) Esquema: opt-in por empresa
$schema = Join-Path $root 'apps\api\prisma\schema.prisma'
if (Test-Path -LiteralPath $schema) {
  $schemaText = Get-Content -LiteralPath $schema -Raw
  Check ($schemaText -match 'guardianEnabled') 'Schema con guardianEnabled' 'El schema no declara guardianEnabled'
  Check ($schemaText -match 'model SaleReconciliationObligation') 'Schema con SaleReconciliationObligation' 'El schema no declara SaleReconciliationObligation'
}

# 6) Identidad Git (fail-closed si no hay .git ni fichero de commit)
$gitDir = Join-Path $root '.git'
$commitFile = Join-Path $root 'SOURCE_COMMIT'
$branch = $null; $commit = $null
if (Test-Path -LiteralPath $gitDir) {
  $branch = (& git -C $root rev-parse --abbrev-ref HEAD 2>$null).Trim()
  $commit = (& git -C $root rev-parse HEAD 2>$null).Trim()
} elseif (Test-Path -LiteralPath $commitFile) {
  $commit = (Get-Content -LiteralPath $commitFile -TotalCount 1).Trim()
  $branch = $ExpectedBranch
}
Check (($branch -eq $ExpectedBranch) -or ($commit -eq $ExpectedCommit)) "Rama $ExpectedBranch (o commit aprobado)" "Rama '$branch' distinta de $ExpectedBranch y commit no aprobado"

# 7) El motor V2 debe existir de verdad (descarta snapshots antiguos tipo 147)
$v2Service = Join-Path $root 'apps\api\src\sales\sale-reconciliation-obligation.service.ts'
Check (Test-Path -LiteralPath $v2Service) 'Motor V2 presente (no es un snapshot 147)' 'Parece un snapshot antiguo: no existe sale-reconciliation-obligation.service.ts'

Write-Host ''
Write-Host '--- Comprobaciones OK ---'
$passes | ForEach-Object { Write-Host "  [OK] $_" }
if ($failures.Count -gt 0) {
  Write-Host '--- Fallos ---'
  $failures | ForEach-Object { Write-Host "  [NO] $_" }
}
Write-Host ''
Write-Host ("Version:  {0}" -f $version)
Write-Host ("Rama:     {0}" -f $branch)
Write-Host ("Commit:   {0}" -f $commit)
Write-Host ("Ruta:     {0}" -f $root)
Write-Host ''
if ($failures.Count -eq 0) {
  Write-Host 'READY FOR MANUAL DEPLOY: YES'
  exit 0
}
Write-Host 'READY FOR MANUAL DEPLOY: NO'
exit 1
