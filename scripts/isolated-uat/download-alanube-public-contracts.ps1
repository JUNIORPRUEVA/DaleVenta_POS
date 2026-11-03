# Public documentation only. No credentials, API requests or emission.
$ErrorActionPreference = 'Stop'
$taskRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$outputDirectory = Join-Path $taskRoot 'artifacts\alanube-public-contracts'
New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
foreach ($slug in @('createinvoicefiscals', 'createinvoices', 'createcreditnotes')) {
  $source = "https://developer.alanube.co/reference/$slug"
  $html = (Invoke-WebRequest -Uri $source -TimeoutSec 30).Content
  $match = [regex]::Match($html, '<script id="ssr-props"[^>]*>([\s\S]*?)</script>')
  if (-not $match.Success) { throw "Public schema unavailable: $slug" }
  $props = $match.Groups[1].Value | ConvertFrom-Json -Depth 100
  $schema = $props.document.api.schema
  if ($schema.openapi -ne '3.0.3' -or $schema.info.title -ne 'API FE DOM') { throw 'Unexpected public contract identity.' }
  # Save only the published schema, never the surrounding site config/analytics.
  $target = Join-Path $outputDirectory "$slug.openapi.json"
  $schema | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $target -Encoding utf8
  $hash = (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash
  Write-Output "$slug | OpenAPI $($schema.openapi) | $hash"
}
