. "$PSScriptRoot\_common.ps1"
Assert-UatEnvironment
$cloneDb = 'daleventa_offline_safe_48h_phase15_migration_uat'
$backup = Join-Path $RepoRoot '.uat/evidence/phase11_postgres_before.dump'
if (-not (Test-Path -LiteralPath $backup)) { throw 'Pre-expansion backup missing' }
$exists = docker exec $UatPostgresContainer psql -U $UatExpectedDbUser -d $UatExpectedDbName -t -A -c "select count(*) from pg_database where datname='$cloneDb';"
if ($LASTEXITCODE -ne 0 -or "$exists".Trim() -ne '0') { throw 'Refusing to overwrite migration clone' }
docker exec $UatPostgresContainer createdb -U $UatExpectedDbUser $cloneDb
if ($LASTEXITCODE -ne 0) { throw 'Clone creation failed' }
docker cp $backup "${UatPostgresContainer}:/tmp/phase15-before.dump"
if ($LASTEXITCODE -ne 0) { throw 'Backup copy failed' }
docker exec $UatPostgresContainer pg_restore --exit-on-error --no-owner -U $UatExpectedDbUser -d $cloneDb /tmp/phase15-before.dump
if ($LASTEXITCODE -ne 0) { throw 'Clone restore failed' }
function Read-Clone([string]$sql) {
  $value = $sql | docker exec -i $UatPostgresContainer psql -v ON_ERROR_STOP=1 -U $UatExpectedDbUser -d $cloneDb -t -A
  if ($LASTEXITCODE -ne 0) { throw 'Clone SQL failed' }
  return "$value".Trim()
}
if ((Read-Clone 'select current_database();') -ne $cloneDb) { throw 'Unsafe database identity' }
$hashQuery = @'
select 'products|' || count(*) || '|' || md5(coalesce(string_agg((to_jsonb(p)-'create_payload_hash')::text,'' order by id),'')) from "Product" p where company_id='11111111-1111-4111-8111-111111111111'
union all
select 'sales|' || count(*) || '|' || md5(coalesce(string_agg(to_jsonb(s)::text,'' order by id),'')) from "Sale" s where company_id='11111111-1111-4111-8111-111111111111'
union all
select 'inventory|' || count(*) || '|' || md5(coalesce(string_agg((to_jsonb(i)-'operation_id'-'operation_payload_hash')::text,'' order by id),'')) from inventory_movements i where company_id='11111111-1111-4111-8111-111111111111'
union all
select 'cash|' || count(*) || '|' || md5(coalesce(string_agg(to_jsonb(c)::text,'' order by id),'')) from cash_sessions c where company_id='11111111-1111-4111-8111-111111111111';
'@
$before = Read-Clone $hashQuery
$columnsBefore = Read-Clone "select count(*) from information_schema.columns where table_schema=current_schema() and column_name in ('create_payload_hash','operation_payload_hash');"
if ($columnsBefore -ne '0') { throw 'Backup is not pre-expansion; no artificial rollback allowed' }
$uri = [UriBuilder]$env:DATABASE_URL
$uri.Path = $cloneDb
$env:DATABASE_URL = $uri.Uri.AbsoluteUri
$env:UAT_EXPECTED_DB_NAME = $cloneDb
$env:UAT_DB_NAME = $cloneDb
Push-Location $ApiRoot
try { npx prisma migrate deploy; if ($LASTEXITCODE -ne 0) { throw 'Prisma rehearsal failed' } }
finally { Pop-Location }
$after = Read-Clone $hashQuery
if ($before -ne $after) { throw 'Historical tenant contents changed' }
$columnsAfter = Read-Clone "select count(*) from information_schema.columns where table_schema=current_schema() and column_name in ('create_payload_hash','operation_payload_hash');"
if ($columnsAfter -ne '2') { throw 'Missing hash columns' }
$hashes = Read-Clone 'select count(*) from "Product" where company_id=''11111111-1111-4111-8111-111111111111'' and create_payload_hash is not null;'
if ($hashes -ne '0') { throw 'Historical payload hashes were invented' }
[ordered]@{status='PASS'; database=$cloneDb; tenant='11111111-1111-4111-8111-111111111111';
  tenantRowFingerprintsBefore=$before; tenantRowFingerprintsAfter=$after;
  historicalPayloadHashesRemainNull=$true; prismaDeploy=$true; sourceBackupSha256=(Get-FileHash $backup).Hash;
  scope='Authentic local UAT pre-expansion backup; no production or shared migration'} |
  ConvertTo-Json | Tee-Object -FilePath (Join-Path $RepoRoot '.uat/evidence/phase15-migration-rehearsal.json')
