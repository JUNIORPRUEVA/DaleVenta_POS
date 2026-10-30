[CmdletBinding()]
param([Parameter(Mandatory)][string]$ActorId, [Parameter(Mandatory)][string]$Manifest,
  [Parameter(Mandatory)][string]$AuthorizationFile, [Parameter(Mandatory)][switch]$ExecuteOnce)
$ErrorActionPreference = 'Stop'
if (-not $ExecuteOnce) { throw 'E32_SEPARATE_AUTHORIZATION_REQUIRED' }
. "$PSScriptRoot\_common.ps1"
Assert-IsolatedEnvironment
$binding = docker port $ContainerName 5432/tcp
if ($LASTEXITCODE -ne 0 -or $binding.Trim() -ne '127.0.0.1:56550') { throw 'E32_UAT_BINDING_REFUSED' }
$env:ECF_EMISSION_ENABLED='false'; $env:ECF_ALANUBE_AUTH_TESTS_ENABLED='false'; $env:ALANUBE_HTTP_TRANSPORT_ENABLED='false'
$cli = Join-Path $RepoRoot 'apps/api/dist/ecf/sandbox/e32-sandbox.cli.js'
Push-Location $RepoRoot
try {
  node $cli --actor $ActorId --manifest $Manifest --authorization $AuthorizationFile
  if ($LASTEXITCODE -ne 0) { throw 'E32_PREFLIGHT_BLOCKED' }
  # No secret is opened by preflight. Decryption occurs only in this separately
  # authorized command; never print the token or pass it as a command argument.
  $tokenFile = Join-Path $ApiRoot '.secrets/alanube-sandbox-token.securestring.xml'
  $secureToken = Import-Clixml -LiteralPath $tokenFile
  if ($secureToken -isnot [securestring]) { throw 'E32_PROTECTED_TOKEN_INVALID' }
  $pointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureToken)
  try {
    $env:ALANUBE_SANDBOX_TOKEN = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($pointer)
    node $cli --actor $ActorId --manifest $Manifest --authorization $AuthorizationFile --execute-once
    if ($LASTEXITCODE -ne 0) { throw 'E32_STOP_REVIEW_REQUIRED_DO_NOT_RETRY' }
  } finally {
    [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer)
    Remove-Item Env:ALANUBE_SANDBOX_TOKEN -ErrorAction SilentlyContinue
  }
} finally { Pop-Location }
