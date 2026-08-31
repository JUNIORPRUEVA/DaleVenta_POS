. "$PSScriptRoot\_common.ps1"

Assert-UatEnvironment
Write-UatBanner

Push-Location $ApiRoot
try {
  npm run start:dev
} finally {
  Pop-Location
}
