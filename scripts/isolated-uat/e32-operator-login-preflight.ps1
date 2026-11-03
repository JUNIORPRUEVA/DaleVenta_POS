[CmdletBinding()]
param([switch]$CreateSyntheticAdmin, [switch]$ConfigureEcfSandbox, [switch]$SyntheticTenantPreflight, [switch]$ExecuteAuthorizedFirstE32)
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\_common.ps1"
Assert-IsolatedEnvironment
if ($CreateSyntheticAdmin -and $ConfigureEcfSandbox) { throw 'SEPARATE_ACCOUNT_AND_FISCAL_CONFIGURATION_REQUIRED' }
if ($ExecuteAuthorizedFirstE32 -and ($CreateSyntheticAdmin -or $ConfigureEcfSandbox)) { throw 'SEPARATE_EMISSION_AND_CONFIGURATION_REQUIRED' }
if ((git branch --show-current).Trim() -ne 'feature/ecf-alanube' -or (Split-Path $RepoRoot -Leaf) -ne 'FULLPOS-ECF-ALANUBE') { throw 'UAT_WORKTREE_REQUIRED' }
if ((docker port $ContainerName 5432/tcp).Trim() -ne '127.0.0.1:56550') { throw 'UAT_BINDING_REQUIRED' }
if ((docker exec $ContainerName psql -U $DbUser -d $DbName -tAc 'SELECT current_database();').Trim() -ne 'fullpos_alanube_uat') { throw 'UAT_DATABASE_REQUIRED' }
if (-not (Test-Path -LiteralPath (Join-Path $RepoRoot 'apps/api/dist/ecf/sandbox/e32-sandbox.cli.js'))) { throw 'BUILD_REQUIRED' }
$env:ALANUBE_ENABLE_REAL_CALLS = 'false'
$env:ECF_EMISSION_ENABLED = 'false'
$env:ECF_ALANUBE_AUTH_TESTS_ENABLED = 'false'
$env:ALANUBE_HTTP_TRANSPORT_ENABLED = 'false'
Remove-Item Env:ALANUBE_SANDBOX_TOKEN -ErrorAction SilentlyContinue
$reportPath = Join-Path $RepoRoot 'artifacts/e32-first-trial/operator-preflight.json'
$safeReport = [ordered]@{ startedAtUtc = [DateTime]::UtcNow.ToString('o'); status = 'WAITING_FOR_OPERATOR'; localLoginAttempts = 0; externalRequests = 0; fiscalPosts = 0; httpStatus = $null; preflight = $null }
# This file contains only status and the CLI's allowlisted checks/hashes.
function Save-SafeReport { $safeReport | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $reportPath -Encoding UTF8 }
Save-SafeReport
Add-Type -AssemblyName System.Net.Http
$login = $null; $response = $null; $content = $null; $passwordPointer = [IntPtr]::Zero
$confirmPointer = [IntPtr]::Zero
$handler = [System.Net.Http.HttpClientHandler]::new()
$handler.AllowAutoRedirect = $false; $handler.UseProxy = $false; $handler.UseCookies = $false
$client = [System.Net.Http.HttpClient]::new($handler)
$client.Timeout = [TimeSpan]::FromSeconds(15)
try {
  Write-Host 'FULLPOS: LOGIN ADMIN UAT LOCAL. No enviar credenciales al chat.'
  if ($CreateSyntheticAdmin) {
    $identifier = 'alanube.admin@fullpos.local'
    Write-Host ('Crear ADMIN sintetico UAT: ' + $identifier + '. Defina una nueva contrasena de 8 caracteres o mas.')
  } elseif ($ConfigureEcfSandbox -or $SyntheticTenantPreflight -or $ExecuteAuthorizedFirstE32) {
    $identifier = 'alanube.admin@fullpos.local'
    Write-Host ('Validar exclusivamente tenant sintetico con usuario: ' + $identifier)
  } else {
    $identifier = Read-Host 'Identificador ADMIN UAT (Enter usa el configurado localmente)'
    if ([string]::IsNullOrWhiteSpace($identifier)) { $identifier = $env:UAT_ADMIN_EMAIL }
  }
  if ([string]::IsNullOrWhiteSpace($identifier)) { throw 'IDENTIFIER_REQUIRED' }
  $password = Read-Host 'Contrasena UAT (entrada oculta)' -AsSecureString
  $passwordPointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($password)
  if ($CreateSyntheticAdmin) {
    $confirmPassword = Read-Host 'Confirme la nueva contrasena (entrada oculta)' -AsSecureString
    $confirmPointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($confirmPassword)
    if ([Runtime.InteropServices.Marshal]::PtrToStringBSTR($passwordPointer) -cne [Runtime.InteropServices.Marshal]::PtrToStringBSTR($confirmPointer)) { throw 'PASSWORD_CONFIRMATION_MISMATCH' }
    $OutputEncoding = [Text.UTF8Encoding]::new($false)
    $provisionInput = @{password=[Runtime.InteropServices.Marshal]::PtrToStringBSTR($passwordPointer)} | ConvertTo-Json -Compress
    Push-Location $RepoRoot
    try { $provisionText = $provisionInput | node ./scripts/isolated-uat/create-synthetic-admin.cjs; $provisionExit = $LASTEXITCODE } finally { Pop-Location }
    $provisionValue = ($provisionText -join "`n") | ConvertFrom-Json
    $safeReport.provision = $provisionValue
    if ($provisionExit -ne 0 -or $provisionValue.status -ne 'SYNTHETIC_ADMIN_CREATED') { $safeReport.status='ADMIN_PROVISION_BLOCKED'; throw 'ADMIN_PROVISION_BLOCKED' }
    Remove-Variable provisionInput,provisionText -ErrorAction SilentlyContinue
  }
  $loginBody = @{ identifier = $identifier; password = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($passwordPointer) } | ConvertTo-Json -Compress
  $content = [System.Net.Http.StringContent]::new($loginBody, [Text.Encoding]::UTF8, 'application/json')
  $safeReport.localLoginAttempts = 1; $safeReport.status = 'LOCAL_LOGIN_IN_PROGRESS'; Save-SafeReport
  $response = $client.PostAsync('http://127.0.0.1:4002/auth/login', $content).GetAwaiter().GetResult()
  $safeReport.httpStatus = [int]$response.StatusCode
  if ($safeReport.httpStatus -notin @(200,201)) { $safeReport.status = 'LOCAL_LOGIN_REJECTED'; throw 'LOCAL_LOGIN_REJECTED' }
  $login = $response.Content.ReadAsStringAsync().GetAwaiter().GetResult() | ConvertFrom-Json
  if (-not $login.accessToken -or $login.user.role -ne 'ADMIN' -or -not $login.user.companyId) { $safeReport.status = 'ADMIN_TENANT_REQUIRED'; throw 'ADMIN_TENANT_REQUIRED' }
  $env:ECF_SANDBOX_OPERATOR_JWT = $login.accessToken
  if ($ConfigureEcfSandbox) {
    $safeReport.status = 'CHECKING_CONFIG_BACKUP'; Save-SafeReport
    # The authenticated API decides company/permissions; no companyId in PATCH.
    $backupProof = Get-Content (Join-Path $RepoRoot 'artifacts/e32-first-trial/tenant-config-backup.json') -Raw | ConvertFrom-Json
    $backupAgeMinutes = ([DateTime]::UtcNow - [DateTime]::Parse($backupProof.verifiedAtUtc).ToUniversalTime()).TotalMinutes
    if ($backupProof.file -notmatch '^ecf_before_tenant_config_\d{8}_\d{6}\.dump$' -or -not $backupProof.fullArchiveReadVerified -or
        $backupAgeMinutes -lt 0 -or $backupAgeMinutes -gt 60) { throw 'RECENT_CONFIG_BACKUP_REQUIRED' }
    $backupPath = Join-Path $RepoRoot ('artifacts/uat-backups/' + $backupProof.file)
    $backupStream = [System.IO.File]::OpenRead($backupPath)
    $backupHasher = [System.Security.Cryptography.SHA256]::Create()
    try {
      $backupHash = ([BitConverter]::ToString($backupHasher.ComputeHash($backupStream))).Replace('-','')
      if ($backupStream.Length -ne $backupProof.bytes -or $backupHash -ne $backupProof.sha256) { throw 'CONFIG_BACKUP_INTEGRITY_REQUIRED' }
    } finally { $backupStream.Dispose(); $backupHasher.Dispose() }
    $safeReport.status = 'VERIFYING_AUTHENTICATED_TENANT'; Save-SafeReport
    $meRequest = [System.Net.Http.HttpRequestMessage]::new([System.Net.Http.HttpMethod]::Get,'http://127.0.0.1:4002/auth/me')
    $meRequest.Headers.Authorization = [System.Net.Http.Headers.AuthenticationHeaderValue]::new('Bearer',$login.accessToken)
    try {
      $meResponse = $client.SendAsync($meRequest).GetAwaiter().GetResult()
      if ([int]$meResponse.StatusCode -ne 200) { throw 'VALID_SESSION_REQUIRED' }
      $me = $meResponse.Content.ReadAsStringAsync().GetAwaiter().GetResult() | ConvertFrom-Json
      if ($me.role -ne 'ADMIN' -or $me.companyId -ne $login.user.companyId -or $me.company.slug -ne 'fullpos-alanube-uat-access' -or $me.company.name -ne 'SYNTHETIC Fullpos Alanube UAT Access') { throw 'SYNTHETIC_AUTHENTICATED_TENANT_REQUIRED' }
    } finally { if ($meResponse) { $meResponse.Dispose() }; $meRequest.Dispose() }
    $configNotes = @{ preparation='CONFIGURED_ADDRESS_PENDING'; providerCompanyTarget='TOKEN_PRIMARY'; remoteCompanyId='01M3T6Y4R9BH35XGJ5PP12KV0T'; testRnc='132109122'; providerName='FULLTECH'; evidenceSha256='dcf9103473cc527d696f96f8c91fa9faf4d2bdccd93a84e7820015f26a537364'; certificationClaim='NONE' } | ConvertTo-Json -Compress
    $safeReport.status = 'APPLYING_AUTHENTICATED_CONFIGURATION'; Save-SafeReport
    $configBody = @{enabled=$false;provider='ALANUBE';environment='SANDBOX';alanubeCompanyId=$null;credentialsSecretRef='env://ALANUBE_SANDBOX_TOKEN';allowedTypes=@('E32');notes=$configNotes} | ConvertTo-Json -Compress
    $configRequest = [System.Net.Http.HttpRequestMessage]::new([System.Net.Http.HttpMethod]::new('PATCH'),'http://127.0.0.1:4002/ecf/config')
    $configRequest.Headers.Authorization = [System.Net.Http.Headers.AuthenticationHeaderValue]::new('Bearer',$login.accessToken)
    $configRequest.Content = [System.Net.Http.StringContent]::new($configBody,[Text.Encoding]::UTF8,'application/json')
    try {
      $configResponse = $client.SendAsync($configRequest).GetAwaiter().GetResult()
      if ([int]$configResponse.StatusCode -ne 200) { throw 'AUTHENTICATED_CONFIG_UPDATE_REJECTED' }
      $configValue = $configResponse.Content.ReadAsStringAsync().GetAwaiter().GetResult() | ConvertFrom-Json
      if ($configValue.companyId -ne $me.companyId -or $configValue.enabled -or $configValue.productionEnabled -or $configValue.environment -ne 'SANDBOX' -or $configValue.certificationStatus -ne 'NOT_STARTED') { throw 'CONFIG_SAFETY_REVIEW_REQUIRED' }
      $safeReport.configuration = @{ status='CONFIGURED_NOT_CERTIFIED'; httpStatus=[int]$configResponse.StatusCode; enabled=$configValue.enabled; environment=$configValue.environment; productionEnabled=$configValue.productionEnabled; certificationStatus=$configValue.certificationStatus; credentialsReferenceConfigured=$configValue.secrets.credentialsConfigured }
    } finally { if ($configResponse) { $configResponse.Dispose() }; $configRequest.Dispose() }
  }
  Push-Location $RepoRoot
  try {
    # No emission/configuration options. JwtStrategy revalidates session and license.
    $preflightText = node ./apps/api/dist/ecf/sandbox/e32-sandbox.cli.js --actor $login.user.id
    $preflightValue = ($preflightText -join "`n") | ConvertFrom-Json
    $safeReport.preflight = [ordered]@{
      result = $preflightValue.result; checks = $preflightValue.checks; blockers = $preflightValue.blockers
      manifestFingerprint = $preflightValue.manifestFingerprint; payloadFingerprint = $preflightValue.payloadFingerprint
      authorizationGranted = $preflightValue.authorizationGranted; authenticatedRequests = $preflightValue.authenticatedRequests
    }
    $safeReport.status = 'PREFLIGHT_COMPLETED'
    Save-SafeReport
    if ($ExecuteAuthorizedFirstE32) {
      if ($preflightValue.result -ne 'READY_FOR_AUTHORIZATION' -or
          $preflightValue.manifestFingerprint -ne '1ed4a6946f379360a7196b3e6acf7825fc070a6120c9a156da477e9910544990' -or
          $preflightValue.payloadFingerprint -ne '37f68474e054ed217655cc409718e6b85cf32f0fcf63560a032ff119a81d4f0d') { throw 'EXACT_USER_AUTHORIZED_PAYLOAD_REQUIRED' }
      $grantPath = Join-Path $RepoRoot 'artifacts/e32-first-trial/single-emission-authorization.json'
      $grantJson = @{ manifestFingerprint=$preflightValue.manifestFingerprint; actorId=$login.user.id; expiresAt=[DateTime]::UtcNow.AddMinutes(15).ToString('o'); maxPosts=1; maxQueries=1;
        approvalReference='user-explicit-consent:2026-10-14:959afb04-b593-4282-b40d-212ed800b507:E320009805001' } | ConvertTo-Json
      [System.IO.File]::WriteAllText($grantPath,$grantJson,[Text.UTF8Encoding]::new($false))
      # Only this separately selected, specifically authorized mode can dispatch.
      $safeReport.externalRequests=$null; $safeReport.fiscalPosts=$null
      $safeReport.status='AUTHORIZED_DISPATCH_STARTED_NO_RETRY'; Save-SafeReport
      & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'e32-sandbox-send-once.ps1') -ActorId $login.user.id -Manifest (Join-Path $RepoRoot 'artifacts/e32-first-trial/manifest.json') -AuthorizationFile $grantPath -ExecuteOnce
      $safeReport.dispatchProcessExitCode=$LASTEXITCODE
      $safeReport.status='AUTHORIZED_DISPATCH_STOPPED_NO_RETRY'
    }
  } finally { Pop-Location }
} catch {
  $safeReport.failureType = $_.Exception.GetType().Name
  $safeReport.failureLine = $_.InvocationInfo.ScriptLineNumber
  if ($safeReport.status -in @('WAITING_FOR_OPERATOR','LOCAL_LOGIN_IN_PROGRESS')) { $safeReport.status = 'LOCAL_LOGIN_OR_PREFLIGHT_FAILED' }
  Write-Host 'BLOCKED: revisar el informe seguro; no imprimir excepcion ni respuesta de login.'
} finally {
  Remove-Item Env:ECF_SANDBOX_OPERATOR_JWT -ErrorAction SilentlyContinue
  if ($passwordPointer -ne [IntPtr]::Zero) { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($passwordPointer) }
  if ($confirmPointer -ne [IntPtr]::Zero) { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($confirmPointer) }
  if ($content) { $content.Dispose() }; if ($response) { $response.Dispose() }
  $client.Dispose(); $handler.Dispose()
  Remove-Variable login,loginBody,password,confirmPassword,identifier,preflightText,provisionInput,provisionText -ErrorAction SilentlyContinue
  $safeReport.completedAtUtc = [DateTime]::UtcNow.ToString('o')
  Save-SafeReport
}
if ($ExecuteAuthorizedFirstE32) {
  Write-Host ('Resultado: ' + $safeReport.status + '. JWT eliminado del entorno. Revisar evidencia antes de cualquier otra accion. NO REPETIR EL ENVIO.')
} else {
  Write-Host ('Resultado: ' + $safeReport.status + '. JWT eliminado del entorno. No se emitio ningun documento.')
}
