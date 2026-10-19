param(
  [Parameter(Mandatory = $true)][string]$Installer,
  [Parameter(Mandatory = $true)][string]$Helper
)
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$bank = Join-Path $repo '.uat/combined144-native-verifier'
if (Test-Path -LiteralPath $bank) { throw 'Refusing to overwrite acceptance evidence.' }
New-Item -ItemType Directory -Path "$bank/updates/144" | Out-Null
$package = Join-Path $bank 'updates/144/candidate.exe.ready'
Copy-Item -LiteralPath $Installer -Destination $package
$sha = (Get-FileHash -LiteralPath $package -Algorithm SHA256).Hash
$cases = @(
  @{Name='valid-unsigned-policy';Path=$package;Hash=$sha;Target=144;Expected=0;Unsigned=$true},
  @{Name='changed-target';Path=$package;Hash=$sha;Target=145;Expected=9;Unsigned=$true},
  @{Name='wrong-hash';Path=$package;Hash=('0'*64);Target=144;Expected=4;Unsigned=$true},
  @{Name='outside-root';Path=$Installer;Hash=$sha;Target=144;Expected=3;Unsigned=$true},
  @{Name='signature-required';Path=$package;Hash=$sha;Target=144;Expected=5;Unsigned=$false}
)
$results = foreach ($case in $cases) {
  $log = Join-Path $bank ($case.Name + '.log')
  $args = @('--verify-only','--package',$case.Path,'--update-root',"$bank/updates",
    '--expected-sha256',$case.Hash,'--target-build',"$($case.Target)",'--log-path',$log)
  if ($case.Unsigned) { $args += '--allow-unsigned' }
  $child = Start-Process -FilePath $Helper -ArgumentList $args -WindowStyle Hidden -Wait -PassThru
  if ($child.ExitCode -ne $case.Expected) { throw "Native verification failed: $($case.Name), exit $($child.ExitCode)" }
  if ((Get-Content -LiteralPath $log -Raw) -match 'installer start requested') { throw 'Verifier tried to install.' }
  [pscustomobject]@{case=$case.Name;exitCode=$child.ExitCode;status='PASS'}
}
[ordered]@{status='PASS';sha256=$sha;cases=@($results);installed=$false;elevated=$false} |
  ConvertTo-Json -Depth 5 | Tee-Object -FilePath "$bank/results.json"
