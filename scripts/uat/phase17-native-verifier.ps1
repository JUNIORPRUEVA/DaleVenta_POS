$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$bank = Join-Path $repo '.uat/phase17-native-verifier'
if (Test-Path $bank) { throw 'Refusing to overwrite native verification evidence' }
New-Item -ItemType Directory -Path "$bank/updates/17002" | Out-Null
$source = Join-Path $repo '.uat/phase17-update-final-bank/packages/FullPOS-Phase17-Candidate-17002.exe'
$package = Join-Path $bank 'updates/17002/candidate.exe.ready'
Copy-Item $source $package
$sha = (Get-FileHash $package).Hash
$helper = Join-Path $repo '.uat/phase17-update-final-bank/app/updater/FullposUpdater.exe'
$oldHelper = Join-Path $repo '.uat/phase17-authentic-verified/132/app/updater/FullposUpdater.exe'
function Invoke-Verify([string]$Executable,[string]$Mode,[string]$Path,[string]$Hash,[int]$Target,[int]$Expected,[bool]$Unsigned=$true,[int]$Parent=0) {
  $log = Join-Path $bank "$Mode.log"
  $arguments = @('--verify-only','--package',$Path,'--update-root',"$bank/updates",'--expected-sha256',$Hash,'--target-build',"$Target",'--log-path',$log)
  if($Unsigned){$arguments+='--allow-unsigned'}
  if($Parent){$arguments+=@('--parent-pid',"$Parent")}
  $child=Start-Process $Executable -ArgumentList $arguments -WindowStyle Hidden -Wait -PassThru
  if($child.ExitCode -ne $Expected){throw "Unexpected native verification result: $Mode $($child.ExitCode)"}
  [pscustomobject]@{case=$Mode;exitCode=$child.ExitCode;status='PASS';helperSha256=(Get-FileHash $Executable).Hash}
}
$cases = @(
  Invoke-Verify $helper 'valid-final' $package $sha 17002 0
  Invoke-Verify $helper 'changed-target' $package $sha 17003 9
  Invoke-Verify $helper 'wrong-hash' $package ('0'*64) 17002 4
  Invoke-Verify $helper 'outside-root' $source $sha 17002 3
  Invoke-Verify $helper 'signature-required' $package $sha 17002 5 $false
  Invoke-Verify $oldHelper 'authentic132-integrity' $package $sha 17002 0
  Invoke-Verify $oldHelper 'authentic132-signature-required' $package $sha 17002 5 $false
)
$unversioned = Join-Path $bank 'updates/17002/unversioned.ready'
Set-Content $unversioned 'phase17 harmless non-executable fixture'
$cases += Invoke-Verify $helper 'missing-version' $unversioned (Get-FileHash $unversioned).Hash 17002 8
# A change after initial validation/parent wait must fail. --verify-only is kept
# throughout: this test can never invoke ShellExecute/UAC or run the package.
$mutable = Join-Path $bank 'updates/17002/mutable.exe.ready'
Copy-Item $package $mutable
$parent = Start-Process "$env:SystemRoot/System32/ping.exe" -ArgumentList @('127.0.0.1','-n','6') -WindowStyle Hidden -PassThru -RedirectStandardOutput "$bank/parent.log"
$log = Join-Path $bank 'changed-during-parent-wait.log'
$child = Start-Process $helper -ArgumentList @('--verify-only','--package',$mutable,'--update-root',"$bank/updates",'--expected-sha256',$sha,'--target-build','17002','--allow-unsigned','--parent-pid',"$($parent.Id)",'--log-path',$log) -WindowStyle Hidden -PassThru
try {
  for($i=0;$i -lt 100;$i++) {
    if((Test-Path $log) -and (Get-Content $log -Raw) -match 'parent wait started'){break}
    Start-Sleep -Milliseconds 20
  }
  if(-not(Test-Path $log) -or (Get-Content $log -Raw) -notmatch 'parent wait started'){throw 'Parent-wait point not observed'}
  [IO.File]::WriteAllBytes($mutable,[byte[]](1,2,3,4))
  if(-not $child.WaitForExit(10000) -or $child.ExitCode -ne 4){throw 'Post-wait replacement was not rejected'}
  if((Get-Content $log -Raw) -match 'installer start requested'){throw 'Verifier tried to install'}
  $cases += [pscustomobject]@{case='changed-during-parent-wait';status='PASS';exitCode=4;installerStarted=$false}
} finally {
  if(-not $child.HasExited){Stop-Process -Id $child.Id}
  if(-not $parent.HasExited){$parent.WaitForExit(10000)|Out-Null}
}
[ordered]@{status='PASS';cases=@($cases);packageSha256=$sha;installed=$false;elevated=$false;
  scope='New helper binds PE ProductVersion to target and rejects post-wait replacement. Authentic132 only integrity/signature rejection; does not inherit new guards.'} |
  ConvertTo-Json -Depth 6 | Tee-Object -FilePath "$repo/.uat/evidence/phase17-native-verifier.json"
