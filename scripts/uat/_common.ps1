$ErrorActionPreference = "Stop"

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$ApiRoot = Join-Path $RepoRoot "apps\api"
$UatEnvFile = Join-Path $ApiRoot ".env.uat.local"
$UatEnvExample = Join-Path $ApiRoot ".env.uat.local.example"
$ComposeFile = Join-Path $RepoRoot "scripts\uat\docker-compose.uat.yml"

function New-UatSecret([int]$Bytes = 24) {
  $buffer = New-Object byte[] $Bytes
  $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
  try {
    $rng.GetBytes($buffer)
  } finally {
    $rng.Dispose()
  }
  [Convert]::ToBase64String($buffer).Replace("+", "A").Replace("/", "B").TrimEnd("=")
}

function Ensure-UatEnvFile {
  if (Test-Path -LiteralPath $UatEnvFile) {
    return
  }

  $dbPassword = New-UatSecret
  $jwtSecret = New-UatSecret 32
  $adminPassword = New-UatSecret 18
  $content = @"
APP_ENV=uat
UAT_LOCAL_ONLY=true
PORT=4000
PRODUCTS_SOURCE=LOCAL
RUN_SEED=false
RUN_MIGRATIONS=false
PRISMA_SYNC_MODE=migrate
REDIS_ENABLED=false
STORAGE_MODE=none
UPLOAD_DIR=./uploads-uat
JWT_SECRET=$jwtSecret
JWT_EXPIRES_IN=15m

UAT_DB_NAME=daleventa_uat_local
UAT_DB_USER=daleventa_uat_user
UAT_DB_PASSWORD=$dbPassword
UAT_DB_PORT=55432
DATABASE_URL=postgresql://daleventa_uat_user:$dbPassword@127.0.0.1:55432/daleventa_uat_local

UAT_ADMIN_EMAIL=uat.admin@daleventa.local
UAT_ADMIN_PASSWORD=$adminPassword
"@
  Set-Content -LiteralPath $UatEnvFile -Value $content -Encoding UTF8
  Write-Host "Created local ignored UAT env file: apps/api/.env.uat.local"
  Write-Host "UAT admin email: uat.admin@daleventa.local"
  Write-Host "UAT admin password is stored only in apps/api/.env.uat.local; do not commit it."
}

function Import-UatEnv {
  Ensure-UatEnvFile
  Get-Content -LiteralPath $UatEnvFile | ForEach-Object {
    $line = $_.Trim()
    if ($line.Length -eq 0 -or $line.StartsWith("#")) { return }
    $idx = $line.IndexOf("=")
    if ($idx -le 0) { return }
    $name = $line.Substring(0, $idx).Trim()
    $value = $line.Substring($idx + 1).Trim().Trim('"')
    [Environment]::SetEnvironmentVariable($name, $value, "Process")
  }
}

function Assert-UatEnvironment {
  Import-UatEnv
  if ($env:APP_ENV -ne "uat") {
    throw "Refusing UAT command: APP_ENV must be uat."
  }
  if ($env:UAT_LOCAL_ONLY -ne "true") {
    throw "Refusing UAT command: UAT_LOCAL_ONLY must be true."
  }
  if ($env:UAT_DB_NAME -ne "daleventa_uat_local") {
    throw "Refusing UAT command: UAT_DB_NAME must be daleventa_uat_local."
  }
  if ($env:DATABASE_URL -notmatch "/daleventa_uat_local($|\?)") {
    throw "Refusing UAT command: DATABASE_URL must target daleventa_uat_local."
  }
  if ($env:DATABASE_URL -match "easypanel|gcdndd|31\.97\.99\.70|hostinger|/daleventa($|\?)|/daleventa_pos($|\?)") {
    throw "Refusing UAT command: DATABASE_URL looks remote or protected."
  }
  if ($env:DATABASE_URL -notmatch "@(127\.0\.0\.1|localhost|\[::1\]):") {
    throw "Refusing UAT command: DATABASE_URL host must be localhost/127.0.0.1/::1."
  }
}

function Assert-DockerAvailable {
  $docker = Get-Command docker -ErrorAction SilentlyContinue
  if (-not $docker) {
    throw "Docker is not installed or not on PATH. Install/start Docker Desktop before running local UAT."
  }
}

function Write-UatBanner {
  Write-Host "ENVIRONMENT: UAT LOCAL"
  Write-Host "DATABASE: $env:UAT_DB_NAME"
  Write-Host "DATABASE_HOST: 127.0.0.1"
  Write-Host "DATABASE_PORT: $env:UAT_DB_PORT"
  Write-Host "API: http://127.0.0.1:$env:PORT"
  Write-Host "PRODUCT SOURCE: $env:PRODUCTS_SOURCE"
  Write-Host "PRODUCTION: NOT CONNECTED"
}
