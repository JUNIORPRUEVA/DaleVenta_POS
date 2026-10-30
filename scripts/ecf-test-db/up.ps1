param()
. "$PSScriptRoot\_test-common.ps1"

Assert-TestEnvironment
Assert-TestDockerAvailable
Write-TestBanner

$existing = (& docker ps -a --format "{{.Names}}" | Where-Object { $_ -eq $TestContainerName })
if ($existing) {
  Write-Host "Ephemeral container already exists; ensuring it is running."
} else {
  Write-Host "Creating ephemeral test database container..."
}

# Do not pipe compose output: piping keeps the detached process attached to logs.
Invoke-TestCompose up -d

$deadline = (Get-Date).AddSeconds(90)
do {
  Start-Sleep -Seconds 2
  $status = (& docker inspect --format "{{.State.Health.Status}}" $TestContainerName 2>$null)
} while ($status -ne "healthy" -and (Get-Date) -lt $deadline)

if ($status -ne "healthy") { throw "Ephemeral test container did not become healthy." }
$portMap = (& docker port $TestContainerName 5432/tcp).Trim()
if ($portMap -ne "127.0.0.1:$TestDbPort") { throw "Unexpected port mapping: $portMap" }
Write-Host "READY: ephemeral test database healthy at $portMap"
