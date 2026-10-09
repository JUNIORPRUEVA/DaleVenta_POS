param(
  [string]$ApiBaseUrl = $env:FULLPOS_RELEASE_API_BASE_URL,
  [string]$ApiToken = $env:FULLPOS_RELEASE_API_TOKEN,
  [string]$PublicBaseUrl = $env:FULLPOS_RELEASE_PUBLIC_BASE_URL,
  [ValidateSet('Local','AwsCli')]
  [string]$StorageMode = $(if ($env:FULLPOS_RELEASE_STORAGE_MODE) { $env:FULLPOS_RELEASE_STORAGE_MODE } else { 'Local' }),
  [string]$StorageRoot = $env:FULLPOS_RELEASE_STORAGE_ROOT,
  [string]$AwsCli = $(if ($env:AWS_CLI) { $env:AWS_CLI } else { 'aws' }),
  [string]$S3BucketUri = $env:FULLPOS_RELEASE_S3_BUCKET_URI,
  [string]$S3EndpointUrl = $env:FULLPOS_RELEASE_S3_ENDPOINT_URL,
  [switch]$SkipBuild,
  [switch]$AllowUnsignedUat
)

$ErrorActionPreference = 'Stop'

function Write-Step {
  param([string]$Message)
  Write-Host "[fullpos-release-prepare] $Message"
}

function Get-RepoRoot {
  $scriptDir = Split-Path -Parent $PSCommandPath
  return (Resolve-Path -LiteralPath (Join-Path $scriptDir '..\..')).Path
}

function Read-PubspecVersion {
  param([string]$RepoRoot)
  $pubspec = Join-Path $RepoRoot 'apps\fulltech_app\pubspec.yaml'
  $line = Get-Content -LiteralPath $pubspec | Where-Object { $_ -match '^\s*version:\s*(\S+)\s*$' } | Select-Object -First 1
  if (-not $line -or $line -notmatch '^\s*version:\s*(\d+\.\d+\.\d+)\+([1-9][0-9]*)\s*$') {
    throw "Invalid pubspec version. Expected x.y.z+build in $pubspec"
  }
  [pscustomobject]@{
    Version = $Matches[1]
    BuildNumber = [int]$Matches[2]
    PubspecValue = "$($Matches[1])+$($Matches[2])"
  }
}

function Invoke-JsonApi {
  param(
    [ValidateSet('GET','POST','PATCH')]
    [string]$Method,
    [string]$Url,
    [object]$Body = $null,
    [string]$ApiToken
  )
  $headers = @{}
  if (-not [string]::IsNullOrWhiteSpace($ApiToken)) {
    $headers.Authorization = "Bearer $ApiToken"
  }
  $params = @{
    Method = $Method
    Uri = $Url
    Headers = $headers
  }
  if ($null -ne $Body) {
    $params.ContentType = 'application/json'
    $params.Body = ($Body | ConvertTo-Json -Depth 8)
  }
  Invoke-RestMethod @params
}

function Copy-ReleaseArtifact {
  param(
    [string]$InstallerPath,
    [string]$StorageKey,
    [string]$StorageMode,
    [string]$StorageRoot,
    [string]$AwsCli,
    [string]$S3BucketUri,
    [string]$S3EndpointUrl
  )

  if ($StorageMode -eq 'Local') {
    if ([string]::IsNullOrWhiteSpace($StorageRoot)) {
      throw 'FULLPOS_RELEASE_STORAGE_ROOT or -StorageRoot is required for Local storage mode.'
    }
    $target = Join-Path $StorageRoot $StorageKey
    if (Test-Path -LiteralPath $target) {
      throw "Refusing to overwrite existing release artifact: $target"
    }
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $target) | Out-Null
    Copy-Item -LiteralPath $InstallerPath -Destination $target -ErrorAction Stop
    return
  }

  if ([string]::IsNullOrWhiteSpace($S3BucketUri)) {
    throw 'FULLPOS_RELEASE_S3_BUCKET_URI or -S3BucketUri is required for AwsCli storage mode.'
  }
  $destination = "$($S3BucketUri.TrimEnd('/'))/$StorageKey"
  $args = @('s3', 'cp', $InstallerPath, $destination, '--no-progress')
  if (-not [string]::IsNullOrWhiteSpace($S3EndpointUrl)) {
    $args += @('--endpoint-url', $S3EndpointUrl)
  }
  & $AwsCli @args
  if ($LASTEXITCODE -ne 0) {
    throw "aws s3 cp failed with exit code $LASTEXITCODE"
  }
}

function Assert-DownloadedArtifact {
  param(
    [string]$DownloadUrl,
    [string]$ExpectedSha256,
    [long]$ExpectedSize
  )
  $temp = Join-Path ([IO.Path]::GetTempPath()) ("fullpos-release-" + [Guid]::NewGuid() + ".exe")
  try {
    Invoke-WebRequest -Uri $DownloadUrl -OutFile $temp -UseBasicParsing
    $item = Get-Item -LiteralPath $temp
    if ($item.Length -ne $ExpectedSize) {
      throw "Downloaded artifact size mismatch. expected=$ExpectedSize actual=$($item.Length)"
    }
    $hash = (Get-FileHash -LiteralPath $temp -Algorithm SHA256).Hash.ToUpperInvariant()
    if ($hash -ne $ExpectedSha256.ToUpperInvariant()) {
      throw "Downloaded artifact SHA256 mismatch."
    }
  } finally {
    Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue
  }
}

if ([string]::IsNullOrWhiteSpace($ApiBaseUrl)) { throw 'ApiBaseUrl is required.' }
if ([string]::IsNullOrWhiteSpace($ApiToken)) { throw 'ApiToken is required; it will not be printed.' }
if ([string]::IsNullOrWhiteSpace($PublicBaseUrl)) { throw 'PublicBaseUrl is required.' }

$repoRoot = Get-RepoRoot
$version = Read-PubspecVersion -RepoRoot $repoRoot
$commitSha = (& git -C $repoRoot rev-parse HEAD).Trim()
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($commitSha)) {
  throw 'Unable to resolve git commit SHA.'
}

if (-not $SkipBuild) {
  & (Join-Path $repoRoot 'scripts\build\build_windows_release.ps1')
  if ($LASTEXITCODE -ne 0) {
    throw "build_windows_release.ps1 failed with exit code $LASTEXITCODE"
  }
}

$fileName = "FullPOS-Setup-$($version.Version)-$($version.BuildNumber).exe"
$installerPath = Join-Path $repoRoot "installer\output\$fileName"
if (-not (Test-Path -LiteralPath $installerPath)) {
  throw "Installer not found: $installerPath"
}

$item = Get-Item -LiteralPath $installerPath
$sha256 = (Get-FileHash -LiteralPath $installerPath -Algorithm SHA256).Hash.ToUpperInvariant()
$signature = Get-AuthenticodeSignature -LiteralPath $installerPath
$signed = $signature.Status -eq 'Valid'
if (-not $signed -and -not $AllowUnsignedUat) {
  throw 'Installer is not Authenticode-valid. Use -AllowUnsignedUat only for explicit local/UAT exception.'
}

$storageKey = "releases/windows/stable/$($version.Version)-$($version.BuildNumber)/$fileName"
$downloadUrl = "$($PublicBaseUrl.TrimEnd('/'))/$storageKey"

Write-Step "Version: $($version.PubspecValue)"
Write-Step "Commit: $commitSha"
Write-Step "Installer: $fileName"
Write-Step "Size: $($item.Length)"
Write-Step "SHA256: $sha256"
Write-Step "Signature: $($signature.Status)"
Write-Step "Storage key: $storageKey"

Copy-ReleaseArtifact `
  -InstallerPath $installerPath `
  -StorageKey $storageKey `
  -StorageMode $StorageMode `
  -StorageRoot $StorageRoot `
  -AwsCli $AwsCli `
  -S3BucketUri $S3BucketUri `
  -S3EndpointUrl $S3EndpointUrl

Assert-DownloadedArtifact -DownloadUrl $downloadUrl -ExpectedSha256 $sha256 -ExpectedSize $item.Length

$release = Invoke-JsonApi `
  -Method POST `
  -Url "$($ApiBaseUrl.TrimEnd('/'))/api/app-updates/releases" `
  -ApiToken $ApiToken `
  -Body @{
    platform = 'windows'
    channel = 'stable'
    version = $version.Version
    buildNumber = $version.BuildNumber
    fileName = $fileName
    fileSize = $item.Length
    sha256 = $sha256
    downloadUrl = $downloadUrl
    storageKey = $storageKey
    releaseNotes = @()
    commitSha = $commitSha
    signed = $signed
  }

[pscustomobject]@{
  READY_TO_PUBLISH = 'YES'
  releaseId = $release.id
  version = $version.Version
  buildNumber = $version.BuildNumber
  fileName = $fileName
  size = $item.Length
  sha256 = $sha256
  signatureStatus = [string]$signature.Status
  signed = $signed
  storageKey = $storageKey
  downloadUrl = $downloadUrl
  status = $release.status
} | Format-List
