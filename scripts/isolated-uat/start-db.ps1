. "$PSScriptRoot\_common.ps1"

Assert-IsolatedEnvironment
Assert-DockerAvailable
Assert-PortNotUsedByOtherContainer -Port $DbPort -ExpectedContainer $ContainerName
Write-IsolatedBanner

Invoke-IsolatedCompose up -d postgres
Write-Host "Waiting for PostgreSQL..."
for ($i = 0; $i -lt 40; $i++) {
  $status = docker inspect --format "{{.State.Health.Status}}" $ContainerName 2>$null
  if ($status -eq "healthy") { break }
  Start-Sleep -Seconds 2
}
if ((docker inspect --format "{{.State.Health.Status}}" $ContainerName) -ne "healthy") {
  throw "PostgreSQL did not become healthy."
}
