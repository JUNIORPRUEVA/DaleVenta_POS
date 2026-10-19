param([switch]$DisposablePhase12)
. "$PSScriptRoot\_common.ps1"
Assert-UatEnvironment
if ($DisposablePhase12) {
  $cloneUri = [UriBuilder]$env:DATABASE_URL
  $cloneUri.Path = 'daleventa_offline_safe_48h_phase12_uat'
  $env:DATABASE_URL = $cloneUri.Uri.AbsoluteUri
  $env:PORT = '46552'
  $env:UAT_DB_NAME = 'daleventa_offline_safe_48h_phase12_uat'
  $env:FULLPOS_DISPOSABLE_PHASE12 = 'true'
} else {
  $env:FULLPOS_DISPOSABLE_PHASE12 = 'false'
}
Write-UatBanner
Push-Location $RepoRoot
try {
  node scripts/uat/product-stock-integrity-smoke.cjs
  if ($LASTEXITCODE -ne 0) { throw 'Product/stock integrity smoke failed.' }
} finally {
  Pop-Location
}
