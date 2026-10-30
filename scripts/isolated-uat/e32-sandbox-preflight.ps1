[CmdletBinding()]
param([string]$ActorId = '', [string]$Manifest = '')
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\_common.ps1"
Assert-IsolatedEnvironment
$binding = docker port $ContainerName 5432/tcp
if ($LASTEXITCODE -ne 0 -or $binding.Trim() -ne '127.0.0.1:56550') { throw 'E32_UAT_BINDING_REFUSED' }
$cli = Join-Path $RepoRoot 'apps/api/dist/ecf/sandbox/e32-sandbox.cli.js'
if (-not (Test-Path -LiteralPath $cli)) { throw 'Run npm run api:build before preflight.' }
$env:ECF_EMISSION_ENABLED = 'false'; $env:ECF_ALANUBE_AUTH_TESTS_ENABLED = 'false'; $env:ALANUBE_HTTP_TRANSPORT_ENABLED = 'false'
$arguments = @($cli)
if ($ActorId) { $arguments += @('--actor',$ActorId) }
if ($Manifest) { $arguments += @('--manifest',$Manifest) }
Push-Location $RepoRoot
try { node @arguments; $result = $LASTEXITCODE } finally { Pop-Location }
if ($result -ne 0) { exit $result }
