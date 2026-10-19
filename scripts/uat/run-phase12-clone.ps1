# Starts only the disposable phase12 database clone. Never restores over manual UAT.
param([switch]$ExistingClone)
. "$PSScriptRoot\_common.ps1"
Assert-UatEnvironment
$cloneDb = 'daleventa_offline_safe_48h_phase12_uat'
$backup = Join-Path $RepoRoot '.uat\evidence\phase12-postgres-before.dump'
if (-not (Test-Path -LiteralPath $backup)) { throw 'Phase12 consistent backup is required.' }
if (Get-NetTCPConnection -LocalPort 46552 -State Listen -ErrorAction SilentlyContinue) { throw 'Clone API port already occupied.' }
$exists = docker exec $UatPostgresContainer psql -U $UatExpectedDbUser -d $UatExpectedDbName -t -A -c "select count(*) from pg_database where datname='$cloneDb';"
if ($LASTEXITCODE -ne 0) { throw 'Source identity unavailable.' }
if ($ExistingClone) {
  if ("$exists".Trim() -ne '1') { throw 'Expected existing clone is missing.' }
} else {
  if ("$exists".Trim() -ne '0') { throw 'Clone already exists; refusing to overwrite.' }
  docker exec $UatPostgresContainer createdb -U $UatExpectedDbUser $cloneDb
  if ($LASTEXITCODE -ne 0) { throw 'Clone creation failed.' }
  docker cp $backup "${UatPostgresContainer}:/tmp/phase12-clone-source.dump"
  if ($LASTEXITCODE -ne 0) { throw 'Backup copy failed.' }
  docker exec $UatPostgresContainer pg_restore --exit-on-error --no-owner -U $UatExpectedDbUser -d $cloneDb /tmp/phase12-clone-source.dump
  if ($LASTEXITCODE -ne 0) { throw 'Clone restore failed.' }
}
$identity = docker exec $UatPostgresContainer psql -U $UatExpectedDbUser -d $cloneDb -t -A -c 'select current_database();'
if ($LASTEXITCODE -ne 0 -or "$identity".Trim() -ne $cloneDb) { throw 'Clone identity failed.' }
$cloneUrl = [UriBuilder]$env:DATABASE_URL
$cloneUrl.Path = $cloneDb
$env:DATABASE_URL = $cloneUrl.Uri.AbsoluteUri
$env:UAT_EXPECTED_DB_NAME = $cloneDb
$env:UAT_DB_NAME = $cloneDb
$env:PORT = '46552'
$env:RUN_SEED = 'false'
$env:RUN_MIGRATIONS = 'false'
Write-UatBanner
Push-Location $ApiRoot
try { node dist/main.js } finally { Pop-Location }
