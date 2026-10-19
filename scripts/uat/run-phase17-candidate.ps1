$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$manifest = Get-Content "$repo/.uat/evidence/phase17-candidate-manifest.json" -Raw | ConvertFrom-Json
if ($manifest.build -ne 17002 -or $manifest.apiBaseUrl -ne 'http://127.0.0.1:46552' -or -not $manifest.appUpdatesDisabled) { throw 'Unexpected candidate identity' }
$app = Join-Path $repo '.uat/phase17-update-final-bank/app'
foreach ($entry in $manifest.runtimeHashes.PSObject.Properties) {
  $path = [IO.Path]::GetFullPath((Join-Path $app $entry.Name))
  if (-not $path.StartsWith("$app\",[StringComparison]::OrdinalIgnoreCase)) { throw 'Invalid runtime manifest path' }
  if ((Get-FileHash -LiteralPath $path).Hash -ne $entry.Value) { throw "Runtime artifact changed: $($entry.Name)" }
}
$health = Invoke-WebRequest 'http://127.0.0.1:46552/health' -TimeoutSec 5
if ($health.StatusCode -ne 200) { throw 'Local clone API unavailable' }
$executable = Join-Path $app 'fullpos_cloud.exe'
if (Get-Process fullpos_cloud -ErrorAction SilentlyContinue | Where-Object Path -eq $executable) { throw 'Candidate already open; refusing a second instance' }
$env:DALEVENTAS_POS_ROOT = Join-Path $repo '.uat/phase17-visual'
$env:FULLPOS_UAT_MODE = 'offline-safe-48h'
New-Item -ItemType Directory -Path $env:DALEVENTAS_POS_ROOT -Force | Out-Null
# Visible launch is intentional: the owner requested the candidate left open.
$child = Start-Process $executable -WorkingDirectory $app -WindowStyle Normal -PassThru
for ($i=0; $i -lt 100; $i++) {
  Start-Sleep -Milliseconds 100
  $child.Refresh()
  if ($child.HasExited) { throw "Candidate exited: $($child.ExitCode)" }
  if ($child.MainWindowHandle -ne 0) { break }
}
[ordered]@{status='OPEN_FOR_MANUAL_UAT';pid=$child.Id;path=$executable;build=17002;
  observedWindowTitle=$child.MainWindowTitle;dataRoot=$env:DALEVENTAS_POS_ROOT;
  api='http://127.0.0.1:46552';commercialUpdatesDisabled=$true;visualValidation='PENDING';
  scope='Process/window metadata only. No login, sale, print or GUI interaction asserted.'} |
  ConvertTo-Json | Tee-Object -FilePath "$repo/.uat/evidence/phase17-candidate-open.json"
