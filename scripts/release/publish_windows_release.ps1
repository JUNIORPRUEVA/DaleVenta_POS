param(
  [Parameter(Mandatory = $true)]
  [string]$ReleaseId,
  [string]$ApiBaseUrl = $env:FULLPOS_RELEASE_API_BASE_URL,
  [string]$ApiToken = $env:FULLPOS_RELEASE_API_TOKEN,
  [switch]$ConfirmPublish,
  [switch]$DryRun,
  [switch]$RetentionDryRun,
  [switch]$AllowUnsignedUat
)

$ErrorActionPreference = 'Stop'

function Write-Step {
  param([string]$Message)
  Write-Host "[fullpos-release-publish] $Message"
}

function Invoke-JsonApi {
  param(
    [ValidateSet('GET','POST')]
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

function Assert-DownloadedArtifact {
  param(
    [string]$DownloadUrl,
    [string]$ExpectedSha256,
    [long]$ExpectedSize
  )
  $temp = Join-Path ([IO.Path]::GetTempPath()) ("fullpos-publish-" + [Guid]::NewGuid() + ".exe")
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
    $signature = Get-AuthenticodeSignature -LiteralPath $temp
    if ($signature.Status -ne 'Valid' -and -not $AllowUnsignedUat) {
      throw 'Downloaded installer is not Authenticode-valid. Use -AllowUnsignedUat only for explicit local/UAT exception.'
    }
    return [string]$signature.Status
  } finally {
    Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue
  }
}

if ([string]::IsNullOrWhiteSpace($ApiBaseUrl)) { throw 'ApiBaseUrl is required.' }
if ([string]::IsNullOrWhiteSpace($ApiToken)) { throw 'ApiToken is required; it will not be printed.' }
if (-not $ConfirmPublish -and -not $DryRun) {
  throw 'Publishing requires explicit -ConfirmPublish. Run prepare_windows_release.ps1 first; publish is intentionally separate.'
}

$base = $ApiBaseUrl.TrimEnd('/')
$release = Invoke-JsonApi -Method GET -Url "$base/api/app-updates/releases/$ReleaseId" -ApiToken $ApiToken

if ($release.platform -ne 'windows' -or $release.channel -ne 'stable') {
  throw "Refusing to publish retention release outside windows/stable. platform=$($release.platform) channel=$($release.channel)"
}
if ($release.status -ne 'draft') {
  throw "Release must be draft before publish. Current status=$($release.status)"
}
if ([string]::IsNullOrWhiteSpace($release.storageKey)) {
  throw 'Release has no storageKey; safe retention requires exact storage keys.'
}

Write-Step "Release: $($release.version)+$($release.buildNumber) id=$($release.id)"
Write-Step "Artifact: $($release.fileName)"
Write-Step "Storage key: $($release.storageKey)"

$signatureStatus = Assert-DownloadedArtifact `
  -DownloadUrl $release.downloadUrl `
  -ExpectedSha256 $release.sha256 `
  -ExpectedSize ([long]$release.fileSize)

Write-Step "Downloaded artifact verified. Signature=$signatureStatus"

if ($DryRun) {
  $checkBuild = [Math]::Max(0, [int]$release.buildNumber - 1)
  $currentCheckUrl = "$base/api/app-updates/check?platform=windows&channel=stable&version=$([Uri]::EscapeDataString($release.version))&build=$($release.buildNumber)"
  $previousCheckUrl = "$base/api/app-updates/check?platform=windows&channel=stable&version=$([Uri]::EscapeDataString($release.version))&build=$checkBuild"
  [pscustomobject]@{
    DRY_RUN = 'YES'
    wouldPublish = 'NO'
    wouldMutateRelease = 'NO'
    wouldRunRetention = 'NO'
    releaseId = $release.id
    version = $release.version
    buildNumber = $release.buildNumber
    status = $release.status
    fileName = $release.fileName
    fileSize = $release.fileSize
    sha256 = $release.sha256
    signatureStatus = $signatureStatus
    storageKey = $release.storageKey
    downloadUrl = $release.downloadUrl
    publishPayload = (@{ retentionDryRun = [bool]$RetentionDryRun } | ConvertTo-Json -Depth 4)
    endpointPreviousBuildCheckUrl = $previousCheckUrl
    endpointCurrentBuildCheckUrl = $currentCheckUrl
    retentionModeIfPublished = $(if ($RetentionDryRun) { 'DRY_RUN' } else { 'LIVE_AFTER_SUCCESSFUL_PUBLISH' })
  } | Format-List
  return
}

$published = Invoke-JsonApi `
  -Method POST `
  -Url "$base/api/app-updates/releases/$ReleaseId/publish" `
  -ApiToken $ApiToken `
  -Body @{ retentionDryRun = [bool]$RetentionDryRun }

$previousBuild = [Math]::Max(0, [int]$published.buildNumber - 1)
$checkPrevious = Invoke-JsonApi `
  -Method GET `
  -Url "$base/api/app-updates/check?platform=windows&channel=stable&version=$([Uri]::EscapeDataString($published.version))&build=$previousBuild" `
  -ApiToken ''
$checkCurrent = Invoke-JsonApi `
  -Method GET `
  -Url "$base/api/app-updates/check?platform=windows&channel=stable&version=$([Uri]::EscapeDataString($published.version))&build=$($published.buildNumber)" `
  -ApiToken ''

if (-not $checkPrevious.updateAvailable -or [int]$checkPrevious.buildNumber -ne [int]$published.buildNumber) {
  throw 'Update check did not return the newly published release for previous builds.'
}
if ($checkCurrent.updateAvailable) {
  throw 'Update check should be up-to-date for the newly published build.'
}

[pscustomobject]@{
  PUBLISHED = 'YES'
  releaseId = $published.id
  version = $published.version
  buildNumber = $published.buildNumber
  status = $published.status
  endpointPreviousBuildOffers = $checkPrevious.buildNumber
  endpointCurrentBuildUpToDate = -not $checkCurrent.updateAvailable
  retentionStatus = $published.retention.status
  retentionDryRun = $published.retention.dryRun
  keep = $published.retention.keep
  candidates = $published.retention.candidates
} | Format-List
