. "$PSScriptRoot\_common.ps1"

Assert-UatEnvironment
Assert-DockerAvailable
Write-UatBanner

if ($env:UAT_DB_NAME -ne "daleventa_uat_local") {
  throw "Refusing reset: unexpected UAT database name."
}

Push-Location $RepoRoot
try {
  docker compose -f $ComposeFile --env-file $UatEnvFile down -v
  docker compose -f $ComposeFile --env-file $UatEnvFile up -d daleventas_uat_postgres
  Write-Host "Waiting for fresh UAT PostgreSQL..."
  for ($i = 0; $i -lt 40; $i++) {
    $status = docker inspect --format "{{.State.Health.Status}}" daleventas_uat_postgres 2>$null
    if ($status -eq "healthy") { break }
    Start-Sleep -Seconds 2
  }
  if ((docker inspect --format "{{.State.Health.Status}}" daleventas_uat_postgres) -ne "healthy") {
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
