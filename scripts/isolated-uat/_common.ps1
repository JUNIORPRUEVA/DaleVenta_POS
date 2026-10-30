$ErrorActionPreference = "Stop"

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$ApiRoot = Join-Path $RepoRoot "apps\api"
$EnvFile = Join-Path $ApiRoot ".env.alanube.uat.local"
$ComposeFile = Join-Path $PSScriptRoot "docker-compose.yml"

$FrontName = "ALANUBE"
$ComposeProject = "fullpos_alanube_uat"
$ContainerName = "fullpos_alanube_uat_postgres"
$DbName = "fullpos_alanube_uat"
$DbUser = "fullpos_alanube_uat_user"
$DbPort = "56550"
$ApiPort = "4002"

function New-IsolatedSecret([int]$Bytes = 24) {
  $buffer = New-Object byte[] $Bytes
  $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
  try {
    $rng.GetBytes($buffer)
  } finally {
    $rng.Dispose()
  }
  [Convert]::ToBase64String($buffer).Replace("+", "A").Replace("/", "B").TrimEnd("=")
}

function Ensure-IsolatedEnvFile {
  if (Test-Path -LiteralPath $EnvFile) {
    return
  }

  $dbPassword = New-IsolatedSecret
  $jwtSecret = New-IsolatedSecret 32
  $adminPassword = New-IsolatedSecret 18
  $content = @"
APP_ENV=uat
UAT_LOCAL_ONLY=true
UAT_EXPECTED_DB_NAME=$DbName
UAT_EXPECTED_DB_PORT=$DbPort
PORT=$ApiPort
PRODUCTS_SOURCE=LOCAL
RUN_SEED=false
RUN_MIGRATIONS=false
PRISMA_SYNC_MODE=migrate
REDIS_ENABLED=false
STORAGE_MODE=none
UPLOAD_DIR=./uploads-alanube-uat
JWT_SECRET=$jwtSecret
JWT_EXPIRES_IN=15m

UAT_DB_NAME=$DbName
UAT_DB_USER=$DbUser
UAT_DB_PASSWORD=$dbPassword
UAT_DB_PORT=$DbPort
UAT_CONTAINER_NAME=$ContainerName
DATABASE_URL=postgresql://$($DbUser):$dbPassword@127.0.0.1:$DbPort/$DbName

ALANUBE_ENV=sandbox
ALANUBE_BASE_URL=https://sandbox.alanube.co/dom/v1
ALANUBE_ENABLE_REAL_CALLS=false

UAT_ADMIN_EMAIL=alanube.admin@fullpos.local
UAT_ADMIN_PASSWORD=$adminPassword
"@
  Set-Content -LiteralPath $EnvFile -Value $content -Encoding UTF8
  Write-Host "Created ignored env file: $EnvFile"
}

function Import-IsolatedEnv {
  Ensure-IsolatedEnvFile
  Get-Content -LiteralPath $EnvFile | ForEach-Object {
    $line = $_.Trim()
    if ($line.Length -eq 0 -or $line.StartsWith("#")) { return }
    $idx = $line.IndexOf("=")
    if ($idx -le 0) { return }
    $name = $line.Substring(0, $idx).Trim()
    $value = $line.Substring($idx + 1).Trim().Trim('"')
    [Environment]::SetEnvironmentVariable($name, $value, "Process")
  }
}

function Assert-DockerAvailable {
  if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
    throw "Docker is not installed or not on PATH."
  }
}

function Assert-PortNotUsedByOtherContainer([string]$Port, [string]$ExpectedContainer) {
  $connections = Get-NetTCPConnection -LocalPort ([int]$Port) -ErrorAction SilentlyContinue
  if (-not $connections) { return }

  $dockerRows = docker ps --format "{{.Names}}|{{.Ports}}"
  $owned = $false
  foreach ($row in $dockerRows) {
    if ($row -match [regex]::Escape($ExpectedContainer) -and $row -match ":$Port->") {
      $owned = $true
    }
  }
  if (-not $owned) {
    throw "Port $Port is already in use by another process/container."
  }
}

function Assert-ApiPortAvailable {
  $connections = Get-NetTCPConnection -LocalPort ([int]$ApiPort) -ErrorAction SilentlyContinue
  if ($connections) {
    throw "API port $ApiPort is already in use."
  }
}

function Assert-IsolatedEnvironment {
  Import-IsolatedEnv
  if ($env:APP_ENV -ne "uat") { throw "APP_ENV must be uat." }
  if ($env:UAT_LOCAL_ONLY -ne "true") { throw "UAT_LOCAL_ONLY must be true." }
  if ($env:PORT -ne $ApiPort) { throw "PORT must be $ApiPort." }
  if ($env:UAT_DB_NAME -ne $DbName) { throw "UAT_DB_NAME must be $DbName." }
  if ($env:UAT_EXPECTED_DB_NAME -ne $DbName) { throw "UAT_EXPECTED_DB_NAME must be $DbName." }
  if ($env:UAT_DB_PORT -ne $DbPort) { throw "UAT_DB_PORT must be $DbPort." }
  if ($env:UAT_EXPECTED_DB_PORT -ne $DbPort) { throw "UAT_EXPECTED_DB_PORT must be $DbPort." }
  if ($env:UAT_CONTAINER_NAME -ne $ContainerName) { throw "UAT_CONTAINER_NAME must be $ContainerName." }
  if ($env:DATABASE_URL -notmatch "@(127\.0\.0\.1|localhost|\[::1\]):$DbPort/$DbName($|\?)") {
    throw "DATABASE_URL must target local $DbName on port $DbPort."
  }
  if ($env:DATABASE_URL -match "easypanel|gcdndd|31\.97\.99\.70|hostinger|/daleventa($|\?)|/daleventa_pos($|\?)|phytoemagry") {
    throw "DATABASE_URL looks remote, production-like, or protected."
  }
  if ($env:ALANUBE_ENV -ne "sandbox") { throw "ALANUBE_ENV must stay sandbox." }
  if ($env:ALANUBE_ENABLE_REAL_CALLS -ne "false") { throw "Alanube real calls are not authorized." }
  if ($env:ALANUBE_BASE_URL -match "api\.alanube|production|prod") {
    throw "Alanube base URL looks production-like."
  }
}

function Invoke-IsolatedCompose {
  param([Parameter(ValueFromRemainingArguments = $true)][string[]]$ComposeArgs)
  Assert-IsolatedEnvironment
  Assert-DockerAvailable
  & docker compose --project-name $ComposeProject -f $ComposeFile --env-file $EnvFile @ComposeArgs
}

function Write-IsolatedBanner {
  Write-Host "FRONT: $FrontName"
  Write-Host "REPO: $RepoRoot"
  Write-Host "API: http://127.0.0.1:$ApiPort"
  Write-Host "DATABASE: $DbName"
  Write-Host "DATABASE_HOST: 127.0.0.1"
  Write-Host "DATABASE_PORT: $DbPort"
  Write-Host "CONTAINER: $ContainerName"
  Write-Host "ALANUBE: SANDBOX CONFIGURED, REAL CALLS DISABLED"
  Write-Host "PRODUCTION: NOT CONNECTED"
}
