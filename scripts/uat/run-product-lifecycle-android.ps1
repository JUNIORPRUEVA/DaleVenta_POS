$ErrorActionPreference = 'Stop'
$taskRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$taskApp = Join-Path $taskRoot 'apps/fulltech_app'
$evidence = Join-Path $taskRoot '.uat/product-lifecycle/android'
$adb = Join-Path $env:LOCALAPPDATA 'Android/Sdk/platform-tools/adb.exe'
$serial = 'emulator-5556'
$package = 'com.daleventa.pos.uat.recovery'
if ((& $adb -s $serial shell getprop ro.boot.qemu.avd_name).Trim() -ne 'FullPOS_Recovery_Closing_20261120') {
  throw 'Only the isolated emulator is permitted.'
}
$space = (& $adb -s $serial shell df -k /data | Select-Object -Last 1).Trim() -split '\s+'
if ([long]$space[3] -lt 3145728) { throw 'Insufficient space; preserve all data.' }
New-Item -ItemType Directory -Path $evidence -Force | Out-Null
$resultFile = Join-Path $evidence 'files/product-lifecycle-evidence/native-result.json'
$previousRunId = if (Test-Path -LiteralPath $resultFile) { (Get-Content -LiteralPath $resultFile -Raw | ConvertFrom-Json).runId } else { $null }
& $adb -s $serial shell am force-stop $package
if ($LASTEXITCODE -ne 0) { throw 'Could not stop isolated test package.' }
$snapshot = Join-Path $evidence ('snapshot-' + [DateTime]::UtcNow.ToString('yyyyMMdd-HHmmssfff') + '.tar')
$capture = [Diagnostics.ProcessStartInfo]::new($adb)
foreach ($argument in @('-s',$serial,'exec-out','run-as',$package,'tar','-cf','-','.')) { $capture.ArgumentList.Add($argument) }
$capture.UseShellExecute=$false; $capture.CreateNoWindow=$true; $capture.RedirectStandardOutput=$true; $capture.RedirectStandardError=$true
$process=[Diagnostics.Process]::Start($capture); $stream=[IO.File]::Create($snapshot)
try { $process.StandardOutput.BaseStream.CopyTo($stream) } finally { $stream.Dispose() }
$process.WaitForExit()
if ($process.ExitCode -ne 0 -or (Get-Item $snapshot).Length -lt 1024) { throw 'Backup failed; no installation allowed.' }
Get-FileHash -LiteralPath $snapshot -Algorithm SHA256 | Select-Object Hash | ConvertTo-Json | Set-Content "$snapshot.sha256.json"
Push-Location $taskApp
try {
  flutter build apk --debug --no-pub --target-platform=android-x64 --target=integration_test/product_lifecycle_native_test.dart `
    --dart-define=FULLPOS_UAT_BUILD=true --dart-define=FULLPOS_UAT_PROFILE=true `
    --dart-define=API_BASE_URL=http://127.0.0.1:4004 --dart-define=APP_BASE_URL=http://127.0.0.1:4004 `
    --dart-define=UAT_API_BASE=http://127.0.0.1:4004 --dart-define=DISABLE_APP_UPDATES=true `
    --dart-define=INTEGRATION_TEST_SHOULD_REPORT_RESULTS_TO_NATIVE=false *> (Join-Path $evidence 'build.log')
  if ($LASTEXITCODE -ne 0) { throw 'Test APK build failed.' }
  & $adb -s $serial install -r (Join-Path $taskApp 'build/app/outputs/flutter-apk/app-debug.apk')
  if ($LASTEXITCODE -ne 0) { throw 'Update failed; no uninstall or clear permitted.' }
  & $adb -s $serial reverse tcp:4004 tcp:4017
  & $adb -s $serial push (Join-Path $taskRoot '.uat/product-lifecycle/native-fixture.json') /data/local/tmp/product-lifecycle-auth.json | Out-Null
  & $adb -s $serial shell "run-as $package sh -c 'cat /data/local/tmp/product-lifecycle-auth.json > files/product-lifecycle-auth.json'"
  if ($LASTEXITCODE -ne 0) { throw 'Could not copy synthetic fixture.' }
  & $adb -s $serial shell rm /data/local/tmp/product-lifecycle-auth.json
  $component=(& $adb -s $serial shell cmd package resolve-activity --brief $package | Where-Object {$_ -match '^com\.daleventa\.pos\.uat\.recovery/'} | Select-Object -Last 1).Trim()
  & $adb -s $serial shell am start -n $component --ez start-paused true | Out-Null
  $remoteUri=$null
  for ($attempt=0;$attempt -lt 30;$attempt++) {
    $taskPid=& $adb -s $serial shell pidof $package
    if ($taskPid -match '^\d+$') {
      $messages=& $adb -s $serial logcat -d "--pid=$taskPid" -s flutter:I
      $observed=[regex]::Matches(($messages -join "`n"),'The Dart VM service is listening on (http://127\.0\.0\.1:\d+/[^\s]+/)')
      if ($observed.Count -gt 0) {$remoteUri=[uri]$observed[$observed.Count-1].Groups[1].Value;break}
    }
    Start-Sleep -Seconds 1
  }
  if (-not $remoteUri) { throw 'No observed VM service; no reinstall attempted.' }
  $debugPort=& $adb -s $serial forward tcp:0 "tcp:$($remoteUri.Port)"
  if ($debugPort -notmatch '^\d+$') { throw 'Invalid VM forwarding.' }
  $localUri=[UriBuilder]::new($remoteUri);$localUri.Port=[int]$debugPort
  flutter drive --no-pub -d $serial "--use-existing-app=$($localUri.Uri.AbsoluteUri)" `
    --driver=integration_test/product_lifecycle_driver.dart --target=integration_test/product_lifecycle_native_test.dart `
    --keep-app-running *> (Join-Path $evidence 'run.log')
  if ($LASTEXITCODE -ne 0) { throw 'Android acceptance failed; preserve the evidence.' }
  $runText = Get-Content -LiteralPath (Join-Path $evidence 'run.log') -Raw
  if (-not $runText.Contains('All tests passed') -or $runText.Contains('end of failure')) {
    throw 'Android driver did not report a clean pass; preserve the previous result and current failure log.'
  }
  $extract=[Diagnostics.ProcessStartInfo]::new($adb)
  foreach ($argument in @('-s',$serial,'exec-out','run-as',$package,'tar','-cf','-','files/product-lifecycle-evidence')) {$extract.ArgumentList.Add($argument)}
  $extract.UseShellExecute=$false;$extract.CreateNoWindow=$true;$extract.RedirectStandardOutput=$true
  $copy=[Diagnostics.Process]::Start($extract);$out=[IO.File]::Create((Join-Path $evidence 'evidence.tar'))
  try {$copy.StandardOutput.BaseStream.CopyTo($out)}finally{$out.Dispose()};$copy.WaitForExit()
  if ($copy.ExitCode -ne 0) {throw 'Could not extract evidence.'}
  tar -xf (Join-Path $evidence 'evidence.tar') -C $evidence
  if ($LASTEXITCODE -ne 0) { throw 'Could not unpack Android evidence.' }
  $currentResult = Get-Content -LiteralPath $resultFile -Raw | ConvertFrom-Json
  if ($currentResult.result -ne 'PASS' -or $currentResult.platform -ne 'android' -or
      [string]::IsNullOrWhiteSpace($currentResult.runId) -or $currentResult.runId -eq $previousRunId) {
    throw 'Android result is missing, failed or stale; it cannot be used as current evidence.'
  }
  Get-Content (Join-Path $evidence 'run.log') -Tail 5
} finally {Pop-Location}
