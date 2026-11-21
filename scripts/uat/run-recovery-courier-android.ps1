$ErrorActionPreference = 'Stop'
$taskRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$taskApp = Join-Path $taskRoot 'apps/fulltech_app'
$evidence = Join-Path $taskRoot '.uat/courier'
$adb = Join-Path $env:LOCALAPPDATA 'Android/Sdk/platform-tools/adb.exe'
$serial = 'emulator-5556'
$package = 'com.daleventa.pos.uat.recovery'
if ((& $adb -s $serial shell getprop ro.boot.qemu.avd_name).Trim() -ne 'FullPOS_Recovery_Closing_20261120') {
  throw 'Refusing to install outside the isolated recovery emulator.'
}
$space = (& $adb -s $serial shell df -k /data | Select-Object -Last 1).Trim() -split '\s+'
if ([long]$space[3] -lt 3145728) { throw 'Insufficient space: keep all existing data and stop.' }
$installed = (& $adb -s $serial shell pm path $package) -match '^package:'
if ($installed) {
  & $adb -s $serial shell am force-stop $package
  $snapshot = Join-Path $evidence ('snapshot-' + [DateTime]::UtcNow.ToString('yyyyMMdd-HHmmssfff'))
  New-Item -ItemType Directory $snapshot -Force | Out-Null
  foreach ($name in @('fulltech_offline.uat.db','fulltech_offline.uat.db-wal','fulltech_offline.uat.db-shm')) {
    & $adb -s $serial exec-out run-as $package cat "databases/$name" > (Join-Path $snapshot $name)
    if ($name.EndsWith('.db') -and ($LASTEXITCODE -ne 0 -or (Get-Item (Join-Path $snapshot $name)).Length -lt 100)) {
      throw 'Could not preserve the existing SQLite evidence.'
    }
  }
}
& $adb -s $serial install -r (Join-Path $taskApp 'build/app/outputs/flutter-apk/app-debug.apk')
if ($LASTEXITCODE -ne 0) { throw 'Install failed. No uninstall, clear or fallback allowed.' }
& $adb -s $serial reverse tcp:4004 tcp:4005
if ($LASTEXITCODE -ne 0) { throw 'Could not forward the isolated local API.' }
$remote = '/data/local/tmp/fullpos-courier-auth.json'
& $adb -s $serial push (Join-Path $evidence 'auth.json') $remote | Out-Null
& $adb -s $serial shell run-as $package mkdir -p files
& $adb -s $serial shell run-as $package cp $remote files/courier-auth.json
if ($LASTEXITCODE -ne 0) { throw 'Could not prepare private local fixture.' }
& $adb -s $serial shell rm $remote # Remove only this disposable credential copy.
$component = (& $adb -s $serial shell cmd package resolve-activity --brief $package |
  Where-Object { $_ -match '^com\.daleventa\.pos\.uat\.recovery/' } | Select-Object -Last 1).Trim()
if (-not $component) { throw 'UAT activity not found.' }
& $adb -s $serial shell am start -n $component --ez start-paused true | Out-Null
$remoteUri = $null
for ($attempt = 0; $attempt -lt 30; $attempt++) {
  $taskPid = & $adb -s $serial shell pidof $package
  if ($taskPid -match '^\d+$') {
    $messages = & $adb -s $serial logcat -d "--pid=$taskPid" -s flutter:I
    $observed = [regex]::Matches(($messages -join "`n"), 'The Dart VM service is listening on (http://127\.0\.0\.1:\d+/[^\s]+/)')
    if ($observed.Count -gt 0) { $remoteUri = [uri]$observed[$observed.Count-1].Groups[1].Value; break }
  }
  Start-Sleep -Seconds 1
}
if (-not $remoteUri) { throw 'UAT VM service not found; keep all evidence.' }
$port = & $adb -s $serial forward tcp:0 "tcp:$($remoteUri.Port)"
if ($port -notmatch '^\d+$') { throw 'Invalid VM forwarding.' }
$localUri = [UriBuilder]::new($remoteUri); $localUri.Port = [int]$port
$env:RECOVERY_HOST_EVIDENCE_DIR = $evidence
Push-Location $taskApp
try {
  flutter drive --no-pub -d $serial "--use-existing-app=$($localUri.Uri.AbsoluteUri)" `
    --driver=integration_test/recovery_stabilization_driver.dart `
    --target=integration_test/recovery_courier_native_test.dart --keep-app-running *> (Join-Path $evidence 'android-run.log')
  if ($LASTEXITCODE -ne 0) { throw 'Native courier acceptance failed; inspect the preserved log.' }
  Get-Content (Join-Path $evidence 'android-run.log') -Tail 6
} finally { Pop-Location }
