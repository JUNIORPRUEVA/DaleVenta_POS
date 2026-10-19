. "$PSScriptRoot\_common.ps1"

Assert-UatEnvironment
Assert-DockerAvailable
Write-UatBanner

if ($env:UAT_DB_NAME -ne $UatExpectedDbName) {
  throw "Refusing reset: unexpected UAT database name."
}

Push-Location $RepoRoot
try {
  docker compose -p $UatComposeProject -f $ComposeFile --env-file $UatEnvFile down -v
  docker compose -p $UatComposeProject -f $ComposeFile --env-file $UatEnvFile up -d $UatPostgresService
  Write-Host "Waiting for fresh UAT PostgreSQL..."
  for ($i = 0; $i -lt 40; $i++) {
    $status = docker inspect --format "{{.State.Health.Status}}" $UatPostgresContainer 2>$null
    if ($status -eq "healthy") { break }
    Start-Sleep -Seconds 2
  }
  if ((docker inspect --format "{{.State.Health.Status}}" $UatPostgresContainer) -ne "healthy") {
    throw "UAT PostgreSQL did not become healthy."
  }

  Push-Location $ApiRoot
  try {
    npx ts-node --transpile-only -P tsconfig.scripts.json scripts/verify-uat-db.ts
    npx prisma migrate deploy
    npx ts-node --transpile-only -P tsconfig.scripts.json scripts/seed-uat-local.ts
  } finally {
    Pop-Location
  }
} finally {
  Pop-Location
}
