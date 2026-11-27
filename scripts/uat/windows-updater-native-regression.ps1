param(
  [Parameter(Mandatory=$true)][string]$UpdaterPath,
  [Parameter(Mandatory=$true)][string]$EvidenceRoot,
  [switch]$IncludeParentTimeout
)
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$root = [IO.Path]::GetFullPath($EvidenceRoot)
if (-not $root.StartsWith($repo + '\.uat\', [StringComparison]::OrdinalIgnoreCase)) { throw 'Evidence must stay in repository .uat' }
if (Test-Path -LiteralPath $root) { throw 'Refusing to overwrite evidence' }
$helper = (Resolve-Path -LiteralPath $UpdaterPath).Path
New-Item -ItemType Directory -Path "$root/updates/64002", "$root/other-root" -Force | Out-Null
$package = Join-Path $root 'updates/64002/lab.exe.ready'
Set-Content -LiteralPath $package -Value 'synthetic verification fixture only' -NoNewline
$hash = (Get-FileHash -LiteralPath $package).Hash.ToLowerInvariant()
function Start-Helper([string[]]$Arguments) {
  $process = [Diagnostics.Process]::new()
  $process.StartInfo.FileName = $helper
  $process.StartInfo.Arguments = ($Arguments | ForEach-Object { '"' + ($_ -replace '"','\"') + '"' }) -join ' '
  $process.StartInfo.UseShellExecute = $false
  $process.StartInfo.RedirectStandardOutput = $true
  $process.StartInfo.RedirectStandardError = $true
  [void]$process.Start()
  return $process
}
function Check([string]$Name, [string[]]$Arguments, [int]$Expected) {
  $process = Start-Helper $Arguments
  $stdout = $process.StandardOutput.ReadToEnd()
  $stderr = $process.StandardError.ReadToEnd()
  $process.WaitForExit()
  Set-Content -LiteralPath "$root/$Name.log" -Value ($stdout + $stderr)
  if ($process.ExitCode -ne $Expected) { throw "$Name expected $Expected got $($process.ExitCode)" }
  return [ordered]@{case=$Name;exitCode=$process.ExitCode;status='PASS'}
}
$common = @('--package',$package,'--update-root',"$root/updates",'--expected-sha256',$hash,'--allow-unsigned')
$cases = @()
$cases += Check 'unsigned-explicit' (@('--verify-only') + $common) 0
$cases += Check 'hash-mismatch' @('--verify-only','--package',$package,'--update-root',"$root/updates",'--expected-sha256',('0'*64),'--allow-unsigned') 4
$cases += Check 'outside-root' @('--verify-only','--package',$package,'--update-root',"$root/other-root",'--expected-sha256',$hash,'--allow-unsigned') 3
$cases += Check 'signature-required' @('--verify-only','--package',$package,'--update-root',"$root/updates",'--expected-sha256',$hash,'--expected-publisher','FullPOS Lab') 5
$cases += Check 'invalid-arguments' @('--verify-only','--package',$package) 1
if ($IncludeParentTimeout) {
  $owner = Start-Process -FilePath (Get-Command python).Source -ArgumentList @('-c','"import time; time.sleep(180)"') -WindowStyle Hidden -PassThru
  $ownerStart = $owner.StartTime
  try {
    $first = Start-Helper ($common + @('--parent-pid',"$($owner.Id)",'--log-path',"$root/timeout.log"))
    Start-Sleep -Milliseconds 500
    $cases += Check 'second-updater-rejected' $common 10
    if (-not $first.WaitForExit(135000)) { throw 'Parent timeout did not finish in expected bound' }
    if ($first.ExitCode -ne 11) { throw "Parent timeout unexpectedly allowed installation: $($first.ExitCode)" }
    $log = Get-Content -LiteralPath "$root/timeout.log" -Raw
    if ($log.Contains('installer start requested')) { throw 'Installer started while parent remained alive' }
    $cases += [ordered]@{case='parent-timeout-aborts-before-installer';exitCode=11;status='PASS'}
  } finally {
    $owned = Get-Process -Id $owner.Id -ErrorAction SilentlyContinue
    if ($owned -and $owned.StartTime -eq $ownerStart) { Stop-Process -Id $owned.Id }
  }
}
[ordered]@{status='PASS';helperSha256=(Get-FileHash -LiteralPath $helper).Hash;cases=$cases} |
  ConvertTo-Json -Depth 5 | Tee-Object -FilePath "$root/result.json"
