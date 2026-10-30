. "$PSScriptRoot\_common.ps1"

$secretFile = Join-Path $ApiRoot ".secrets\alanube-sandbox-token.securestring.xml"

Assert-IsolatedEnvironment
Assert-ApiPortAvailable

if ($env:ALANUBE_TOKEN_SECRET_REF -ne "env://ALANUBE_SANDBOX_TOKEN") {
  throw "ALANUBE_TOKEN_SECRET_REF must be env://ALANUBE_SANDBOX_TOKEN for this UAT launcher."
}
if ($env:ALANUBE_ENV -ne "sandbox") {
  throw "ALANUBE_ENV must be sandbox."
}
if ($env:ALANUBE_ENABLE_REAL_CALLS -ne "false") {
  throw "Alanube real calls are not authorized."
}
if (-not (Test-Path -LiteralPath $secretFile)) {
  throw "Local encrypted Alanube token file is missing. Run scripts/isolated-uat/set-alanube-sandbox-token.ps1 first."
}

$secureToken = Import-Clixml -LiteralPath $secretFile
if ($secureToken -isnot [securestring]) {
  throw "Local encrypted Alanube token file is invalid."
}

$tokenPtr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureToken)
try {
  $tokenValue = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($tokenPtr)
  if ([string]::IsNullOrWhiteSpace($tokenValue)) {
    throw "Local encrypted Alanube token is empty."
  }
  [Environment]::SetEnvironmentVariable("ALANUBE_SANDBOX_TOKEN", $tokenValue, "Process")
} finally {
  if ($tokenPtr -ne [IntPtr]::Zero) {
    [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($tokenPtr)
  }
  Remove-Variable -Name tokenValue -ErrorAction SilentlyContinue
}

Write-IsolatedBanner
Write-Host "ALANUBE_TOKEN_SECRET_REF: CONFIGURED"
Write-Host "ALANUBE_SANDBOX_TOKEN: LOADED_FOR_PROCESS"
Write-Host "ALANUBE_AUTH: NOT_TESTED"

Push-Location $ApiRoot
try {
  npm run start:dev
} finally {
  [Environment]::SetEnvironmentVariable("ALANUBE_SANDBOX_TOKEN", $null, "Process")
  Pop-Location
}
