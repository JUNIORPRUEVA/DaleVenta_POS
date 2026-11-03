param([Parameter(Mandatory = $true)][string]$Pattern)
. "$PSScriptRoot\_test-common.ps1"

Assert-TestEnvironment
Set-Location $RepoRoot

# Deterministic environment for automated tests (ephemeral database only).
$env:ECF_POSTGRES_UAT = "true"
$env:ALANUBE_ENABLE_REAL_CALLS = "false"
$env:ECF_EMISSION_ENABLED = "false"
$env:ECF_ALANUBE_AUTH_TESTS_ENABLED = "false"

# Perfil UAT LOCAL. Sin estos dos flags, suites legítimas fallan por guardas de
# seguridad y no por defectos:
#   - UAT_LOCAL_ONLY habilita el despacho SIMULADO (`simulatedDispatchRefusal`).
#     No habilita nada real: el transporte real sigue bloqueado por
#     ALANUBE_ENABLE_REAL_CALLS=false.
#   - FINANCIAL_LEGACY_COMPAT permite que las peticiones sin identificador de
#     turno sigan el camino legacy; sin él responden 409 LEGACY_MISSING_SESSION.
#     El camino moderno (originCashSessionId) sigue siendo el preferente.
$env:APP_ENV = "uat"
$env:UAT_LOCAL_ONLY = "true"
$env:FINANCIAL_LEGACY_COMPAT = "true"
foreach ($v in 'ALANUBE_TEST_RNC','ALANUBE_TEST_SEQUENCE_FROM','ALANUBE_TEST_SEQUENCE_TO','ALANUBE_TEST_SEQUENCE_EXPIRES_ON','ALANUBE_TOKEN_SECRET_REF','ALANUBE_CREDENTIAL_SOURCE') {
  Remove-Item "env:$v" -ErrorAction SilentlyContinue
}

Set-Location (Join-Path $RepoRoot "apps\api")
& npx jest --runInBand --testPathPatterns $Pattern
exit $LASTEXITCODE
