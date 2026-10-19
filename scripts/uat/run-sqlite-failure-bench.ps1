param(
  [string] $BenchRoot
)

. "$PSScriptRoot\_common.ps1"

Assert-UatEnvironment
Write-UatBanner

$ErrorActionPreference = 'Stop'

function Resolve-Sqlite {
  $sqlite = (Get-Command sqlite3.exe -ErrorAction SilentlyContinue | Select-Object -First 1)
  if ($sqlite) { return $sqlite.Source }

  $androidSqlite = Join-Path $env:LOCALAPPDATA 'Android\Sdk\platform-tools\sqlite3.exe'
  if (Test-Path -LiteralPath $androidSqlite) { return $androidSqlite }

  throw 'sqlite3.exe is required for the SQLite failure bench.'
}

function Assert-UnderRoot {
  param(
    [Parameter(Mandatory = $true)] [string] $Root,
    [Parameter(Mandatory = $true)] [string] $Path
  )
  $rootFull = [System.IO.Path]::GetFullPath($Root).TrimEnd('\') + '\'
  $pathFull = [System.IO.Path]::GetFullPath($Path)
  if (-not $pathFull.StartsWith($rootFull, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "Unsafe path outside bench root: $pathFull"
  }
}

function Invoke-SqliteRaw {
  param(
    [Parameter(Mandatory = $true)] [string] $SqlitePath,
    [Parameter(Mandatory = $true)] [string[]] $Arguments
  )

  $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
  $startInfo.FileName = $SqlitePath
  $startInfo.UseShellExecute = $false
  $startInfo.RedirectStandardOutput = $true
  $startInfo.RedirectStandardError = $true
  $startInfo.Arguments = ($Arguments | ForEach-Object {
    '"' + ($_ -replace '"', '\"') + '"'
  }) -join ' '

  $process = [System.Diagnostics.Process]::Start($startInfo)
  $stdout = $process.StandardOutput.ReadToEnd()
  $stderr = $process.StandardError.ReadToEnd()
  $process.WaitForExit()

  [pscustomobject]@{
    ExitCode = $process.ExitCode
    Output = (($stdout, $stderr) -join "`n").Trim()
  }
}

$timestamp = Get-Date -Format 'yyyyMMddHHmmss'
if ([string]::IsNullOrWhiteSpace($BenchRoot)) {
  $BenchRoot = Join-Path $RepoRoot ".uat\sqlite-failure-bench-$timestamp"
}

Assert-UnderRoot -Root (Join-Path $RepoRoot '.uat') -Path $BenchRoot

$sqlite = Resolve-Sqlite
New-Item -ItemType Directory -Force -Path $BenchRoot | Out-Null
$db = Join-Path $BenchRoot 'locked-write-test.db'

& $sqlite $db "create table if not exists t(id integer primary key, value text); insert into t(value) values('seed');" | Out-Null

$startInfo = [System.Diagnostics.ProcessStartInfo]::new()
$startInfo.FileName = $sqlite
$startInfo.Arguments = "`"$db`""
$startInfo.UseShellExecute = $false
$startInfo.RedirectStandardInput = $true
$startInfo.RedirectStandardOutput = $true
$startInfo.RedirectStandardError = $true
$lockProcess = [System.Diagnostics.Process]::Start($startInfo)
$lockProcess.StandardInput.WriteLine('.timeout 100')
$lockProcess.StandardInput.WriteLine('BEGIN EXCLUSIVE;')
$lockProcess.StandardInput.WriteLine("INSERT INTO t(value) VALUES('lock-holder');")
$lockProcess.StandardInput.Flush()
Start-Sleep -Seconds 1

$locked = Invoke-SqliteRaw -SqlitePath $sqlite -Arguments @(
  $db,
  '.timeout 100',
  "insert into t(value) values('should-fail-locked');"
)
$lockProcess.StandardInput.WriteLine('COMMIT;')
$lockProcess.StandardInput.WriteLine('.exit')
$lockProcess.StandardInput.Close()
$lockProcess.WaitForExit()

if ($locked.ExitCode -eq 0) {
  throw 'Expected locked write to fail, but sqlite3 write succeeded.'
}
if ($locked.Output -notmatch 'locked|busy') {
  throw "Expected locked/busy error. Actual: $($locked.Output)"
}

$readonlyDb = Join-Path $BenchRoot 'readonly-write-test.db'
Copy-Item -LiteralPath $db -Destination $readonlyDb
Set-ItemProperty -LiteralPath $readonlyDb -Name IsReadOnly -Value $true
try {
  $readonly = Invoke-SqliteRaw -SqlitePath $sqlite -Arguments @(
    $readonlyDb,
    "insert into t(value) values('should-fail-readonly');"
  )
} finally {
  Set-ItemProperty -LiteralPath $readonlyDb -Name IsReadOnly -Value $false
}

if ($readonly.ExitCode -eq 0) {
  throw 'Expected readonly write to fail, but sqlite3 write succeeded.'
}
if ($readonly.Output -notmatch 'readonly|unable|attempt to write') {
  throw "Expected readonly/write error. Actual: $($readonly.Output)"
}

[ordered]@{
  status = 'PASS'
  benchRoot = $BenchRoot
  lockedWriteExitCode = $locked.ExitCode
  lockedWriteError = $locked.Output
  readonlyWriteExitCode = $readonly.ExitCode
  readonlyWriteError = $readonly.Output
  sourceDatabasePreserved = (Test-Path -LiteralPath $db)
} | ConvertTo-Json -Depth 5
