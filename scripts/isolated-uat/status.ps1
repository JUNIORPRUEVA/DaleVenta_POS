. "$PSScriptRoot\_common.ps1"

Assert-IsolatedEnvironment
Write-IsolatedBanner
docker ps --filter "name=$ContainerName" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
Get-NetTCPConnection -LocalPort ([int]$ApiPort) -ErrorAction SilentlyContinue | Select-Object LocalAddress,LocalPort,State,OwningProcess
Get-NetTCPConnection -LocalPort ([int]$DbPort) -ErrorAction SilentlyContinue | Select-Object LocalAddress,LocalPort,State,OwningProcess
