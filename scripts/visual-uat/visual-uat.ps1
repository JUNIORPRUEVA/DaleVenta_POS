param(
  [Parameter(Mandatory = $true)]
  [ValidateSet('env', 'start-api', 'seed', 'status')]
  [string]$Action
)

# Perfil UAT VISUAL (interruptor e-CF en Windows).
#
# Objetivo: poder abrir FullPOS Cloud Windows contra un backend UAT local
# confirmado, sin tocar jamás:
#   - producción,
#   - la UAT histórica (`fullpos_alanube_uat_postgres`, 56550), que es inmutable,
#   - la base de pruebas automáticas en su estado de referencia.
#
# El backend se levanta contra la base **desechable** (56551,
# `fullpos_alanube_uat_test`) porque está declarada como tal por
# `scripts/ecf-test-db/_test-common.ps1` y ya tiene migraciones aplicadas.
# El perfil del entorno efímero NO puede arrancar la API (su UAT_EXPECTED_DB_NAME
# no coincide), así que aquí se deriva un perfil propio con el nombre y el puerto
# reales, más un puerto de API distinto (4004).

$ErrorActionPreference = 'Stop'

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$ApiRoot = Join-Path $RepoRoot 'apps\api'
$TestEnvFile = Join-Path $ApiRoot '.env.alanube.test.uat.local'
$VisualEnvFile = Join-Path $ApiRoot '.env.ecf.visual.uat.local'

$ExpectedDbName = 'fullpos_alanube_uat_test'
$ExpectedDbPort = '56551'
$ApiPort = '4004'
$HistoricalPort = '56550'
$HistoricalDbName = 'fullpos_alanube_uat'

function New-VisualSecret([int]$Bytes = 18) {
  $buffer = New-Object byte[] $Bytes
  $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
  try { $rng.GetBytes($buffer) } finally { $rng.Dispose() }
  [Convert]::ToBase64String($buffer).Replace('+', 'A').Replace('/', 'B').TrimEnd('=')
}

function Ensure-VisualEnvFile {
  if (Test-Path -LiteralPath $VisualEnvFile) { return }
  if (-not (Test-Path -LiteralPath $TestEnvFile)) {
    throw 'Falta el entorno efímero de pruebas (.env.alanube.test.uat.local).'
  }

  $skip = '^(PORT|UAT_EXPECTED_DB_NAME|UAT_EXPECTED_DB_PORT|ECF_EMISSION_ENABLED|ALANUBE_ENABLE_REAL_CALLS)='
  $kept = Get-Content -LiteralPath $TestEnvFile | Where-Object {
    $_ -match '^[A-Z_0-9]+=' -and $_ -notmatch $skip
  }
  $extra = @(
    "PORT=$ApiPort",
    "UAT_EXPECTED_DB_NAME=$ExpectedDbName",
    "UAT_EXPECTED_DB_PORT=$ExpectedDbPort",
    'ECF_EMISSION_ENABLED=false',
    'ALANUBE_ENABLE_REAL_CALLS=false',
    'ECF_ALANUBE_AUTH_TESTS_ENABLED=false',
    'ALANUBE_HTTP_TRANSPORT_ENABLED=false',
    'ECF_VISUAL_UAT_PROFILE=true',
    'VISUAL_UAT_ADMIN_EMAIL=ecf.visual.admin@fullpos.local',
    "VISUAL_UAT_ADMIN_PASSWORD=$(New-VisualSecret)",
    'VISUAL_UAT_COMPANY_NAME=ECF Visual UAT Demo'
  )
  Set-Content -LiteralPath $VisualEnvFile -Value ($kept + $extra) -Encoding UTF8
  Write-Host 'Creado el fichero de entorno visual UAT (ignorado por git).'
}

function Import-VisualEnv {
  Ensure-VisualEnvFile
  Get-Content -LiteralPath $VisualEnvFile | ForEach-Object {
    $line = $_.Trim()
    if ($line.Length -eq 0 -or $line.StartsWith('#')) { return }
    $idx = $line.IndexOf('=')
    if ($idx -le 0) { return }
    $name = $line.Substring(0, $idx).Trim()
    $value = $line.Substring($idx + 1).Trim().Trim('"')
    [Environment]::SetEnvironmentVariable($name, $value, 'Process')
  }
}

function Assert-VisualUatEnvironment {
  Import-VisualEnv

  if ($env:APP_ENV -ne 'uat') { throw 'APP_ENV debe ser uat.' }
  if ($env:UAT_LOCAL_ONLY -ne 'true') { throw 'UAT_LOCAL_ONLY debe ser true.' }
  if ($env:PORT -ne $ApiPort) { throw "PORT debe ser $ApiPort." }
  if ($env:UAT_EXPECTED_DB_NAME -ne $ExpectedDbName) { throw "UAT_EXPECTED_DB_NAME debe ser $ExpectedDbName." }
  if ($env:UAT_EXPECTED_DB_PORT -ne $ExpectedDbPort) { throw "UAT_EXPECTED_DB_PORT debe ser $ExpectedDbPort." }
  if ($env:DATABASE_URL -notmatch "@127\.0\.0\.1:$ExpectedDbPort/$ExpectedDbName($|\?)") {
    throw "DATABASE_URL debe apuntar a la base desechable en 127.0.0.1:$ExpectedDbPort."
  }

  # La UAT histórica es de SOLO LECTURA para este perfil.
  if ($env:DATABASE_URL -match ":$HistoricalPort/" -or $env:DATABASE_URL -match "/$HistoricalDbName($|\?)") {
    throw 'Rechazado: este perfil nunca opera sobre la UAT histórica.'
  }
  if ($env:DATABASE_URL -match 'easypanel|gcdndd|31\.97\.99\.70|hostinger|phytoemagry') {
    throw 'Rechazado: DATABASE_URL parece remota o de producción.'
  }

  if ($env:ALANUBE_ENABLE_REAL_CALLS -ne 'false') { throw 'Las llamadas reales a Alanube no están autorizadas.' }
  if ($env:ECF_EMISSION_ENABLED -ne 'false') { throw 'La emisión fiscal debe permanecer desactivada.' }
}

function Show-Status {
  Assert-VisualUatEnvironment
  $db = docker ps --filter "name=fullpos_alanube_ecf_test_postgres" --format '{{.Names}} {{.Status}} {{.Ports}}'
  Write-Host "Perfil visual UAT:"
  Write-Host "  API port   : $ApiPort"
  Write-Host "  Database   : $ExpectedDbName @ 127.0.0.1:$ExpectedDbPort (desechable)"
  Write-Host "  Histórica  : intocada (puerto $HistoricalPort, solo lectura)"
  Write-Host "  Alanube    : real calls = $env:ALANUBE_ENABLE_REAL_CALLS, emisión = $env:ECF_EMISSION_ENABLED"
  if ($db) { Write-Host "  Contenedor : $db" }
  $listening = [bool](Get-NetTCPConnection -LocalPort ([int]$ApiPort) -State Listen -ErrorAction SilentlyContinue)
  Write-Host "  API activa : $listening"
}

function Start-VisualApi {
  Assert-VisualUatEnvironment
  if (Get-NetTCPConnection -LocalPort ([int]$ApiPort) -State Listen -ErrorAction SilentlyContinue) {
    throw "El puerto $ApiPort ya está en uso."
  }
  $env:APPYRA_USAGE_TELEMETRY_ENABLED = 'false'
  Remove-Item Env:ALANUBE_SANDBOX_TOKEN -ErrorAction SilentlyContinue
  Write-Host "Arrancando API UAT visual en http://127.0.0.1:$ApiPort (base desechable $ExpectedDbName)"
  Push-Location $ApiRoot
  try { npm run start:dev } finally { Pop-Location }
}

function Invoke-Seed {
  Assert-VisualUatEnvironment
  $base = "http://127.0.0.1:$ApiPort"
  $email = $env:VISUAL_UAT_ADMIN_EMAIL
  $password = $env:VISUAL_UAT_ADMIN_PASSWORD
  if (-not $email -or -not $password) { throw 'Faltan las credenciales sintéticas del entorno visual.' }

  $body = @{
    email           = $email
    password        = $password
    confirmPassword = $password
    firstName       = 'ECF'
    lastName        = 'Visual UAT'
    phone           = '0000000000'
    commercialName  = $env:VISUAL_UAT_COMPANY_NAME
  } | ConvertTo-Json

  $created = $false
  try {
    Invoke-RestMethod -Method Post -Uri "$base/auth/register-business" -ContentType 'application/json' -Body $body | Out-Null
    $created = $true
    Write-Host 'Empresa sintética creada (registro real de la API).'
  } catch {
    $code = $_.Exception.Response.StatusCode.value__
    if ($code -eq 409) {
      Write-Host 'La empresa sintética ya existía: el seed es idempotente.'
    } else {
      throw "No se pudo registrar la empresa sintética (HTTP $code)."
    }
  }

  $login = Invoke-RestMethod -Method Post -Uri "$base/auth/login" -ContentType 'application/json' `
    -Body (@{ email = $email; password = $password } | ConvertTo-Json)
  $token = $login.accessToken
  if (-not $token) { throw 'El login no devolvió accessToken.' }

  $headers = @{ Authorization = "Bearer $token" }
  $settings = Invoke-RestMethod -Method Get -Uri "$base/settings" -Headers $headers
  $capabilities = Invoke-RestMethod -Method Get -Uri "$base/ecf/capabilities" -Headers $headers

  Write-Host "--- Estado sintético (empresa: $($env:VISUAL_UAT_COMPANY_NAME)) ---"
  Write-Host "  login                 : OK (usuario sintético)"
  Write-Host "  settings.ecfEnabled   : $($settings.ecfEnabled)"
  Write-Host "  settings.companyName  : $($settings.companyName)"
  Write-Host "  ecf.capabilities.enabled         : $($capabilities.enabled)"
  Write-Host "  ecf.capabilities.emissionPathAvailable : $($capabilities.emissionPathAvailable)"
  Write-Host "  empresa nueva en este seed       : $created"
  Write-Host '  (las credenciales quedan solo en el fichero de entorno local ignorado)'
}

switch ($Action) {
  'env' { Assert-VisualUatEnvironment; Write-Host 'Entorno visual UAT listo.' }
  'start-api' { Start-VisualApi }
  'seed' { Invoke-Seed }
  'status' { Show-Status }
}
