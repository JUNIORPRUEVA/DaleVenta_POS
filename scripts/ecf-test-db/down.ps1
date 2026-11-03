param()
. "$PSScriptRoot\_test-common.ps1"

Assert-TestEnvironment

# Hard guard: only the exact ephemeral identifiers may be destroyed.
$resolvedContainer = (& docker ps -a --format "{{.Names}}" | Where-Object { $_ -eq $TestContainerName })
if (-not $resolvedContainer) {
  Write-Host "Ephemeral test container is not present. Nothing to destroy."
  exit 0
}
Assert-EphemeralContainer $resolvedContainer

$volumeExists = (& docker volume ls --format "{{.Name}}" | Where-Object { $_ -eq $TestVolumeName })
if ($volumeExists -and $volumeExists -ne $TestVolumeName) {
  throw "Refusing: resolved volume name '$volumeExists' is not the ephemeral test volume."
}

# Safety: never remove the historical container/volume.
if ($TestContainerName -eq $HistoricalContainer -or $TestVolumeName -match 'fullpos_alanube_uat_fullpos_alanube_uat_postgres_data') {
  throw "Refusing: identifiers overlap with the historical UAT."
}

Write-Host "Destroying ONLY $TestContainerName and volume $TestVolumeName ..."
Invoke-TestCompose down -v

$stillThere = (& docker ps -a --format "{{.Names}}" | Where-Object { $_ -eq $TestContainerName })
if ($stillThere) { throw "Ephemeral container still present after down." }
Write-Host "Ephemeral resources removed. Historical UAT untouched."
