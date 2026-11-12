$ErrorActionPreference = 'Stop'
$api = 'http://127.0.0.1:4004'
$stamp = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
$email = "qa.f3.$stamp@example.com"
$out = [ordered]@{}

function J($o) { $o | ConvertTo-Json -Depth 8 -Compress }

# 1) Registro
$payload = @{
  commercialName = "QA Fase3 $stamp"
  firstName      = 'Ana Maria'
  email          = $email
  password       = 'QaFase3!2026'
  confirmPassword= 'QaFase3!2026'
  phone          = '8095550000'
  marketingOptIn = $false
  locale         = 'es-DO'
} | ConvertTo-Json
$r = Invoke-WebRequest -Uri "$api/auth/register-business" -Method Post -ContentType 'application/json' -Body $payload -UseBasicParsing
$reg = $r.Content | ConvertFrom-Json
$out.registro_status = $r.StatusCode
$out.registro_tiene_tokens = [bool]($reg.accessToken -and $reg.refreshToken)
$out.registro_company = $reg.activeCompany.name
$out.registro_member_role = $reg.activeMembership.role
$out.registro_requires_onboarding = $reg.requiresOnboarding
$out.email = $email

$h = @{ Authorization = "Bearer $($reg.accessToken)" }

# 2) Bienvenida vacia
$w1 = (Invoke-WebRequest -Uri "$api/onboarding/welcome" -Headers $h -UseBasicParsing).Content | ConvertFrom-Json
$out.welcome_inicial = [ordered]@{
  requiresWelcome = $w1.requiresWelcome
  businessType    = $w1.businessType
  completedAt     = $w1.completedAt
  companyName     = $w1.companyName
  n_tipos         = $w1.options.businessTypes.Count
  ultimoTipo      = $w1.options.businessTypes[-1]
  n_anios         = $w1.options.businessAgeRanges.Count
  n_tamanios      = $w1.options.businessSizes.Count
}

# 3) Guardar
$body = @{ businessType='Ferretería'; businessAgeRange='1 a 3 años'; businessSize='Mediano' } | ConvertTo-Json
$w2 = (Invoke-WebRequest -Uri "$api/onboarding/welcome" -Method Put -Headers $h -ContentType 'application/json' -Body $body -UseBasicParsing).Content | ConvertFrom-Json
$out.welcome_guardado = [ordered]@{
  businessType = $w2.businessType; businessAgeRange = $w2.businessAgeRange
  businessSize = $w2.businessSize; requiresWelcome = $w2.requiresWelcome
  completedAt = $w2.completedAt
}

# 4) Repetir -> mismo registro, misma fecha
$body2 = @{ businessType='Ferretería'; businessAgeRange='4 a 10 años'; businessSize='Grande' } | ConvertTo-Json
$w3 = (Invoke-WebRequest -Uri "$api/onboarding/welcome" -Method Put -Headers $h -ContentType 'application/json' -Body $body2 -UseBasicParsing).Content | ConvertFrom-Json
$out.welcome_repetido = [ordered]@{
  ageRange = $w3.businessAgeRange; size = $w3.businessSize
  mismaFecha = ($w3.completedAt -eq $w2.completedAt)
}

# 5) Valor invalido -> 400
try {
  Invoke-WebRequest -Uri "$api/onboarding/welcome" -Method Put -Headers $h -ContentType 'application/json' -Body (@{ businessType='NoExiste'; businessAgeRange='1 a 3 años'; businessSize='Mediano' } | ConvertTo-Json) -UseBasicParsing | Out-Null
  $out.invalido_status = 200
} catch { $out.invalido_status = $_.Exception.Response.StatusCode.value__ }

# 6) Ticket de handoff
$t = (Invoke-WebRequest -Uri "$api/auth/handoff/ticket" -Method Post -Headers $h -ContentType 'application/json' -Body (@{ platform='web' } | ConvertTo-Json) -UseBasicParsing).Content | ConvertFrom-Json
$out.ticket_len = $t.ticket.Length
$out.ticket_ttl = $t.expiresIn

# 7) Canje
$ex = (Invoke-WebRequest -Uri "$api/auth/handoff/exchange" -Method Post -ContentType 'application/json' -Body (@{ ticket = $t.ticket } | ConvertTo-Json) -UseBasicParsing)
$exBody = $ex.Content | ConvertFrom-Json
$out.canje_status = $ex.StatusCode
$out.canje_tiene_tokens = [bool]($exBody.accessToken -and $exBody.refreshToken)
$out.canje_company = $exBody.activeCompany.name

# 8) Segundo canje -> 401
try {
  Invoke-WebRequest -Uri "$api/auth/handoff/exchange" -Method Post -ContentType 'application/json' -Body (@{ ticket = $t.ticket } | ConvertTo-Json) -UseBasicParsing | Out-Null
  $out.canje_replay_status = 200
} catch { $out.canje_replay_status = $_.Exception.Response.StatusCode.value__ }

# 9) Ticket invalido -> 401
try {
  Invoke-WebRequest -Uri "$api/auth/handoff/exchange" -Method Post -ContentType 'application/json' -Body (@{ ticket = 'inventado' } | ConvertTo-Json) -UseBasicParsing | Out-Null
  $out.canje_basura_status = 200
} catch { $out.canje_basura_status = $_.Exception.Response.StatusCode.value__ }

# 10) Login normal sigue funcionando
$l = (Invoke-WebRequest -Uri "$api/auth/login" -Method Post -ContentType 'application/json' -Body (@{ email=$email; password='QaFase3!2026' } | ConvertTo-Json) -UseBasicParsing).Content | ConvertFrom-Json
$out.login_ok = [bool]$l.accessToken

$out | ConvertTo-Json -Depth 8
