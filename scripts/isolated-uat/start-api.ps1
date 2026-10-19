. "$PSScriptRoot\_common.ps1"

Assert-IsolatedEnvironment
Assert-ApiPortAvailable
Write-IsolatedBanner
Push-Location $ApiRoot
try {
  npm run start:dev
} finally {
  Pop-Location
}
