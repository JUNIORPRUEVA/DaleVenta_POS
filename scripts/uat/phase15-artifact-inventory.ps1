param([string]$ExtractorPath)
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
if ($ExtractorPath) {
  $ExtractorPath = (Resolve-Path -LiteralPath $ExtractorPath).Path
  if (-not $ExtractorPath.StartsWith((Join-Path $repo '.uat/tools/').Replace('/', '\'), [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Extractor must be inside the isolated UAT tools directory'
  }
}
$original = 'C:\Users\pc\DEV\PROYECTOS\PRODUCTOS\DaleVentas POS'
$roots = @('C:\src\fullpos-136', 'C:\src\fullpos-137', 'C:\src\fullpos-138',
  'C:\src\fullpos-139', 'C:\src\fullpos-140', 'C:\src\fullpos-141',
  'C:\src\fullpos-release-141-build', 'C:\src\fullpos-release-141-20261013215837',
  "$original\installer", "$original\release", "$original\release_artifacts")
$manifests = @(
  "$original\release_artifacts\windows-release-1.0.6-130-e8473c02-manifest.json",
  "$original\installer\output\windows-release-1.0.6-132-f1be244c-manifest.json")
$manifestRecords = foreach ($path in $manifests) {
  $data = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
  [pscustomobject]@{ path=$path; manifestSha256=(Get-FileHash -LiteralPath $path).Hash;
    artifact=$data.artifact; version=$data.version; commit=$data.commit;
    sha256=$data.sha256; buildTimestampUtc=$data.build_timestamp_utc;
    sourceWorktree=$data.source_worktree; declaredDeployed=$data.deployed }
}
$files = foreach ($root in $roots) {
  if (-not (Test-Path -LiteralPath $root)) { continue }
  # Root-limited discovery; no customer devices, installed apps, env or certificate files.
  & rg --files --hidden --no-ignore $root -g '*.exe' -g '!**/node_modules/**' -g '!**/.git/**' `
    -g '!**/build/**' -g '!**/ephemeral/**' -g '!**/.dart_tool/**' |
    Where-Object { [IO.Path]::GetFileName($_) -match '^(FullPOS.*(Setup|Candidate)|DaleVentas.*Setup|setup\.exe$)' }
}
$payloadChecks = @{}
$records = foreach ($path in @($files | Sort-Object -Unique)) {
  $file = Get-Item -LiteralPath $path
  $sha = (Get-FileHash -LiteralPath $path).Hash
  $signature = Get-AuthenticodeSignature -LiteralPath $path
  $matchingManifests = @($manifestRecords | Where-Object { $_.artifact -eq $file.Name -and $_.sha256 -eq $sha })
  if ($ExtractorPath -and -not $payloadChecks.ContainsKey($sha)) {
    $listingPath = Join-Path $repo ".uat/evidence/phase15-installer-list-$sha.log"
    & $ExtractorPath --list $path *> $listingPath
    if ($LASTEXITCODE -eq 0) {
      $listing = Get-Content -LiteralPath $listingPath -Raw
      $payloadChecks[$sha] = [pscustomobject]@{status='PASS'; containsUpdater=($listing -match '(?i)\\FullposUpdater\.exe"'); evidence=$listingPath}
    } else {
      $payloadChecks[$sha] = [pscustomobject]@{status='BLOCKED'; containsUpdater=$null; evidence=$listingPath}
    }
  }
  [pscustomobject]@{
    path=$file.FullName; productVersion=$file.VersionInfo.ProductVersion.Trim();
    fileVersion=$file.VersionInfo.FileVersion.Trim(); sizeBytes=$file.Length;
    lastWriteUtc=$file.LastWriteTimeUtc.ToString('o'); sha256=$sha;
    signatureStatus=[string]$signature.Status;
    manifestMatches=@($matchingManifests | Select-Object path,version,commit,buildTimestampUtc,declaredDeployed);
    provenance= $(if($matchingManifests.Count){'LOCAL_MANIFEST_HASH_MATCH; distribution unproven'}else{'LOCAL_FILE; distribution/source unproven'});
    updaterPayload= $(if($payloadChecks.ContainsKey($sha)){$payloadChecks[$sha]}else{'UNKNOWN until read-only extraction'});
    isolatedExecution='NOT RUN: requires disposable Windows isolation and outbound network control'
  }
}
$certificates = @(Get-ChildItem Cert:/CurrentUser/My,Cert:/LocalMachine/My -CodeSigningCert -ErrorAction Stop)
$result = [ordered]@{ createdAtUtc=[DateTime]::UtcNow.ToString('o'); roots=$roots;
  artifactCount=@($records).Count; artifacts=@($records); manifests=@($manifestRecords);
  extractor= $(if($ExtractorPath){@{path=$ExtractorPath;sha256=(Get-FileHash -LiteralPath $ExtractorPath).Hash}}else{$null});
  codeSigningCertificateCount=$certificates.Count;
  usablePrivateCodeSigningCertificateCount=@($certificates | Where-Object HasPrivateKey).Count;
  limitations='No installer was executed. No certificate private key was read/exported. A matching local manifest is not evidence of client distribution.' }
$result | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $repo '.uat/evidence/phase15-artifact-inventory.json') -Encoding utf8
"Artifacts inventoried: $(@($records).Count); matching manifest artifacts: $(@($records | Where-Object { $_.manifestMatches.Count -gt 0 }).Count); usable code-signing certificates: $($result.usablePrivateCodeSigningCertificateCount)"
