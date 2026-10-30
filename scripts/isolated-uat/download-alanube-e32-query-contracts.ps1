# Public developer documentation only; no API calls or credentials.
$ErrorActionPreference = 'Stop'
$taskRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$destination = Join-Path $taskRoot 'artifacts/alanube-public-contracts'
foreach ($slug in @('checkinvoices', 'checkinvoicesbycompany', 'checkpurchases')) {
  $target = Join-Path $destination "$slug.openapi.json"
  if (Test-Path -LiteralPath $target) {
    Write-Output "$slug EXISTING_SHA256=$((Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash)"
    continue
  }
  $html = (Invoke-WebRequest -Uri "https://developer.alanube.co/reference/$slug" -TimeoutSec 30).Content
  $match = [regex]::Match($html, '<script id="ssr-props"[^>]*>([\s\S]*?)</script>')
  if (-not $match.Success) { throw 'E32_PUBLIC_SCHEMA_UNAVAILABLE' }
  $schema = ($match.Groups[1].Value | ConvertFrom-Json -Depth 100).document.api.schema
  if ($schema.openapi -ne '3.0.3' -or $schema.info.title -ne 'API FE DOM') { throw 'E32_PUBLIC_SCHEMA_IDENTITY_INVALID' }
  $schema | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $target -Encoding utf8
  Write-Output "$slug SHA256=$((Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash)"
}
