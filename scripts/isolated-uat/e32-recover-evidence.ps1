[CmdletBinding()]
param([Parameter(Mandatory)][switch]$ExecuteAuthorizedOneGet)
$ErrorActionPreference='Stop'
. "$PSScriptRoot\_common.ps1"
Assert-IsolatedEnvironment
if (-not $ExecuteAuthorizedOneGet) { throw 'SPECIFIC_GET_AUTHORIZATION_REQUIRED' }
$env:ALANUBE_ENABLE_REAL_CALLS='false'; $env:ECF_EMISSION_ENABLED='false'; $env:ECF_ALANUBE_AUTH_TESTS_ENABLED='false'
$env:NODE_USE_ENV_PROXY='0'
Remove-Item Env:ALANUBE_SANDBOX_TOKEN -ErrorAction SilentlyContinue
Push-Location $RepoRoot
try {
  node ./scripts/isolated-uat/e32-recover-evidence.cjs --check
  if($LASTEXITCODE -ne 0){throw 'GET_PREFLIGHT_BLOCKED'}
  $protectedToken=Import-Clixml -LiteralPath (Join-Path $ApiRoot '.secrets/alanube-sandbox-token.securestring.xml')
  if($protectedToken -isnot [securestring]){throw 'PROTECTED_SANDBOX_TOKEN_REQUIRED'}
  $pointer=[Runtime.InteropServices.Marshal]::SecureStringToBSTR($protectedToken)
  try {
    $env:ALANUBE_SANDBOX_TOKEN=[Runtime.InteropServices.Marshal]::PtrToStringBSTR($pointer)
    node ./scripts/isolated-uat/e32-recover-evidence.cjs --execute-authorized-one-get
    if($LASTEXITCODE -ne 0){throw 'GET_STOPPED_NO_RETRY'}
  } finally {
    [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer)
    Remove-Item Env:ALANUBE_SANDBOX_TOKEN -ErrorAction SilentlyContinue
  }
} finally { Pop-Location }
