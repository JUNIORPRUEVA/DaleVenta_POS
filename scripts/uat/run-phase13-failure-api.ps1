# Separate PostgreSQL container: failure injection never stops the manual DB.
param([switch]$ExistingContainer)
. "$PSScriptRoot\_common.ps1"
Assert-UatEnvironment
$failureContainer = 'fullpos_phase13_failure_postgres'
$failureDb = 'daleventa_offline_safe_48h_failure_uat'
if (Get-NetTCPConnection -LocalPort 46554 -State Listen -ErrorAction SilentlyContinue) { throw 'Failure API port occupied.' }
if (-not $ExistingContainer) {
  if (Get-NetTCPConnection -LocalPort 56593 -State Listen -ErrorAction SilentlyContinue) { throw 'Failure DB port occupied.' }
  $env:POSTGRES_PASSWORD = $env:UAT_DB_PASSWORD
  docker run -d --name $failureContainer --label fullpos.uat.phase=13 -p 127.0.0.1:56593:5432 -e POSTGRES_PASSWORD -e "POSTGRES_USER=$UatExpectedDbUser" -e "POSTGRES_DB=$failureDb" postgres:16-alpine | Out-Null
  if ($LASTEXITCODE -ne 0) { throw 'Separate failure container could not be created; no existing resource is overwritten.' }
  $ready = $false
  for ($attempt = 0; $attempt -lt 30; $attempt++) {
    docker exec $failureContainer pg_isready -h 127.0.0.1 -U $UatExpectedDbUser -d $failureDb *> $null
    if ($LASTEXITCODE -eq 0) { $ready = $true; break }
    Start-Sleep -Milliseconds 500
  }
  if (-not $ready) { throw 'Failure DB startup timed out.' }
  docker cp (Join-Path $RepoRoot '.uat/evidence/phase13-postgres-before.dump') "${failureContainer}:/tmp/phase13-source.dump"
  if ($LASTEXITCODE -ne 0) { throw 'Failure backup copy failed.' }
  docker exec $failureContainer pg_restore --exit-on-error --no-owner -U $UatExpectedDbUser -d $failureDb /tmp/phase13-source.dump
  if ($LASTEXITCODE -ne 0) { throw 'Failure DB restore failed.' }
}
$label = docker inspect --format '{{index .Config.Labels "fullpos.uat.phase"}}' $failureContainer
if ($LASTEXITCODE -ne 0 -or "$label".Trim() -ne '13') { throw 'Failure container identity mismatch.' }
$identity = docker exec $failureContainer psql -U $UatExpectedDbUser -d $failureDb -t -A -c 'select current_database();'
if ($LASTEXITCODE -ne 0 -or "$identity".Trim() -ne $failureDb) { throw 'Failure DB identity mismatch.' }
$failureUrl = [UriBuilder]$env:DATABASE_URL
$failureUrl.Path = $failureDb
$failureUrl.Port = 56593
$env:DATABASE_URL = $failureUrl.Uri.AbsoluteUri
$env:UAT_DB_NAME = $failureDb
$env:UAT_EXPECTED_DB_NAME = $failureDb
$env:UAT_DB_PORT = '56593'
$env:PORT = '46554'
Write-UatBanner
Push-Location $ApiRoot
try { node dist/main.js } finally { Pop-Location }
