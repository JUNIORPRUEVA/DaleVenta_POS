$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$bank = Join-Path $repo '.uat/phase16-package-verifier'
if (Test-Path -LiteralPath $bank) { throw 'Refusing to overwrite verifier evidence' }
$updates = New-Item -ItemType Directory -Force "$bank/updates/14017"
$source = Join-Path $repo '.uat/phase16-update-final-bank/packages/FullPOS-Phase16-Recovery-UAT.exe'
$package = Join-Path $updates.FullName 'candidate.exe.ready'
Copy-Item -LiteralPath $source -Destination $package
$sha = (Get-FileHash $package).Hash
$incomplete = Join-Path $updates.FullName 'incomplete.exe.ready'
$inputFile = [IO.File]::OpenRead($package)
try { $bytes = [byte[]]::new(4096); $count = $inputFile.Read($bytes,0,$bytes.Length); [IO.File]::WriteAllBytes($incomplete,$bytes[0..($count-1)]) } finally { $inputFile.Dispose() }
$helpers = @{
  authentic132 = Join-Path $repo '.uat/phase15-authentic/132/app/updater/FullposUpdater.exe'
  final14017 = Join-Path $repo '.uat/n16/build/windows/x64/runner/Release/updater/FullposUpdater.exe'
}
$cases = foreach ($helper in $helpers.GetEnumerator()) {
  foreach ($mode in @('valid-lab','hash-mismatch','incomplete','outside-root','signature-required')) {
    $log = Join-Path $bank "$($helper.Key)-$mode.log"
    $file = if ($mode -eq 'incomplete') { $incomplete } elseif ($mode -eq 'outside-root') { $source } else { $package }
    $expectedHash = if ($mode -eq 'hash-mismatch') { '0' * 64 } else { $sha }
    $arguments = @('--verify-only','--package',$file,'--update-root',(Split-Path $updates.FullName),'--expected-sha256',$expectedHash,'--target-build','14017','--log-path',$log)
    if ($mode -ne 'signature-required') { $arguments += '--allow-unsigned' }
    $child = Start-Process -FilePath $helper.Value -ArgumentList $arguments -WindowStyle Hidden -PassThru -Wait
    $expectedExit = switch ($mode) { 'valid-lab' { 0 } 'outside-root' { 3 } 'signature-required' { 5 } default { 4 } }
    if ($child.ExitCode -ne $expectedExit) { throw "Unexpected verifier exit: $($helper.Key) $mode $($child.ExitCode)" }
    [pscustomobject]@{helper=$helper.Key;helperSha256=(Get-FileHash $helper.Value).Hash;mode=$mode;exitCode=$child.ExitCode;status='PASS'}
  }
}
[ordered]@{status='PASS';packageSha256=$sha;cases=@($cases);installed=$false;elevated=$false;
  scope='Unsigned laboratory fixture only; signature-required must reject. No signed publisher or production launch proved.'} |
  ConvertTo-Json -Depth 5 | Tee-Object -FilePath "$repo/.uat/evidence/phase16-package-verifier.json"
