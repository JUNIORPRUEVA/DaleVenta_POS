. "$PSScriptRoot\_common.ps1"

Assert-IsolatedEnvironment
Write-IsolatedBanner
Push-Location $ApiRoot
try {
  npx prisma migrate deploy
} finally {
  Pop-Location
}
