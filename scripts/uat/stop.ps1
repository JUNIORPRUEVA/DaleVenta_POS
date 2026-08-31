. "$PSScriptRoot\_common.ps1"

Assert-UatEnvironment
Assert-DockerAvailable
Write-UatBanner

Push-Location $RepoRoot
try {
  docker compose -f $ComposeFile --env-file $UatEnvFile down
} finally {
  Pop-Location
}
