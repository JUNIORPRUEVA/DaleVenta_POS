$ErrorActionPreference = "Stop"

# Shared helpers for the EPHEMERAL automated-test PostgreSQL. This environment is
# disposable and completely separate from the historical UAT (fullpos_alanube_uat).
# Nothing here ever operates on the historical container, database or volume.

$RepoRoot    = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$ApiRoot     = Join-Path $RepoRoot "apps\api"
$EnvFile     = Join-Path $ApiRoot ".env.alanube.test.uat.local"
$ComposeFile = Join-Path $PSScriptRoot "docker-compose.test.yml"

$TestFrontName      = "ECF_TEST"
$TestComposeProject = "fullpos_alanube_ecf_test"
$TestContainerName  = "fullpos_alanube_ecf_test_postgres"
$TestVolumeName     = "fullpos_alanube_ecf_test_postgres_data"
$TestDbName         = "fullpos_alanube_uat_test"
$TestDbUser         = "fullpos_alanube_uat_test_user"
$TestDbPort         = "56551"
$TestMarker         = "ECF_EPHEMERAL_TEST_DB"
$TestApiPort        = "4003"

# Historical UAT: must NEVER be touched by automated tests.
$HistoricalContainer = "fullpos_alanube_uat_postgres"
$HistoricalDbName    = "fullpos_alanube_uat"
$HistoricalPort      = "56550"

function New-TestSecret([int]$Bytes = 24) {
  $buffer = New-Object byte[] $Bytes
  $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
  try { $rng.GetBytes($buffer) } finally { $rng.Dispose() }
  [Convert]::ToBase64String($buffer).Replace("+", "A").Replace("/", "B").TrimEnd("=")
}

function Ensure-TestEnvFile {
  if (Test-Path -LiteralPath $EnvFile) { return }
  $dbPassword = New-TestSecret
  $jwtSecret = New-TestSecret 32
  $content = @"
APP_ENV=uat
UAT_LOCAL_ONLY=true
ECF_TEST_DB_MARKER=$TestMarker
PORT=$TestApiPort
PRODUCTS_SOURCE=LOCAL
RUN_SEED=false
RUN_MIGRATIONS=false
PRISMA_SYNC_MODE=migrate
REDIS_ENABLED=false
STORAGE_MODE=none
UPLOAD_DIR=./uploads-ecf-test
JWT_SECRET=$jwtSecret
JWT_EXPIRES_IN=15m
ECF_EMISSION_ENABLED=false

TEST_DB_NAME=$TestDbName
TEST_DB_USER=$TestDbUser
TEST_DB_PASSWORD=$dbPassword
TEST_DB_PORT=$TestDbPort
TEST_CONTAINER_NAME=$TestContainerName
DATABASE_URL=postgresql://$($TestDbUser):$dbPassword@127.0.0.1:$TestDbPort/$TestDbName

ALANUBE_ENV=sandbox
ALANUBE_BASE_URL=https://sandbox.alanube.co/dom/v1
ALANUBE_ENABLE_REAL_CALLS=false
"@
  Set-Content -LiteralPath $EnvFile -Value $content -Encoding UTF8
  Write-Host "Created ignored ephemeral test env file: $EnvFile"
}

function Import-TestEnv {
  Ensure-TestEnvFile
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

function Assert-TestDockerAvailable {
  if (-not (Get-Command docker -ErrorAction SilentlyContinue)) { throw "Docker is not installed or not on PATH." }
}

function Assert-TestEnvironment {
  Import-TestEnv
  if ($env:TEST_DB_NAME -ne $TestDbName) { throw "TEST_DB_NAME must be $TestDbName." }
  if ($env:TEST_DB_PORT -ne $TestDbPort) { throw "TEST_DB_PORT must be $TestDbPort." }
  if ($env:TEST_CONTAINER_NAME -ne $TestContainerName) { throw "TEST_CONTAINER_NAME must be $TestContainerName." }
  if ($env:ECF_TEST_DB_MARKER -ne $TestMarker) { throw "ECF_TEST_DB_MARKER must be $TestMarker." }
  if ($env:APP_ENV -ne "uat") { throw "APP_ENV must be uat (local isolated semantic)." }
  if ($env:UAT_LOCAL_ONLY -ne "true") { throw "UAT_LOCAL_ONLY must be true." }
  if ($env:DATABASE_URL -notmatch "@127\.0\.0\.1:$TestDbPort/$TestDbName($|\?)") {
    throw "DATABASE_URL must target the ephemeral test database on 127.0.0.1:$TestDbPort."
  }
  # Absolute refusal to run automated tests against the historical UAT.
  if ($env:DATABASE_URL -match "/$HistoricalDbName($|\?)" -or $env:DATABASE_URL -match ":$HistoricalPort/") {
    throw "Refusing: automated tests must never target the historical UAT database."
  }
  if ($env:DATABASE_URL -match "easypanel|gcdndd|31\.97\.99\.70|hostinger|phytoemagry") {
    throw "DATABASE_URL looks remote or production-like."
  }
  if ($env:ALANUBE_ENV -ne "sandbox") { throw "ALANUBE_ENV must stay sandbox." }
  if ($env:ALANUBE_ENABLE_REAL_CALLS -ne "false") { throw "Alanube real calls are not authorized." }
}

function Assert-EphemeralContainer([string]$Name) {
  if ($Name -ne $TestContainerName) { throw "Refusing to operate on '$Name': not the ephemeral test container." }
}

function Invoke-TestCompose {
  param([Parameter(ValueFromRemainingArguments = $true)][string[]]$ComposeArgs)
  Assert-TestEnvironment
  Assert-TestDockerAvailable
  & docker compose --project-name $TestComposeProject -f $ComposeFile --env-file $EnvFile @ComposeArgs
}

function Get-HistoricalSyntheticCounts {
  # Read-only probe of the historical UAT. Used to prove automated tests add nothing there.
  $out = & docker exec $HistoricalContainer psql -U fullpos_alanube_uat_user -d $HistoricalDbName -tAc `
    "SELECT (SELECT count(*) FROM companies WHERE slug LIKE 'ecf-%'), (SELECT count(*) FROM ecf_sandbox_e32_trials), (SELECT count(*) FROM ecf_electronic_documents)"
  if ($LASTEXITCODE -ne 0 -or -not $out) { throw "Unable to read historical UAT counts." }
  return ($out.Trim() -split "\|") -join ","
}

function Write-TestBanner {
  Write-Host "FRONT:      $TestFrontName"
  Write-Host "REPO:       $RepoRoot"
  Write-Host "CONTAINER:  $TestContainerName"
  Write-Host "VOLUME:     $TestVolumeName"
  Write-Host "DATABASE:   $TestDbName on 127.0.0.1:$TestDbPort"
  Write-Host "HISTORICAL: NOT USED (fullpos_alanube_uat stays read-only and intact)"
}
