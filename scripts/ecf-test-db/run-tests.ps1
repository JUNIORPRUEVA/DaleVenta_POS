param()
. "$PSScriptRoot\_test-common.ps1"

Assert-TestEnvironment
Set-Location $RepoRoot

# Deterministic environment for automated tests only.
$env:ECF_POSTGRES_UAT = "true"
$env:ALANUBE_ENABLE_REAL_CALLS = "false"
$env:ECF_EMISSION_ENABLED = "false"
$env:ECF_ALANUBE_AUTH_TESTS_ENABLED = "false"
# Prevent leaked historical-env variables from affecting unit tests.
foreach ($v in 'ALANUBE_TEST_RNC','ALANUBE_TEST_SEQUENCE_FROM','ALANUBE_TEST_SEQUENCE_TO','ALANUBE_TEST_SEQUENCE_EXPIRES_ON','ALANUBE_TOKEN_SECRET_REF','ALANUBE_CREDENTIAL_SOURCE') {
  Remove-Item "env:$v" -ErrorAction SilentlyContinue
}

$before = Get-HistoricalSyntheticCounts
Write-Host "Historical UAT counts BEFORE (companies,trials,documents): $before"

Write-Host "Running the full API suite against the EPHEMERAL test database..."
& npm --workspace apps/api test
$exit = $LASTEXITCODE

$after = Get-HistoricalSyntheticCounts
Write-Host "Historical UAT counts AFTER  (companies,trials,documents): $after"

if ($before -ne $after) {
  throw "ISOLATION VIOLATION: automated tests changed the historical UAT ($before -> $after)."
}
Write-Host "ISOLATION OK: historical UAT unchanged by the automated suite."
if ($exit -ne 0) { throw "Automated suite reported failures (exit $exit)." }
