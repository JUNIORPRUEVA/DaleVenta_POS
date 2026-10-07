param(
  [Parameter(Mandatory = $true)]
  [string] $UpdaterPath
)

$ErrorActionPreference = 'Stop'

function Assert-ExitCode {
  param(
    [string] $Name,
    [string[]] $Arguments,
    [int] $ExpectedExitCode
  )
  $process = New-Object System.Diagnostics.Process
  $process.StartInfo.FileName = $updater
  $process.StartInfo.Arguments = ($Arguments | ForEach-Object {
    '"' + ($_ -replace '"', '\"') + '"'
  }) -join ' '
  $process.StartInfo.UseShellExecute = $false
  $process.StartInfo.RedirectStandardOutput = $true
  $process.StartInfo.RedirectStandardError = $true
  [void] $process.Start()
  $stdout = $process.StandardOutput.ReadToEnd()
  $stderr = $process.StandardError.ReadToEnd()
  $process.WaitForExit()
  if ($process.ExitCode -ne $ExpectedExitCode) {
    throw "$Name failed. Expected exit $ExpectedExitCode, got $($process.ExitCode). Output: $stdout $stderr"
  }
  Write-Host "$Name PASS"
}

$updater = (Resolve-Path -LiteralPath $UpdaterPath).Path
$root = Join-Path $env:TEMP ("fullpos-updater-harness-" + [guid]::NewGuid())
$outside = Join-Path $env:TEMP ("fullpos-updater-outside-" + [guid]::NewGuid())
New-Item -ItemType Directory -Force -Path $root, $outside | Out-Null

try {
  $buildDir = Join-Path $root '131'
  New-Item -ItemType Directory -Force -Path $buildDir | Out-Null
  $package = Join-Path $buildDir 'setup.ready'
  Set-Content -LiteralPath $package -Value 'uat unsigned package' -NoNewline
  $hash = (Get-FileHash -LiteralPath $package -Algorithm SHA256).Hash.ToLowerInvariant()

  $outsidePackage = Join-Path $outside 'setup.ready'
  Set-Content -LiteralPath $outsidePackage -Value 'uat unsigned package' -NoNewline

  Assert-ExitCode 'valid unsigned UAT verify' @('--verify-only', '--package', $package, '--update-root', $root, '--expected-sha256', $hash, '--allow-unsigned') 0

  Assert-ExitCode 'invalid args rejected' @('--verify-only', '--package', $package) 1

  Assert-ExitCode 'package outside root rejected' @('--verify-only', '--package', $outsidePackage, '--update-root', $root, '--expected-sha256', $hash, '--allow-unsigned') 3

  Assert-ExitCode 'hash mismatch rejected' @('--verify-only', '--package', $package, '--update-root', $root, '--expected-sha256', ('0' * 64), '--allow-unsigned') 4

  Assert-ExitCode 'unsigned production policy rejected' @('--verify-only', '--package', $package, '--update-root', $root, '--expected-sha256', $hash, '--expected-publisher', 'FULLTECH, SRL') 5
}
finally {
  Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
  Remove-Item -LiteralPath $outside -Recurse -Force -ErrorAction SilentlyContinue
}
