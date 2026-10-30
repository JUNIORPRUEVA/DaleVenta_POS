[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..\..")
$secretDir = Join-Path $repoRoot "apps\api\.secrets"
$secretFile = Join-Path $secretDir "alanube-sandbox-token.securestring.xml"

if (-not (Test-Path -LiteralPath $secretDir)) {
  New-Item -ItemType Directory -Path $secretDir | Out-Null
}

if (Test-Path -LiteralPath $secretFile) {
  $answer = Read-Host "An encrypted Alanube Sandbox token already exists. Overwrite it? Type YES to continue"
  if ($answer -ne "YES") {
    Write-Host "Existing encrypted token was preserved."
    exit 0
  }
}

$token = Read-Host "Alanube Sandbox token" -AsSecureString
if ($token.Length -eq 0) {
  throw "Token cannot be empty."
}

$token | Export-Clixml -LiteralPath $secretFile

$acl = Get-Acl -LiteralPath $secretFile
$acl.SetAccessRuleProtection($true, $false)
$rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
  [System.Security.Principal.WindowsIdentity]::GetCurrent().Name,
  "FullControl",
  "Allow"
)
$acl.SetAccessRule($rule)
Set-Acl -LiteralPath $secretFile -AclObject $acl

Write-Host "Alanube Sandbox token stored for the current Windows user."
Write-Host "Secret file: apps/api/.secrets/alanube-sandbox-token.securestring.xml"
Write-Host "Token value: HIDDEN"
