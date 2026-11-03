param()
. "$PSScriptRoot\_test-common.ps1"

Assert-TestEnvironment
Assert-TestDockerAvailable
Write-TestBanner

$identity = (& docker exec $TestContainerName psql -U $TestDbUser -d $TestDbName -tAc "SELECT current_database();").Trim()
if ($identity -ne $TestDbName) { throw "Unexpected database identity: $identity" }
Write-Host "Identity OK: $identity"

$probeId = [guid]::NewGuid().ToString()
& docker exec $TestContainerName psql -U $TestDbUser -d $TestDbName -v ON_ERROR_STOP=1 `
  -c "CREATE TABLE IF NOT EXISTS ecf_test_probe (id text PRIMARY KEY, front text NOT NULL, created_at timestamptz NOT NULL DEFAULT now());" | Out-Null
& docker exec $TestContainerName psql -U $TestDbUser -d $TestDbName -v ON_ERROR_STOP=1 `
  -c "INSERT INTO ecf_test_probe (id, front) VALUES ('$probeId', '$TestFrontName');" | Out-Null
$count = (& docker exec $TestContainerName psql -U $TestDbUser -d $TestDbName -tAc "SELECT count(*) FROM ecf_test_probe WHERE id = '$probeId';").Trim()
if ($count -ne "1") { throw "Controlled write/read probe failed on the ephemeral test database." }
Write-Host "Ephemeral write/read probe OK: $probeId"

# Append-only + RESTRICT integrity must be present in the ephemeral schema too.
$triggers = (& docker exec $TestContainerName psql -U $TestDbUser -d $TestDbName -tAc `
  "SELECT count(*) FROM pg_trigger WHERE NOT tgisinternal AND tgname IN ('ecf_evidence_immutable','ecf_e32_trial_guard','ecf_e32_trial_events_immutable');").Trim()
Write-Host "Integrity triggers present: $triggers (expected 3)"
if ($triggers -ne "3") { throw "Ephemeral schema is missing expected append-only guards." }

Write-Host "Historical UAT counts (read-only): $(Get-HistoricalSyntheticCounts)"
Write-Host "VERIFY OK."
