param(
  [Parameter(Mandatory)]
  [ValidateSet('cash_journal_native_test.dart', 'recovery_restart_probe_test.dart')]
  [string]$Target
)
$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$app = Join-Path $root 'apps/fulltech_app'
$evidence = Join-Path $root '.uat/android-isolated-final-20261120/evidence'
$adb = Join-Path $env:LOCALAPPDATA 'Android/Sdk/platform-tools/adb.exe'
$serial = 'emulator-5556'
$package = 'com.daleventa.pos.uat.recovery'
if ((& $adb -s $serial shell getprop ro.boot.qemu.avd_name).Trim() -ne 'FullPOS_Recovery_Closing_20261120') {
  throw 'Refusing to update an unrecognized Android device.'
}
$space = (& $adb -s $serial shell df -k /data | Select-Object -Last 1).Trim() -split '\s+'
if ([long]$space[3] -lt 3145728) { throw 'At least 3 GiB must remain before installation.' }
if (-not ((& $adb -s $serial shell pm path $package) -match '^package:')) {
  throw 'Run the initial acceptance before a journal/restart probe.'
}

# Preserve financial evidence before replacing a test APK. Never use uninstall,
# clear, trim-caches or the Flutter tool's install/retry fallback.
& $adb -s $serial shell am force-stop $package
if ($LASTEXITCODE -ne 0) { throw 'Could not stop the isolated test package.' }
$snapshot = Join-Path $evidence ('snapshots/' + [DateTime]::UtcNow.ToString('yyyyMMdd-HHmmssfff'))
New-Item -ItemType Directory -Path $snapshot -Force | Out-Null
foreach ($name in @('fulltech_offline.uat.db', 'fulltech_offline.uat.db-wal', 'fulltech_offline.uat.db-shm')) {
  $capture = [Diagnostics.ProcessStartInfo]::new($adb)
  foreach ($argument in @('-s', $serial, 'exec-out', 'run-as', $package, 'cat', "databases/$name")) {
    $capture.ArgumentList.Add($argument)
  }
  $capture.UseShellExecute = $false
  $capture.CreateNoWindow = $true
  $capture.RedirectStandardOutput = $true
  $capture.RedirectStandardError = $true
  $captureProcess = [Diagnostics.Process]::Start($capture)
  $destination = Join-Path $snapshot $name
  $stream = [IO.File]::Create($destination)
  try { $captureProcess.StandardOutput.BaseStream.CopyTo($stream) }
  finally { $stream.Dispose() }
  $captureProcess.WaitForExit()
  if ($name.EndsWith('.db') -and ($captureProcess.ExitCode -ne 0 -or (Get-Item $destination).Length -lt 100)) {
    throw 'The financial database could not be backed up; installation cancelled.'
  }
}
Get-ChildItem $snapshot -File | Get-FileHash -Algorithm SHA256 |
  Select-Object Path, Hash | ConvertTo-Json | Set-Content (Join-Path $snapshot 'sha256.json')

Push-Location $app
try {
  $defines = @(
    '--dart-define=FULLPOS_UAT_BUILD=true', '--dart-define=FULLPOS_UAT_PROFILE=true',
    '--dart-define=API_BASE_URL=http://127.0.0.1:4004', '--dart-define=APP_BASE_URL=http://127.0.0.1:4004',
    '--dart-define=UAT_API_BASE=http://127.0.0.1:4004', '--dart-define=DISABLE_APP_UPDATES=true',
    '--dart-define=INTEGRATION_TEST_SHOULD_REPORT_RESULTS_TO_NATIVE=false'
  )
  $buildLog = Join-Path $evidence "build-$Target.log"
  flutter build apk --debug --no-pub --target-platform=android-x64 "--target=integration_test/$Target" @defines *> $buildLog
  if ($LASTEXITCODE -ne 0) { throw 'The isolated test APK did not build.' }
  & $adb -s $serial install -r (Join-Path $app 'build/app/outputs/flutter-apk/app-debug.apk')
  if ($LASTEXITCODE -ne 0) { throw 'APK update failed. No uninstall or retry is permitted.' }
  & $adb -s $serial reverse tcp:4004 tcp:4005
  if ($LASTEXITCODE -ne 0) { throw 'Local API forwarding failed.' }
  $component = (& $adb -s $serial shell cmd package resolve-activity --brief $package |
    Where-Object { $_ -match '^com\.daleventa\.pos\.uat\.recovery/' } | Select-Object -Last 1).Trim()
  if (-not $component) { throw 'The isolated test activity is unavailable.' }
  & $adb -s $serial shell am start -n $component --ez start-paused true
  if ($LASTEXITCODE -ne 0) { throw 'The isolated test activity did not start.' }
  $remoteUri = $null
  for ($attempt = 0; $attempt -lt 30; $attempt++) {
    $appPid = & $adb -s $serial shell pidof $package
    if ($appPid -match '^\d+$') {
      $messages = & $adb -s $serial logcat -d "--pid=$appPid" -s flutter:I
      $observed = [regex]::Matches(($messages -join "`n"), 'The Dart VM service is listening on (http://127\.0\.0\.1:\d+/[^\s]+/)')
      if ($observed.Count -gt 0) { $remoteUri = [uri]$observed[$observed.Count - 1].Groups[1].Value; break }
    }
    Start-Sleep -Seconds 1
  }
  if (-not $remoteUri) { throw 'No observed VM service was available; no reinstall attempted.' }
  $debugPort = & $adb -s $serial forward tcp:0 "tcp:$($remoteUri.Port)"
  if ($debugPort -notmatch '^\d+$') { throw 'Invalid forwarded debug port.' }
  $localUri = [UriBuilder]::new($remoteUri)
  $localUri.Port = [int]$debugPort
  $version = Invoke-RestMethod -Uri "$($localUri.Uri.AbsoluteUri)getVersion" -TimeoutSec 5
  if ($version.result.type -ne 'Version') { throw 'The observed VM service did not respond.' }
  $env:RECOVERY_HOST_EVIDENCE_DIR = $evidence
  $runLog = Join-Path $evidence "run-$Target.log"
  flutter drive --no-pub -d $serial "--use-existing-app=$($localUri.Uri.AbsoluteUri)" `
    --driver=integration_test/recovery_stabilization_driver.dart "--target=integration_test/$Target" --keep-app-running *> $runLog
  if ($LASTEXITCODE -ne 0) { throw "Native acceptance failed; inspect run-$Target.log." }
  Get-Content (Join-Path $evidence "run-$Target.log") -Tail 6
  Write-Output "PASS: $Target. SQLite evidence preserved before APK update."
} finally { Pop-Location }
