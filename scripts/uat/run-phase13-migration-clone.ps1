param([switch]$PrismaDeploy)
. "$PSScriptRoot\_common.ps1"
Assert-UatEnvironment
$cloneDb = if ($PrismaDeploy) { 'daleventa_offline_safe_48h_phase13_prisma_uat' } else { 'daleventa_offline_safe_48h_phase13_migration_uat' }
$backup = Join-Path $RepoRoot '.uat/evidence/phase11_postgres_before.dump'
if (-not (Test-Path -LiteralPath $backup)) { throw 'Verified pre-hash backup is missing.' }
$exists = docker exec $UatPostgresContainer psql -U $UatExpectedDbUser -d $UatExpectedDbName -t -A -c "select count(*) from pg_database where datname='$cloneDb';"
if ($LASTEXITCODE -ne 0 -or "$exists".Trim() -ne '0') { throw 'Refusing to overwrite a migration clone.' }
docker exec $UatPostgresContainer createdb -U $UatExpectedDbUser $cloneDb
if ($LASTEXITCODE -ne 0) { throw 'Clone creation failed.' }
docker cp $backup "${UatPostgresContainer}:/tmp/phase13-pre-hash.dump"
if ($LASTEXITCODE -ne 0) { throw 'Backup copy failed.' }
docker exec $UatPostgresContainer pg_restore --exit-on-error --no-owner -U $UatExpectedDbUser -d $cloneDb /tmp/phase13-pre-hash.dump
if ($LASTEXITCODE -ne 0) { throw 'Restore failed.' }
function Read-Clone([string]$Sql) {
  $result = $Sql | docker exec -i $UatPostgresContainer psql -v ON_ERROR_STOP=1 -U $UatExpectedDbUser -d $cloneDb -t -A
  if ($LASTEXITCODE -ne 0) { throw 'Clone SQL failed.' }
  return "$result".Trim()
}
if ((Read-Clone 'select current_database();') -ne $cloneDb) { throw 'Clone identity mismatch.' }
$countsSql = @'
select (select count(*) from "Product" where company_id='11111111-1111-4111-8111-111111111111') || '|' ||
 (select count(*) from "Sale" where company_id='11111111-1111-4111-8111-111111111111') || '|' ||
 (select count(*) from inventory_movements where company_id='11111111-1111-4111-8111-111111111111');
'@
$before = Read-Clone $countsSql
$hashColumns = Read-Clone "select count(*) from information_schema.columns where table_schema=current_schema() and column_name in ('create_payload_hash','operation_payload_hash');"
if ($hashColumns -ne '0') { throw 'Backup is not the pre-hash snapshot; refusing artificial rollback.' }
if ($PrismaDeploy) {
  $cloneUrl = [UriBuilder]$env:DATABASE_URL
  $cloneUrl.Path = $cloneDb
  $env:DATABASE_URL = $cloneUrl.Uri.AbsoluteUri
  $env:UAT_EXPECTED_DB_NAME = $cloneDb
  $env:UAT_DB_NAME = $cloneDb
  Push-Location $ApiRoot
  try { npx prisma migrate deploy; if ($LASTEXITCODE -ne 0) { throw 'Prisma deployment rehearsal failed.' } }
  finally { Pop-Location }
} else {
foreach ($migration in @('20261014113000_inventory_movement_operation_id','20261014153000_offline_operation_payload_hash')) {
  Get-Content -LiteralPath (Join-Path $RepoRoot "apps/api/prisma/migrations/$migration/migration.sql") | docker exec -i $UatPostgresContainer psql -v ON_ERROR_STOP=1 -U $UatExpectedDbUser -d $cloneDb | Out-Null
  if ($LASTEXITCODE -ne 0) { throw "Additive migration failed: $migration" }
}
}
$after = Read-Clone $countsSql
if ($before -ne $after) { throw 'Tenant row counts changed.' }
$nulls = Read-Clone 'select count(*) from "Product" where company_id=''11111111-1111-4111-8111-111111111111'' and create_payload_hash is not null;'
if ($nulls -ne '0') { throw 'Historical hashes were unexpectedly rewritten.' }
$result = [ordered]@{ status='PASS'; database=$cloneDb; tenant='11111111-1111-4111-8111-111111111111'; before=$before; after=$after; previousHashColumns=0; destructiveRollbackAttempted=$false; historicalHashesRemainNull=$true; prismaMigrateDeploy=[bool]$PrismaDeploy }
$evidence = if ($PrismaDeploy) { '.uat/evidence/phase13-prisma-migration-clone.json' } else { '.uat/evidence/phase13-migration-clone.json' }
$result | ConvertTo-Json | Tee-Object -FilePath (Join-Path $RepoRoot $evidence)
