param([switch]$FinalCandidate)
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$bankName = if ($FinalCandidate) { 'phase16-update-final-bank' } else { 'phase16-update-bank' }
$evidenceName = if ($FinalCandidate) { 'phase16-update-recovery-final.json' } else { 'phase16-update-recovery.json' }
$candidateVersion = if ($FinalCandidate) { '1.0.6.14017' } else { '1.0.6.14016' }
$bank = Join-Path $repo ".uat/$bankName"
if (Test-Path -LiteralPath $bank) { throw 'Refusing to overwrite update recovery evidence' }
New-Item -ItemType Directory -Force "$bank/app", "$bank/candidate", "$bank/databases" | Out-Null
$old = Join-Path $repo '.uat/phase16-native-bank/app'
$candidate = Join-Path $repo '.uat/n16/build/windows/x64/runner/Release'
Copy-Item "$old/*" "$bank/app" -Recurse
Copy-Item "$candidate/*" "$bank/candidate" -Recurse
$sourceDb = Join-Path $repo '.uat/phase13-update-bench/phase11-flutter-client-update/databases/fulltech_offline.db'
Copy-Item -LiteralPath $sourceDb -Destination "$bank/databases/fulltech_offline.db"
$dbHash = (Get-FileHash "$bank/databases/fulltech_offline.db").Hash
$compiler = 'C:\Users\pc\AppData\Local\Programs\Inno Setup 6\ISCC.exe'
& $compiler "/DBank=$bank" "/DCandidateVersion=$candidateVersion" (Join-Path $repo 'scripts/uat/phase16-update-bank.iss') *> "$bank/compile.log"
if ($LASTEXITCODE -ne 0) { throw 'Isolated Inno build failed' }
$package = Join-Path $bank 'packages/FullPOS-Phase16-Recovery-UAT.exe'
$results = foreach ($stage in @('before', 'during', 'after')) {
  $installer = Start-Process -FilePath $package -ArgumentList @('/VERYSILENT','/SUPPRESSMSGBOXES','/SP-','/NORESTART',"/PAUSEAT=$stage","/LOG=$bank/$stage-interrupted.log") -WindowStyle Hidden -PassThru
  for ($i=0; $i -lt 100 -and -not(Test-Path "$bank/pause-$stage.marker"); $i++) { Start-Sleep -Milliseconds 200 }
  if (-not(Test-Path "$bank/pause-$stage.marker")) { throw "Interruption point not observed: $stage" }
  $processes = Get-CimInstance Win32_Process
  $targets = @($installer.Id)
  do { $newTargets = @($processes | Where-Object { $_.ParentProcessId -in $targets -and $_.ProcessId -notin $targets } | Select-Object -ExpandProperty ProcessId); $targets += $newTargets } while ($newTargets.Count)
  foreach ($targetPid in $targets) { Stop-Process -Id $targetPid -ErrorAction SilentlyContinue }
  if ((Get-FileHash "$bank/databases/fulltech_offline.db").Hash -ne $dbHash) { throw 'Interrupted installer changed SQLite' }
  $recovery = Start-Process -FilePath $package -ArgumentList @('/VERYSILENT','/SUPPRESSMSGBOXES','/SP-','/NORESTART',"/LOG=$bank/$stage-recovered.log") -WindowStyle Hidden -Wait -PassThru
  if ($recovery.ExitCode -ne 0) { throw 'Recovery installer failed' }
  if ((Get-FileHash "$bank/app/data/app.so").Hash -ne (Get-FileHash "$bank/candidate/data/app.so").Hash) { throw 'Recovered candidate hash mismatch' }
  if ((Get-FileHash "$bank/databases/fulltech_offline.db").Hash -ne $dbHash) { throw 'Recovery changed SQLite' }
  [pscustomobject]@{stage=$stage;status='PASS';childProcessesInterrupted=$targets.Count;recoveryExit=$recovery.ExitCode;sqliteUnchanged=$true}
}
# Roll back only lab executable files, never its database. This does not prove
# compatibility with a lower schema: the future-schema guard is tested separately.
Copy-Item "$old/*" "$bank/app" -Recurse -Force
if ((Get-FileHash "$bank/databases/fulltech_offline.db").Hash -ne $dbHash) { throw 'Binary rollback changed SQLite' }
$restore = Start-Process -FilePath $package -ArgumentList @('/VERYSILENT','/SUPPRESSMSGBOXES','/SP-','/NORESTART',"/LOG=$bank/final-recovered.log") -WindowStyle Hidden -Wait -PassThru
if ($restore.ExitCode -ne 0) { throw 'Final binary recovery failed' }
[ordered]@{status='PASS';cases=@($results);sqliteSha256=$dbHash;packageSha256=(Get-FileHash $package).Hash;
  binaryRollbackPreservedDatabase=$true;originalsTouched=$false;
  scope='Real isolated Inno replacement before/during/after interruption; no physical power cut, signed UAC or automatic relaunch asserted'} |
  ConvertTo-Json -Depth 6 | Tee-Object -FilePath (Join-Path $repo ".uat/evidence/$evidenceName")
