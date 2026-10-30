param()
. "$PSScriptRoot\_test-common.ps1"

Assert-TestEnvironment
Set-Location $ApiRoot

Write-Host "Applying Prisma migrations to the EPHEMERAL test database only..."
& npx prisma migrate deploy
if ($LASTEXITCODE -ne 0) { throw "prisma migrate deploy failed on the ephemeral test database." }

& npx prisma migrate status
Write-Host "MIGRATIONS APPLIED (ephemeral test database)."
