$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$previous = Get-Content "$repo/.uat/evidence/phase15-artifact-inventory.json" -Raw | ConvertFrom-Json
$bank = Join-Path $repo '.uat/phase17-authentic-verified'
if (Test-Path -LiteralPath $bank) { throw 'Refusing to overwrite historical verification evidence' }
New-Item -ItemType Directory -Path $bank | Out-Null
$extractor = $previous.extractor.path
if ((Get-FileHash $extractor).Hash -ne $previous.extractor.sha256) { throw 'Extractor identity changed' }
$artifacts = foreach ($old in $previous.artifacts) {
  $file = Get-Item -LiteralPath $old.path
  $sha = (Get-FileHash $file.FullName).Hash
  if ($sha -ne $old.sha256 -or $file.Length -ne $old.sizeBytes) { throw "Historical artifact changed: $($file.Name)" }
  [pscustomobject]@{path=$file.FullName;sizeBytes=$file.Length;sha256=$sha;
    version=$file.VersionInfo.ProductVersion;signature=[string](Get-AuthenticodeSignature $file.FullName).Status;
    matchesPrevious=$true}
}
$manifests = foreach ($old in $previous.manifests) {
  if ((Get-FileHash $old.path).Hash -ne $old.manifestSha256) { throw 'Historical manifest changed' }
  $document = Get-Content $old.path -Raw | ConvertFrom-Json
  $artifact = @($artifacts | Where-Object { [IO.Path]::GetFileName($_.path) -eq $document.artifact -and $_.sha256 -eq $document.sha256 })
  if ($artifact.Count -ne 1) { throw 'Expected one exact historical artifact per manifest' }
  $version = if ($document.version -eq '1.0.6+130') { '130' } elseif ($document.version -eq '1.0.6+132') { '132' } else { throw 'Unexpected historical manifest version' }
  $destination = Join-Path $bank $version
  New-Item -ItemType Directory -Path $destination | Out-Null
  & $extractor --list $artifact[0].path *> "$bank/list-$version.log"
  if ($LASTEXITCODE -ne 0) { throw 'Installer listing failed' }
  $listing = Get-Content "$bank/list-$version.log" -Raw
  $includes = @('--extract','--output-dir',$destination,'--include','app\app\fullpos_cloud.exe',
    '--include','app\app\data\app.so','--include','app\updater\FullposUpdater.exe',$artifact[0].path)
  & $extractor @includes *> "$bank/extract-$version.log"
  if ($LASTEXITCODE -ne 0) { throw 'Selective extraction failed' }
  [pscustomobject]@{version=$document.version;manifest=$old.path;manifestSha256=$old.manifestSha256;
    commit=$document.commit;artifact=$artifact[0].path;sha256=$artifact[0].sha256;
    containsUpdater=($listing -match '(?i)\\FullposUpdater\.exe"');
    provenance='Matching local manifest, not evidence of customer distribution';installed=$false;appExecuted=$false}
}
$expectedFiles = Get-Content "$repo/.uat/evidence/phase15-extracted-files.json" -Raw | ConvertFrom-Json
$extracted = foreach ($file in @(Get-ChildItem $bank -Recurse -File | Where-Object Extension -ne '.log')) {
  $sha = (Get-FileHash $file.FullName).Hash
  if (@($expectedFiles | Where-Object sha256 -eq $sha).Count -ne 1) { throw 'Extracted content differs from verified historical payload' }
  [pscustomobject]@{path=$file.FullName;sha256=$sha;sizeBytes=$file.Length;
    version=$file.VersionInfo.ProductVersion;signature=[string](Get-AuthenticodeSignature $file.FullName).Status}
}
if (@($extracted).Count -ne 5) { throw 'Expected exactly five whitelisted historical payload files' }
$version133 = foreach ($root in $previous.roots) {
  if (Test-Path -LiteralPath $root) {
    & rg --files --hidden --no-ignore $root -g '*133*' -g '!**/node_modules/**' -g '!**/.git/**' -g '!**/build/**' -g '!**/.dart_tool/**' -g '!**/ephemeral/**'
  }
}
[ordered]@{status='PASS';artifacts=@($artifacts);manifests=@($manifests);extracted=@($extracted);
  searchedRoots=$previous.roots;version133NamedFiles=@($version133);version133= $(if(@($version133 | Where-Object { $_ -match '(?i)setup.*133.*\.exe$' }).Count){'FOUND_REQUIRES_VERIFICATION'}else{'NOT AVAILABLE in bounded search'});
  extractionOnly=$true;authenticAppExecution='BLOCKED: no authorized disposable Windows isolation';
  codeSigningCertificates=@(Get-ChildItem Cert:/CurrentUser/My,Cert:/LocalMachine/My -CodeSigningCert).Count} |
  ConvertTo-Json -Depth 8 | Set-Content "$repo/.uat/evidence/phase17-artifact-verification.json"
"PASS: $(@($artifacts).Count) unchanged historical artifacts; 2 exact manifests; 5 payload files freshly extracted; no installer/app launched"
