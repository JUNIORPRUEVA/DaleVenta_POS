[CmdletBinding()]
param(
  [switch]$LoadLocalSecret
)

$ErrorActionPreference = "Stop"

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..\..")
$privateEnvPath = Join-Path $repoRoot "apps\api\.env.alanube.uat.local"
$exampleEnvPath = Join-Path $repoRoot "apps\api\.env.alanube.uat.local.example"
$localSecretPath = Join-Path $repoRoot "apps\api\.secrets\alanube-sandbox-token.securestring.xml"
$clientPath = Join-Path $repoRoot "apps\api\src\ecf\ecf-alanube.client.ts"
$allowedBaseUrl = "https://sandbox.alanube.co/dom/v1"
$allowedCredentialSources = @(
  "alanube-sandbox-attachment",
  "operator-vault",
  "local-dpapi-securestring",
  "windows-credential-manager",
  "company-secret-manager",
  "manual-pending"
)

function Read-EnvMap {
  param([string]$Path)

  $map = @{}
  foreach ($line in Get-Content -LiteralPath $Path) {
    $trimmed = $line.Trim()
    if ($trimmed.Length -eq 0 -or $trimmed.StartsWith("#")) {
      continue
    }
    $separator = $trimmed.IndexOf("=")
    if ($separator -lt 1) {
      continue
    }
    $key = $trimmed.Substring(0, $separator).Trim()
    $value = $trimmed.Substring($separator + 1).Trim()
    $map[$key] = $value
  }
  return $map
}

function Require-Value {
  param(
    [hashtable]$Map,
    [string]$Key
  )

  if (-not $Map.ContainsKey($Key) -or [string]::IsNullOrWhiteSpace([string]$Map[$Key])) {
    return "PENDING"
  }
  return "OK"
}

function Test-SecretReference {
  param([string]$Reference)

  if ([string]::IsNullOrWhiteSpace($Reference)) {
    return @{
      Found = "PENDING"
      Accessible = "PENDING"
      ResolutionSupported = "PENDING"
    }
  }
  if ($Reference -match "^env://([A-Z][A-Z0-9_]{2,128})$") {
    $name = $Matches[1]
    $value = [Environment]::GetEnvironmentVariable($name, "Process")
    if (-not $value) {
      $value = [Environment]::GetEnvironmentVariable($name, "User")
    }
    if (-not $value) {
      $value = [Environment]::GetEnvironmentVariable($name, "Machine")
    }
    $present = if ([string]::IsNullOrWhiteSpace($value)) { "PENDING" } else { "OK" }
    return @{
      Found = $present
      Accessible = $present
      ResolutionSupported = "OK"
    }
  }
  if ($Reference -match "^secret://windows/([A-Za-z0-9._:@/-]{3,160})$") {
    $target = $Matches[1]
    $found = "PENDING"
    if ($IsWindows -or $env:OS -eq "Windows_NT") {
      $null = & cmdkey.exe "/list:$target" 2>$null
      if ($LASTEXITCODE -eq 0) {
        $found = "OK"
      }
    }
    return @{
      Found = $found
      Accessible = $found
      ResolutionSupported = "BLOCKED_UNSUPPORTED"
    }
  }
  if ($Reference -match "^secret://docker/[A-Za-z0-9._-]{3,128}$") {
    return @{
      Found = "NOT_CHECKED_LOCAL"
      Accessible = "NOT_CHECKED_LOCAL"
      ResolutionSupported = "OK"
    }
  }
  return @{
    Found = "INVALID"
    Accessible = "INVALID"
    ResolutionSupported = "INVALID"
  }
}

Push-Location $repoRoot
try {
  if ($LoadLocalSecret) {
    if (-not (Test-Path -LiteralPath $localSecretPath)) {
      throw "Local encrypted Alanube token file is missing."
    }
    $secureToken = Import-Clixml -LiteralPath $localSecretPath
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
  }

  Write-Host "Alanube Sandbox local configuration check"
  Write-Host "Private file path: apps/api/.env.alanube.uat.local"

  if (-not (Test-Path -LiteralPath $exampleEnvPath)) {
    throw "Missing template: apps/api/.env.alanube.uat.local.example"
  }
  Write-Host "Template: OK"

  $ignored = & git check-ignore -q -- "apps/api/.env.alanube.uat.local"
  if ($LASTEXITCODE -ne 0) {
    throw "Private Alanube env file is not ignored by Git."
  }
  Write-Host "Git ignore for private file: OK"

  $trackedPrivate = & git ls-files -- "apps/api/.env.alanube.uat.local"
  if ($trackedPrivate) {
    throw "Private Alanube env file is tracked by Git."
  }
  Write-Host "Private file tracked by Git: NO"

  if (-not (Test-Path -LiteralPath $privateEnvPath)) {
    Write-Host "Private file exists: PENDING"
    Write-Host "Required variables: PENDING"
  } else {
    Write-Host "Private file exists: OK"
    $envMap = Read-EnvMap -Path $privateEnvPath

    if ((Require-Value -Map $envMap -Key "ALANUBE_ENV") -eq "OK" -and $envMap["ALANUBE_ENV"] -ne "sandbox") {
      throw "ALANUBE_ENV must be sandbox."
    }
    Write-Host "ALANUBE_ENV: $(Require-Value -Map $envMap -Key "ALANUBE_ENV")"

    if ((Require-Value -Map $envMap -Key "ALANUBE_BASE_URL") -eq "OK") {
      $baseUrl = ([string]$envMap["ALANUBE_BASE_URL"]).TrimEnd("/")
      if ($baseUrl -ne $allowedBaseUrl) {
        throw "ALANUBE_BASE_URL is not the allowed Sandbox DOM endpoint."
      }
    }
    Write-Host "ALANUBE_BASE_URL: $(Require-Value -Map $envMap -Key "ALANUBE_BASE_URL")"

    if ((Require-Value -Map $envMap -Key "ALANUBE_ENABLE_REAL_CALLS") -eq "OK" -and $envMap["ALANUBE_ENABLE_REAL_CALLS"] -ne "false") {
      throw "ALANUBE_ENABLE_REAL_CALLS must remain false in this phase."
    }
    Write-Host "ALANUBE_ENABLE_REAL_CALLS: $(Require-Value -Map $envMap -Key "ALANUBE_ENABLE_REAL_CALLS")"

    if ((Require-Value -Map $envMap -Key "ALANUBE_CREDENTIAL_SOURCE") -eq "OK") {
      $credentialSource = [string]$envMap["ALANUBE_CREDENTIAL_SOURCE"]
      if ($allowedCredentialSources -notcontains $credentialSource) {
        throw "ALANUBE_CREDENTIAL_SOURCE is not an accepted local source identifier."
      }
    }
    Write-Host "ALANUBE_CREDENTIAL_SOURCE: $(Require-Value -Map $envMap -Key "ALANUBE_CREDENTIAL_SOURCE")"

    if ((Require-Value -Map $envMap -Key "ALANUBE_TOKEN_SECRET_REF") -eq "OK") {
      $secretRef = [string]$envMap["ALANUBE_TOKEN_SECRET_REF"]
      if ($secretRef -notmatch "^env://[A-Z][A-Z0-9_]{2,128}$") {
        throw "ALANUBE_TOKEN_SECRET_REF must be a reference, not a raw token."
      }
    }
    Write-Host "ALANUBE_TOKEN_SECRET_REF: $(Require-Value -Map $envMap -Key "ALANUBE_TOKEN_SECRET_REF")"
    $secretStatus = Test-SecretReference -Reference ([string]$envMap["ALANUBE_TOKEN_SECRET_REF"])
    Write-Host "ALANUBE_TOKEN_CREDENTIAL_FOUND: $($secretStatus.Found)"
    Write-Host "ALANUBE_TOKEN_ACCESSIBLE_BY_PROCESS: $($secretStatus.Accessible)"
    Write-Host "ALANUBE_TOKEN_RESOLUTION_SUPPORTED: $($secretStatus.ResolutionSupported)"
    Write-Host "ALANUBE_TOKEN_VALID_WITH_PROVIDER: NOT_TESTED"

    foreach ($key in @(
      "ALANUBE_TEST_RNC",
      "ALANUBE_TEST_SEQUENCE_FROM",
      "ALANUBE_TEST_SEQUENCE_TO",
      "ALANUBE_TEST_SEQUENCE_EXPIRES_ON"
    )) {
      Write-Host "$($key): $(Require-Value -Map $envMap -Key $key)"
    }
    Write-Host "ALANUBE_TEST_SEQUENCE_PREFIX: OPTIONAL"
  }

  $clientSource = Get-Content -LiteralPath $clientPath -Raw
  foreach ($pattern in @("fetch\(", "Authorization", "Bearer", "axios", "http\.request", "https\.request")) {
    if ($clientSource -match $pattern) {
      throw "Unexpected HTTP/auth transport pattern found in EcfAlanubeClient."
    }
  }
  Write-Host "Alanube client HTTP transport: ABSENT"
  Write-Host "Production calls: BLOCKED"
  Write-Host "Emission: BLOCKED"
  Write-Host "Result: PASS"
} finally {
  if ($LoadLocalSecret) {
    [Environment]::SetEnvironmentVariable("ALANUBE_SANDBOX_TOKEN", $null, "Process")
  }
  Pop-Location
}
