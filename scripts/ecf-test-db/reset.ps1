param()
. "$PSScriptRoot\_test-common.ps1"

# Rebuilds the EPHEMERAL test schema from prisma/migrations. Destructive BY DESIGN
# and safe only because Assert-TestEnvironment hard-blocks anything that is not the
# exact disposable test container/port/volume. The historical UAT is never touched.
Assert-TestEnvironment
Set-Location $ApiRoot

Write-Host "Rebuilding the EPHEMERAL test schema from prisma/migrations (disposable data only)..."
# --skip-seed: the automated suites create their own fixtures; the seed needs
# ADMIN_PASSWORD and is not part of the ephemeral test environment contract.
& npx prisma migrate reset --force --skip-generate --skip-seed
if ($LASTEXITCODE -ne 0) { throw "prisma migrate reset failed on the ephemeral test database." }

& npx prisma migrate status
Write-Host "EPHEMERAL SCHEMA REBUILT."
