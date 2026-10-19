$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$bank = Join-Path $repo '.uat/phase15-native-verifier'
if (Test-Path -LiteralPath $bank) { throw 'Refusing to overwrite verifier evidence' }
$updates = New-Item -ItemType Directory -Force (Join-Path $bank 'updates/15001')
$sourcePackage = Join-Path $repo '.uat/phase14-native-bank/packages/FullPOS-Phase14-Native-UAT-B.exe'
$package = Join-Path $updates.FullName 'phase14-candidate.exe.ready'
Copy-Item -LiteralPath $sourcePackage -Destination $package
$sha = (Get-FileHash -LiteralPath $package).Hash
if ($sha -ne 'A0D74F3A1108BF67EF4AE9B3727ABA13729A72CE3DA70C815F3039DED630C552') { throw 'Approved candidate hash changed' }
$helpers = @{
  historical132 = Join-Path $repo '.uat/phase15-authentic/132/app/updater/FullposUpdater.exe'
  candidate = Join-Path $repo '.uat/phase14-native-bank/version-b/updater/FullposUpdater.exe'
}
$cases = foreach ($entry in $helpers.GetEnumerator()) {
  foreach ($mode in @('uat-unsigned', 'wrong-hash', 'signature-required')) {
    $log = Join-Path $bank "$($entry.Key)-$mode.log"
    $expectedHash = if ($mode -eq 'wrong-hash') { '0' * 64 } else { $sha }
    $args = @('--verify-only', '--package', $package, '--update-root', (Split-Path $updates.FullName),
      '--expected-sha256', $expectedHash, '--target-build', '15001', '--log-path', $log)
    if ($mode -ne 'signature-required') { $args += '--allow-unsigned' }
    $process = Start-Process -FilePath $entry.Value -ArgumentList $args -WindowStyle Hidden -PassThru -Wait
    $text = Get-Content -LiteralPath $log -Raw
    if ($mode -eq 'uat-unsigned') {
      if ($process.ExitCode -ne 0 -or $text -notmatch 'verify-only success') { throw 'Valid UAT fixture rejected' }
    } elseif ($process.ExitCode -eq 0 -or $text -notmatch 'validation failed') {
      throw 'Invalid package accepted'
    }
    [pscustomobject]@{helper=$entry.Key; helperSha256=(Get-FileHash -LiteralPath $entry.Value).Hash;
      mode=$mode; exitCode=$process.ExitCode; result='PASS'; log=$log}
  }
}
[ordered]@{status='PASS'; packageSha256=$sha; cases=@($cases);
  installed=$false; elevated=$false; relaunched=$false;
  scope='Authentic extracted +132 helper and candidate helper, verification only; signature-required rejects unsigned package'} |
  ConvertTo-Json -Depth 6 | Tee-Object -FilePath (Join-Path $repo '.uat/evidence/phase15-native-verifier.json')
