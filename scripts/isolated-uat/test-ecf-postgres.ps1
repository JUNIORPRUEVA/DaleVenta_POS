. "$PSScriptRoot\_common.ps1"
Assert-IsolatedEnvironment
$ports = docker port $ContainerName 5432/tcp
if ($LASTEXITCODE -ne 0 -or $ports.Trim() -ne '127.0.0.1:56550') { throw 'UAT container binding refused.' }
$identity = docker exec $ContainerName psql -U $DbUser -d $DbName -tAc 'SELECT current_database();'
if ($LASTEXITCODE -ne 0 -or $identity.Trim() -ne $DbName) { throw 'UAT database identity refused.' }
$env:ECF_POSTGRES_UAT = 'true'
$env:ECF_EMISSION_ENABLED = 'false'
$env:ALANUBE_HTTP_TRANSPORT_ENABLED = 'false'
$env:ECF_ALANUBE_AUTH_TESTS_ENABLED = 'false'
Push-Location $RepoRoot
try {
  npm --workspace apps/api test -- --testPathPatterns=src/ecf/documents/.*postgres.integration-spec.ts
  if ($LASTEXITCODE -ne 0) { throw 'ECF PostgreSQL UAT failed.' }
} finally {
  Remove-Item Env:ECF_POSTGRES_UAT -ErrorAction SilentlyContinue
  Pop-Location
}
