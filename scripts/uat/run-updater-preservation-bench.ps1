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

  throw 'sqlite3.exe is required for the preservation bench.'
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

function Sha256 {
  param([Parameter(Mandatory = $true)] [string] $Path)
  return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

$timestamp = Get-Date -Format 'yyyyMMddHHmmss'
if ([string]::IsNullOrWhiteSpace($BenchRoot)) {
  $BenchRoot = Join-Path $RepoRoot ".uat\updater-preservation-bench-$timestamp"
}

Assert-UnderRoot -Root (Join-Path $RepoRoot '.uat') -Path $BenchRoot

$sqlite = Resolve-Sqlite
$appRoot = Join-Path $BenchRoot 'windows-app-root'
$dbDir = Join-Path $appRoot 'databases'
$updatesDir = Join-Path $appRoot 'updates'
$logsDir = Join-Path $appRoot 'logs'
$db = Join-Path $dbDir 'fulltech_offline.db'
$wal = "$db-wal"
$shm = "$db-shm"

New-Item -ItemType Directory -Force -Path $dbDir, $updatesDir, $logsDir | Out-Null

& $sqlite $db @"
PRAGMA journal_mode=WAL;
CREATE TABLE IF NOT EXISTS pending_actions (
  id TEXT PRIMARY KEY,
  operation TEXT NOT NULL,
  payload TEXT NOT NULL,
  status TEXT NOT NULL,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
);
CREATE TABLE IF NOT EXISTS offline_sales (
  id TEXT PRIMARY KEY,
  client_request_id TEXT NOT NULL,
  cash_session_id TEXT NOT NULL,
  total_sold REAL NOT NULL,
  status TEXT NOT NULL
);
INSERT OR REPLACE INTO pending_actions VALUES (
  'bench-action-1',
  'sales.create',
  '{"clientRequestId":"bench-sale-1","originCashSessionId":"bench-cash-1"}',
  'pending',
  1800000000000,
  1800000000000
);
INSERT OR REPLACE INTO offline_sales VALUES (
  'bench-sale-1',
  'bench-sale-1',
  'bench-cash-1',
  123.45,
  'pending'
);
PRAGMA wal_checkpoint(TRUNCATE);
"@ | Out-Null

$pendingBefore = (& $sqlite $db "select count(*) from pending_actions where status='pending';").Trim()
$saleIdBefore = (& $sqlite $db "select client_request_id || '|' || cash_session_id || '|' || total_sold from offline_sales where id='bench-sale-1';").Trim()
Set-Content -LiteralPath $wal -Value 'uat wal sentinel' -NoNewline
Set-Content -LiteralPath $shm -Value 'uat shm sentinel' -NoNewline

$before = [ordered]@{
  db = Sha256 $db
  wal = Sha256 $wal
  shm = Sha256 $shm
  pending = $pendingBefore
  saleId = $saleIdBefore
}

foreach ($build in @(201001, 201002)) {
  $buildDir = Join-Path $updatesDir $build
  New-Item -ItemType Directory -Force -Path $buildDir | Out-Null
  $part = Join-Path $buildDir "FullPOS-UAT-$build.exe.part"
  $ready = Join-Path $buildDir "FullPOS-UAT-$build.exe.ready"

  Set-Content -LiteralPath $part -Value "fake uat package $build" -NoNewline
  $packageHash = Sha256 $part

  if ($build -eq 201001) {
    $interrupted = Join-Path $buildDir 'interrupted-download.part'
    Set-Content -LiteralPath $interrupted -Value 'partial bytes only' -NoNewline
    $interruptedHash = Sha256 $interrupted
  }

  Move-Item -LiteralPath $part -Destination $ready
  $state = [ordered]@{
    targetBuild = $build
    targetVersion = "uat.$build"
    state = 'READY_TO_INSTALL'
    artifactRelativePath = "$build/FullPOS-UAT-$build.exe.ready"
    bytesDownloaded = (Get-Item -LiteralPath $ready).Length
    fileSizeExpected = (Get-Item -LiteralPath $ready).Length
    sha256Expected = $packageHash
    signatureStatus = 'NotSigned'
    signatureAcceptedBy = 'UatUnsignedPolicy'
    attempts = 1
    lastUpdateResult = 'READY_TO_INSTALL'
    createdAt = (Get-Date).ToUniversalTime().ToString('o')
    updatedAt = (Get-Date).ToUniversalTime().ToString('o')
  }
  $state | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $buildDir 'update_state.json') -Encoding UTF8
}

$after = [ordered]@{
  db = Sha256 $db
  wal = Sha256 $wal
  shm = Sha256 $shm
  pending = $before.pending
  saleId = $before.saleId
}

if ($before.db -ne $after.db) { throw 'SQLite DB hash changed during updater bench.' }
if ($before.wal -ne $after.wal) { throw 'SQLite WAL hash changed during updater bench.' }
if ($before.shm -ne $after.shm) { throw 'SQLite SHM hash changed during updater bench.' }
if ($before.pending -ne '1' -or $after.pending -ne '1') { throw 'Pending action was not preserved.' }
if ($before.saleId -ne $after.saleId) { throw 'Offline sale identity changed.' }

[ordered]@{
  status = 'PASS'
  benchRoot = $BenchRoot
  appRoot = $appRoot
  sqlite = $db
  pendingActions = [int]$after.pending
  offlineSaleIdentity = $after.saleId
  buildsPrepared = @(201001, 201002)
  interruptedPartPreserved = (Test-Path -LiteralPath (Join-Path $updatesDir '201001\interrupted-download.part'))
  readyArtifacts = @(
    (Join-Path $updatesDir '201001\FullPOS-UAT-201001.exe.ready'),
    (Join-Path $updatesDir '201002\FullPOS-UAT-201002.exe.ready')
  )
} | ConvertTo-Json -Depth 5
