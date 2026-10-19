. "$PSScriptRoot\_common.ps1"

Assert-IsolatedEnvironment
Write-IsolatedBanner

$identity = docker exec $ContainerName psql -U $DbUser -d $DbName -tAc "SELECT current_database();"
if ($identity.Trim() -ne $DbName) {
  throw "Unexpected database identity: $identity"
}

$probeId = [guid]::NewGuid().ToString()
docker exec $ContainerName psql -U $DbUser -d $DbName -v ON_ERROR_STOP=1 -c "CREATE TABLE IF NOT EXISTS isolated_uat_probe (id text PRIMARY KEY, front text NOT NULL, created_at timestamptz NOT NULL DEFAULT now());" | Out-Null
docker exec $ContainerName psql -U $DbUser -d $DbName -v ON_ERROR_STOP=1 -c "INSERT INTO isolated_uat_probe (id, front) VALUES ('$probeId', '$FrontName');" | Out-Null
$count = docker exec $ContainerName psql -U $DbUser -d $DbName -tAc "SELECT count(*) FROM isolated_uat_probe WHERE id = '$probeId' AND front = '$FrontName';"
if ($count.Trim() -ne "1") {
  throw "Controlled write/read probe failed."
}
Write-Host "Controlled write/read probe passed: $probeId"
