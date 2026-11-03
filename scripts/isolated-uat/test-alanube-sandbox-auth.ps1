[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"

. "$PSScriptRoot\_common.ps1"

$endpoint = "https://sandbox.alanube.co/dom/v1/company"
$secretFile = Join-Path $ApiRoot ".secrets\alanube-sandbox-token.securestring.xml"
$method = "GET"
$requestCount = 0

function Write-Result($key, $value) {
  Write-Host "$($key): $value"
}

function Get-RedactedStatusFromException($errorRecord) {
  $exception = $errorRecord.Exception
  if ($exception.Response -and $exception.Response.StatusCode) {
    return [int]$exception.Response.StatusCode
  }
  return $null
}

Assert-IsolatedEnvironment

if ($env:ALANUBE_ENV -ne "sandbox") { throw "ALANUBE_ENV must be sandbox." }
if ($env:ALANUBE_ENABLE_REAL_CALLS -ne "false") { throw "Global Alanube real calls must remain false." }
if ($env:ECF_EMISSION_ENABLED -eq "true") { throw "E-CF emission must remain disabled." }
if ($env:ECF_ALANUBE_AUTH_TESTS_ENABLED -eq "true") { throw "Global auth tests flag must remain disabled." }
if ($env:ALANUBE_TOKEN_SECRET_REF -ne "env://ALANUBE_SANDBOX_TOKEN") {
  throw "ALANUBE_TOKEN_SECRET_REF must be env://ALANUBE_SANDBOX_TOKEN."
}
if (-not (Test-Path -LiteralPath $secretFile)) {
  throw "Local encrypted Alanube token file is missing."
}

$uri = [Uri]$endpoint
if ($method -ne "GET" -or $uri.Scheme -ne "https" -or $uri.Host -ne "sandbox.alanube.co" -or $uri.AbsolutePath -ne "/dom/v1/company" -or $uri.Query) {
  throw "Endpoint diagnostic policy rejected the request."
}

$secureToken = Import-Clixml -LiteralPath $secretFile
if ($secureToken -isnot [securestring]) {
  throw "Local encrypted Alanube token file is invalid."
}

$tokenPtr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureToken)
$classification = "NOT_EXECUTED"
$statusCode = "N/A"
$elapsedMs = "N/A"
try {
  $tokenValue = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($tokenPtr)
  if ([string]::IsNullOrWhiteSpace($tokenValue)) {
    throw "Local encrypted Alanube token is empty."
  }
  [Environment]::SetEnvironmentVariable("ALANUBE_SANDBOX_TOKEN", $tokenValue, "Process")
  $headers = @{
    "accept" = "application/json"
    "authorization" = "Bearer $tokenValue"
  }
  $started = Get-Date
  $requestCount++
  if ($requestCount -ne 1) { throw "Diagnostic attempted more than one authenticated request." }
  try {
    $response = Invoke-WebRequest -Method Get -Uri $endpoint -Headers $headers -TimeoutSec 20 -MaximumRedirection 0 -UseBasicParsing
    $elapsedMs = [int]((Get-Date) - $started).TotalMilliseconds
    $statusCode = [int]$response.StatusCode
    if ($statusCode -eq 200) {
      try {
        $null = $response.Content | ConvertFrom-Json
        $classification = "AUTH_CONFIRMED"
      } catch {
        $classification = "INVALID_RESPONSE"
      }
    } else {
      $classification = "AUTH_INCONCLUSIVE"
    }
  } catch {
    $elapsedMs = [int]((Get-Date) - $started).TotalMilliseconds
    $code = Get-RedactedStatusFromException $_
    if ($code) {
      $statusCode = $code
      switch ($code) {
        401 { $classification = "AUTH_REJECTED" }
        403 { $classification = "PERMISSION_DENIED" }
        404 { $classification = "AUTH_INCONCLUSIVE" }
        429 { $classification = "RATE_LIMITED" }
        default {
          if ($code -ge 500) { $classification = "NETWORK_ERROR" }
          else { $classification = "INVALID_RESPONSE" }
        }
      }
    } elseif ($_.Exception.Message -match "timed out|timeout") {
      $classification = "TIMEOUT"
    } else {
      $classification = "NETWORK_ERROR"
    }
  }
} finally {
  if ($tokenPtr -ne [IntPtr]::Zero) {
    [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($tokenPtr)
  }
  Remove-Variable -Name tokenValue -ErrorAction SilentlyContinue
  Remove-Variable -Name headers -ErrorAction SilentlyContinue
  [Environment]::SetEnvironmentVariable("ALANUBE_SANDBOX_TOKEN", $null, "Process")
}

Write-Result "ALANUBE_SANDBOX_AUTH_DIAGNOSTIC" "COMPLETE"
Write-Result "ENVIRONMENT" "SANDBOX"
Write-Result "METHOD" $method
Write-Result "PATH" "/dom/v1/company"
Write-Result "HTTP_STATUS" $statusCode
Write-Result "ELAPSED_MS" $elapsedMs
Write-Result "CLASSIFICATION" $classification
Write-Result "REQUEST_COUNT" $requestCount
Write-Result "TOKEN_EXPOSED" "NO"
Write-Result "DOCUMENTS_EMITTED" "0"
Write-Result "DATA_MODIFIED" "0"
Write-Result "ALANUBE_AUTHENTICATION" $classification
