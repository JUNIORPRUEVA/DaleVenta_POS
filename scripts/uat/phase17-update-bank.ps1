$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$bank = Join-Path $repo '.uat/phase17-update-final-bank'
if (Test-Path -LiteralPath $bank) { throw 'Refusing to overwrite updater laboratory evidence' }
$old = Join-Path $repo '.uat/phase16-update-final-bank/candidate'
$candidate = Join-Path $repo '.uat/n17/build/windows/x64/runner/Release'
if ((Get-Item "$candidate/fullpos_cloud.exe").VersionInfo.ProductVersion -notmatch '17002') { throw 'Wrong candidate build' }
function Get-SharedReadHash([string]$Path) {
  $stream = [IO.File]::Open($Path,[IO.FileMode]::Open,[IO.FileAccess]::Read,([IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete))
  $algorithm = [Security.Cryptography.SHA256]::Create()
  try { return [Convert]::ToHexString($algorithm.ComputeHash($stream)) }
  finally { $algorithm.Dispose(); $stream.Dispose() }
}
New-Item -ItemType Directory -Force "$bank/app","$bank/candidate","$bank/databases" | Out-Null
Copy-Item "$old/*" "$bank/app" -Recurse
Copy-Item "$candidate/*" "$bank/candidate" -Recurse
$compiler = 'C:\Users\pc\AppData\Local\Programs\Inno Setup 6\ISCC.exe'
& $compiler "$repo/scripts/uat/phase17-candidate.iss" *> "$bank/compile.log"
if ($LASTEXITCODE -ne 0) { throw 'Isolated candidate packaging failed' }
$nonce = [Guid]::NewGuid().ToString('N')
$owner = Start-Process (Get-Command python).Source -ArgumentList @("$repo/scripts/uat/phase17-live-update-fixture.py",$nonce) -WindowStyle Hidden -PassThru -RedirectStandardOutput "$bank/fixture-stdout.log" -RedirectStandardError "$bank/fixture-stderr.log"
try {
  for ($i=0;$i -lt 150 -and -not(Test-Path "$bank/fixture-ready.json");$i++) { if($owner.HasExited){throw 'SQLite fixture owner failed'}; Start-Sleep -Milliseconds 100 }
  $fixture = Get-Content "$bank/fixture-ready.json" -Raw | ConvertFrom-Json
  if ($fixture.pid -ne $owner.Id -or $fixture.nonce -ne $nonce) { throw 'Unexpected SQLite fixture owner identity' }
  $package = Join-Path $bank 'packages/FullPOS-Phase17-Candidate-17002.exe'
  $cases = foreach ($stage in @('before','during','after')) {
    $installer = Start-Process $package -ArgumentList @('/VERYSILENT','/SUPPRESSMSGBOXES','/SP-','/NORESTART',"/PAUSEAT=$stage","/LOG=$bank/$stage-interrupted.log") -WindowStyle Hidden -PassThru
    for ($i=0;$i -lt 150 -and -not(Test-Path "$bank/pause-$stage.marker");$i++) { Start-Sleep -Milliseconds 100 }
    if (-not(Test-Path "$bank/pause-$stage.marker")) { throw "Missing controlled installer marker: $stage" }
    $processes = Get-CimInstance Win32_Process
    $children = @($installer.Id)
    do { $next = @($processes | Where-Object { $_.ParentProcessId -in $children -and $_.ProcessId -notin $children } | Select-Object -ExpandProperty ProcessId); $children += $next } while ($next.Count)
    foreach ($childPid in $children) { Stop-Process -Id $childPid -ErrorAction SilentlyContinue }
    $recovery = Start-Process $package -ArgumentList @('/VERYSILENT','/SUPPRESSMSGBOXES','/SP-','/NORESTART',"/LOG=$bank/$stage-recovered.log") -WindowStyle Hidden -PassThru -Wait
    if ($recovery.ExitCode -ne 0) { throw 'Candidate reinstallation failed' }
    foreach ($property in $fixture.files.PSObject.Properties) {
      if ((Get-SharedReadHash "$bank/databases/$($property.Name)") -ne $property.Value.sha256) { throw "SQLite family changed: $($property.Name)" }
    }
    if ((Get-FileHash "$bank/app/data/app.so").Hash -ne (Get-FileHash "$bank/candidate/data/app.so").Hash) { throw 'Installed candidate differs' }
    [pscustomobject]@{stage=$stage;status='PASS';recoveryExit=0;dbWalShmUnchanged=$true;fixtureOwnerStillRunning=(-not $owner.HasExited)}
  }
  Set-Content "$bank/fixture-stop.marker" $nonce
  if (-not $owner.WaitForExit(15000) -or $owner.ExitCode -ne 0) { throw 'Post-update native SQLite validation failed' }
  $result = Get-Content "$bank/fixture-result.json" -Raw | ConvertFrom-Json
  [ordered]@{status='PASS';cases=@($cases);fixture=$result;package=$package;packageSha256=(Get-FileHash $package).Hash;
    packageBytes=(Get-Item $package).Length;signature=[string](Get-AuthenticodeSignature $package).Status;
    scope='14017 to17002 isolated Inno replacement with open SQLite/WAL/SHM and8 synthetic pending actions; not historical installers, UAC or physical power loss'} |
    ConvertTo-Json -Depth 8 | Tee-Object -FilePath "$repo/.uat/evidence/phase17-update-bank.json"
} finally {
  if (-not $owner.HasExited) {
    Set-Content "$bank/fixture-stop.marker" $nonce
    if (-not $owner.WaitForExit(10000)) { Stop-Process -Id $owner.Id }
  }
}
