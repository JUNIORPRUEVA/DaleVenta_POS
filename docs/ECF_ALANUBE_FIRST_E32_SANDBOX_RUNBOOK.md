# Primera E32 Sandbox — procedimiento de un solo uso

## Propuesta con compatibilidad específica — lista para autorización separada

La evidencia local se reevaluó con ALANUBE_DOM_E32_SANDBOX_OBSERVED_V1 sin nuevas
llamadas: integridad/correlación PASS, contrato publicado FAIL conservado,
compatibilidad específica PASS. Firma sin zona ni instante UTC inferido, trackId
no disponible y fecha fiscal literal preservada. No se modificó PostgreSQL histórico.

Artefacto revisable: artifacts/e32-first-trial/recovery-get-reconciliation-proposal.json.
IdempotencyKey e32-reconcile:539a68567e93ad13009bdde0b3a6a74bd096f35f1373ca589923f6ed5de5f2c3.
Incluye todos los hashes, identidad, antes/después y originales de cada regla.
Reproducción sin red/DB writes, con escritura exclusivamente del artefacto local:

```powershell
. ./scripts/isolated-uat/_common.ps1
Assert-IsolatedEnvironment
node scripts/isolated-uat/e32-reconciliation-dry-run.cjs --write-proposal
```

Primera ejecución SAVED_NOT_APPLIED; posteriores idénticas ALREADY_EXISTS_IDENTICAL;
contenido divergente bloquea sin sobrescribir. Sin ese flag es solo diagnóstico.
El comando no tiene --apply ni ejecuta conciliación. La idempotencia ejecutada y
probada aquí es la del diagnóstico/propuesta, no una mutación histórica.

Cambios concretos propuestos dentro de una futura transacción autenticada:

| Registro | Actual | Propuesto |
| --- | --- | --- |
| ecf_electronic_documents56cb2743-c4a0-4be4-a167-3cd5d0314f40 | UNKNOWN_RESULT, referencias null | HUMAN_REVIEW_REQUIRED; id01M4Y3DEPXXG27G8BNQGMNQ04B; e-NCF E320009805001 |
| Trial2d552e31-4d6b-4ee2-a2b7-7caaf75484dd | UNKNOWN_RESULT, consumido | Sin cambios; nunca PREPARED |
| Intentos |1SEND_TO_PROVIDER,0QUERY_PROVIDER | Añadir registro del GET ya realizado, sin repetirlo |
| Evidencia/historial/auditoría | POST histórico intacto | Append-only: hash GET+POST, actor, consentimiento, schema FAIL, compatibilidad PASS, reglas originales, ACCEPTED observado/consumo true |

Alcance exclusivo: tenant e7df7640-04ea-4000-9135-0c4451822205 y operación
959afb04-b593-4282-b40d-212ed800b507. Receipt PROVIDER_DECLARED, autenticidad no
elevada, validación publicada OFFICIAL_SCHEMA_INVALID. No fiscalSnapshot fabricado
ni DGII_ACCEPTED/PROVIDER_ACCEPTED automático. Trial, reservas y secuencia consumida
no se liberan. El mismo schema sigue fallando en las tres variantes: no ocultarlo.

Antes de escribir se requieren autorización separada, ADMIN/sesión/empresa/licencia
vigentes, backup nuevo verificado, releer y bloquear FOR UPDATE la fila exacta con
companyId; comprobar todos los hashes/huellas, estados esperados, identidad y no
conflicto de id/e-NCF. Un ejecutor transaccional deberá validar estos requisitos
sin recibir actor/tenant fingidos desde un archivo y superar pruebas de mutación
con datos sintéticos antes de aplicarse al histórico. No se implementó/ejecutó
un bypass o mutador --apply en esta tarea de preparación.

Vincular referencias antes de insertar receipt que congela correlación; actualizar
estado/log/auditoría atómicamente. Misma clave y contenido: ALREADY_RECONCILED sin
duplicados. Clave o evidencia divergente, tenant distinto, falta de permiso,
archivo alterado, identidad/estado contradictorios o nuevas variantes: abortar.

Recuperación: error antes de commit → ROLLBACK total; nunca resetear trial/reemitir.
Si ya hubo commit, conservar historial y registrar corrección compensatoria solo
con autorización nueva; no borrar receipts ni restaurar backup sobre trabajo
posterior. Verificar después: un vínculo y transición previstos, hashes/actor
coincidentes, replay sin filas nuevas, rechazo multiempresa y ausencia de nuevas
solicitudes, reemisión, UUID/fecha inventados o aceptación fiscal automática.

**GO para aprobar esta propuesta de revisión humana.** canApply=false: aún falta
autorización y validación del ejecutor persistente. Los apartados siguientes son
antecedentes; el bloqueo de compatibilidad anterior queda resuelto solo para este
perfil observado y este objetivo de revisión humana.

## GET de recuperación consumido; propuesta de conciliación sin ejecutar

El GET autorizado del id01M4Y3DEPXXG27G8BNQGMNQ04B se completó el
2026-10-14T21:16:52.201Z: HTTP200, FINISHED/ACCEPTED, secuencia consumida,
RNC132109122 y E320009805001 coincidentes. No repetir el recuperador. Mantener
recovery-get-claim.json: no borrarlo para permitir otra consulta. Validación
oficial falla en stampDate/trackId/signatureDate; detalle exacto en readiness.

Reproducir localmente sin red ni cambios DB con el comando READ_ONLY de abajo.
Ahora incluye verificación DPAPI/hash y los errores del GET recuperado. No se
requiere token Alanube ni login para esta lectura local de evidencia.

### Propuesta condicionada a revisión y autorización separada

**Estado actual: NO-GO para aplicar.** La identidad está correlacionada; el cuerpo
no cumple íntegramente el contrato. Primero resolver/documentar las diferencias,
sin normalización silenciosa ni zonas horarias inventadas. La propuesta máxima
sin verificador fiscal sería revisión humana de una observación del proveedor,
nunca DGII_ACCEPTED. Presentar una propuesta final validada antes de pedir aplicar.

Registros exactos propuestos, exclusivamente tenant e7df7640-04ea-4000-9135-0c4451822205:

- Documento56cb2743-c4a0-4be4-a167-3cd5d0314f40: UNKNOWN_RESULT →
  HUMAN_REVIEW_REQUIRED, vínculo id01M4Y3DEPXXG27G8BNQGMNQ04B y
  externalDocumentNumber E320009805001; resultado observado ACCEPTED y
  sequenceConsumed=true explícitos en auditoría. No fiscalSnapshot de aceptación.
- Trial2d552e31-4d6b-4ee2-a2b7-7caaf75484dd: **no cambiar estado ni identidad**.
  Conservar UNKNOWN_RESULT como historial de ejecución y latch consumido.
- Añadir intento QUERY_PROVIDER que documente el GET ya realizado, sin ejecutarlo
  nuevamente; unicidad empresa/operación/idempotencyKey del documento.
- Añadir receipt/evento y status log/auditoría append-only con SHA del GET,
  SHA del POST original, schema hash, actor ADMIN, referencias de autorización,
  resultado observado y validación íntegra. Si se autoriza únicamente cuarentena,
  dejar OFFICIAL_SCHEMA_INVALID y trust PROVIDER_DECLARED, sin elevar autenticidad.

Validaciones previas: nueva sesión ADMIN válida por mecanismo existente (su login
local también requerirá autorización cuando corresponda), aislamiento y backup
nuevo íntegro, hash del archivo DPAPI descifrado, coincidencia de payload/manifiesto/
operación,1POST/1GET externo,1POST/0GET previo en DB, estado y referencias locales
esperados, ausencia de otro vínculo al id/e-NCF. Fallar ante cualquier divergencia.

Transacción futura: bloqueo del documento por tenant, nueva lectura de condiciones,
clave idempotente estable tenant+operación+SHA_GET+versión, comprobar replay igual
antes de insertar. Repetición equivalente devuelve ALREADY_RECONCILED sin nuevas
filas; hash/contenido divergente devuelve conflicto. Vínculo antes de congelar
correlación mediante receipt; log y cambios atómicos. Nunca resetear el trial,
liberar/reutilizar secuencia ni emitir HTTP desde esta transacción.

Rollback: antes del commit, ROLLBACK deja todas las filas como estaban. Después
del commit no borrar/reescribir eventos ni resetear numeración; cualquier corrección
requiere otra autorización y evento compensatorio auditado, manteniendo revisión
humana y bloqueo de reemisión. No restaurar una base completa sobre trabajo posterior.

Pruebas posteriores: verificar una única transición propuesta, un único vínculo,
receipt/hash/actor coherentes, replay sin duplicados, rechazo de otro tenant o hash,
trial consumido inmutable, sin DGII_ACCEPTED ni fiscalSnapshot fabricado y sin
nuevas solicitudes de red. Los pasos son un **plan**, no código aplicado ni cambio
histórico autorizado. Ninguna conciliación se ejecutó en esta recuperación.

## Conciliación histórica: diagnóstico READ_ONLY, aplicación bloqueada

Alcance único: tenant e7df7640-04ea-4000-9135-0c4451822205,
operación959afb04-b593-4282-b40d-212ed800b507, E320009805001,
trial2d552e31-4d6b-4ee2-a2b7-7caaf75484dd,
documento56cb2743-c4a0-4be4-a167-3cd5d0314f40,
id remoto observado01M4Y3DEPXXG27G8BNQGMNQ04B.

Desde el worktree/rama exclusivos ejecutar únicamente el diagnóstico:

```powershell
. ./scripts/isolated-uat/_common.ps1
Assert-IsolatedEnvironment
node scripts/isolated-uat/e32-reconciliation-dry-run.cjs
```

No abre credenciales Alanube, no hace login ni llamadas HTTP, no tiene --apply.
Verifica loopback/puerto/base/container, tenant sintético y operación exacta;
usa REPEATABLE READ READ ONLY, parámetros SQL y timeout. Contrasta hashes,
e-NCF, intento único y evento POST. Repetirlo no cambia registros ni consume nada.
Resultado actual chainMatches=true, canApplyReconciliation=false.

**Evidencia que falta:** bytes originales para reproducir schema y comparación
de companyIdentification, o una nueva evidencia documental completa y correlacionada
con procedencia verificada. El hash de respuesta no reemplaza los bytes. No pedir
tokens/respuestas sensibles por chat ni reconstruir una respuesta rellenando nulls.
Alternativa futura: una consulta GET por el id exacto, exclusivamente tras una
nueva autorización de lectura y sesión válida; no repetir /company ni POST fiscal.
Una respuesta GET sería evidencia nueva con su propio hash/schema, no la respuesta
histórica del POST. No se realizó ninguna consulta en esta tarea.

**Procedimiento condicionado, NO ejecutado ni aprobado para aplicar:**

1. Completar la evidencia y su validación estricta; generar propuesta READ_ONLY
   con estado antes/después, hashes, actor y comprobaciones. Si falta cualquier
   dato, seguir bloqueado. Para aceptación fiscal se requiere además el mecanismo
   verificado de autenticidad; no sustituirlo por un boolean o evidencia sintética.
2. Presentar esa propuesta y solicitar autorización separada para persistir,
   limitada a esta operación/documento. No usar la autorización pasada de emisión.
3. Verificar UAT y backup nuevo íntegro. Aplicar con ADMIN autenticado por los
   mecanismos existentes y transacción que bloquee el documento exacto por tenant.
4. Revalidar estado UNKNOWN_RESULT, huellas, intento único, hash/identidad remota,
   e-NCF y ausencia de asociación contradictoria. No resetear/cambiar el trial
   consumido. Con las garantías hoy implementadas, el objetivo máximo sería
   HUMAN_REVIEW_REQUIRED con resultado observado explícito, no DGII_ACCEPTED.
5. Registrar vínculo y observación/auditoría append-only bajo clave estable de
   conciliación derivada de tenant+operación+hash+versión; mismo contenido debe
   devolver ALREADY_RECONCILED sin doble evento y contenido divergente debe fallar.
   Mantener la secuencia consumida y las reservas. No UPDATE SQL manual del estado.
6. Comprobar estado/historial y que siguen1 POST,0 GET salvo consulta nueva
   específicamente autorizada. No enviar otro comprobante para resolver el estado.

Hasta completar1–2 no se habilita un ejecutor persistente. Diagnóstico detallado,
pruebas y límites de lo verificable en la sección actual de readiness.

## Procedimiento consumido — no ejecutar otra vez

La autorización para959afb04-b593-4282-b40d-212ed800b507/E320009805001 se
ejecutó una vez el2026-10-14T20:59:46.475Z. HTTP201, legalStatus ACCEPTED,
status REGISTERED, sequenceConsumed=true, id01M4Y3DEPXXG27G8BNQGMNQ04B.
No hubo GET ni reintentos. No repetir el POST ni reutilizar la secuencia.
La discrepancia de validación/correlación mantiene UNKNOWN_RESULT local y no
autoriza reemisión. Readiness contiene el resultado y evidencia vigente.
Los pasos de envío siguientes quedan únicamente como registro histórico.

## Credenciales de acceso UAT resueltas

Identificador vigente **alanube.admin@fullpos.local**, empresa sintética dedicada
fullpos-alanube-uat-access. Usar contraseña definida interactivamente el 2026-10-14,
no la antigua del env ni credenciales de Alanube. Login HTTP201 y JWT/rol/licencia
verificados por preflight; TRIAL estándar hasta 2026-10-21, no autorrenovable.
Ver ECF_ALANUBE_UAT_ADMIN_ACCESS.md (backup, scope y evidencia).

Para próximos accesos ejecutar helper **sin** -CreateSyntheticAdmin. La opción
de creación ya se consumió y rechaza identidades existentes; no sirve como reset.
Preflight fiscal permanece BLOCKED: configuración e-CF de este tenant aún ausente
y dirección Sandbox pendiente. No es un fallo de acceso. No activar emisión.

## Login UAT autorizado: ejecución interactiva disponible

La autorización más reciente permite iniciar API UAT y POST **solo local**
/auth/login. Sustituye la prohibición previa de ese POST; no autoriza llamadas
Alanube ni emisión. Conservar nombre FULLTECH y RNC 132109122. No reconsultar
/company. El único dato externo solicitado es la dirección válida de prueba.

Launcher `scripts/isolated-uat/start-api.ps1`: runtime UAT exclusivo en
127.0.0.1:4002, sin fallback a interfaces públicas; telemetría saliente y emisión
desactivadas. No carga token Alanube. No usar npm start (tiene prestart de
migraciones). Se usa start:dev. No arrancar una segunda API si el puerto está ocupado.

En otra terminal del worktree ejecutar:

```powershell
./scripts/isolated-uat/e32-operator-login-preflight.ps1
```

El helper pide identificador y contraseña oculta (Enter en identificador usa
el ADMIN configurado, sin mostrarlo). Realiza un único POST a 127.0.0.1:4002,
sin proxy, cookies, redirects ni reintentos. JWT exclusivamente en memoria/env
transitorio para CLI; el CLI revalida sesión/tenant/rol/licencia con JwtStrategy.
No pasar contraseña/JWT por argumentos, chat, archivos ni transcripción.
Único artefacto: operator-preflight.json, ignorado, con estado/HTTP/checks/hashes;
no respuesta de login, JWT, contraseña ni refreshToken. Limpieza al terminar.
Si hay rechazo, no reintentar automáticamente ni cambiar licencias o contraseña.

La sesión sigue pendiente mientras el informe indique WAITING_FOR_OPERATOR.
Eso no valida autenticación ni deja solo un bloqueo externo. No afirmar PASS
de sesión/tenant/secretRef/número hasta obtener el preflight autenticado.
Último intento interactivo: HTTP401 Invalid credentials; ADMIN configurado no
existe en esta UAT. Se necesita una cuenta ADMIN existente válida; las credenciales
del portal Alanube no sirven para este login. No ejecutar seed, reset de contraseña
ni activar licencia para evitar el error. Si no existe una cuenta, su provisión
sintética debe prepararse expresamente como operación UAT separada.

Si api:build falla EPERM de DLL Prisma con API en marcha: identificar primero
el PID del listener4002 y el dueño de la DLL de este worktree. Detener solo el
runtime UAT propio, completar build y reiniciar launcher. Ctrl+C del watcher
puede dejar su hijo node activo; no borrar DLL ni matar procesos globalmente.
Esta validación terminó con build PASS y API reiniciada en loopback.

La API pública DOM documenta PATCH /company para actualizar address; no se
ejecutó ni está autorizado. No hay pestaña de portal Sandbox abierta en el
navegador accesible ni URL de portal no sensible confirmada: no se verificaron
menús ni disponibilidad de edición en UI. Revisar el perfil en el portal
suministrado por Alanube sin guardar cambios. Si solo muestra `address`, solicitar
la dirección de simulación al proveedor. No usar literalmente el placeholder.

2026-10-14. **NO EJECUTAR ENVÍO AHORA.** Readiness actual BLOCKED.
Este procedimiento no autoriza emisión. Solo aplica a la UAT aislada de este
worktree; no producción, DGII, alta externa de compañías ni webhooks públicos.

## Última consulta real: no repetir

Una autorización específica ya se consumió con un GET /company, HTTP 200,
2026-10-14T18:48:56.5416763Z. Principal confirmada: id
01M3T6Y4R9BH35XGJ5PP12KV0T, RNC 132109122, type=main. Nombre remoto FULLTECH,
dirección literal `address`. Ver hash/evidencia mínima en el informe readiness.
El vínculo TOKEN_PRIMARY ya no está pendiente; no solicitar una asociada/ULID.
El borrador omite metadata.alanubeCompanyId y conserva el RNC de Alanube.

BLOCKED: `address` no verifica domicilio. Revisar en portal, sin guardar cambios,
si ese perfil de prueba debe emitir como FULLTECH y cuál es su dirección válida.
Si solo muestra el placeholder, enviar el mensaje reducido preparado. No tomar
una dirección de un ejemplo ni cambiar al RNC fiscal de FULLTECH.

API UAT no escuchaba en 4002 y no había JWT del operador. No se ejecutó login:
el permiso de esta tarea prohibió cualquier POST. Los pasos manuales inferiores
usan POST local /auth/login y requieren que el operador los ejecute o autorice
ese login local específicamente. Nunca confundirlo con permiso de envío fiscal.
Los procedimientos GET inferiores quedan como referencia histórica; no repetir
la consulta ni usar el token bajo la autorización ya consumida.

## Antes de la autorización

1. Confirmar raíz FULLPOS-ECF-ALANUBE y feature/ecf-alanube. Conservar todo el
   trabajo local. No commit/push/merge/deploy, reset/clean/stash ni cambio de rama.
2. El usuario confirma entrega oficial Sandbox: RNC 132109122, rango numérico
   9805001–9806000 y vencimiento 2028-12-31. El formato de 13 caracteres de los
   ejemplos oficiales produce E320009805001–E320009806000; candidato primero
   E320009805001. Comprobar que no se usó en el portal; no reservar ni emitir.
   Principal ya confirmada por GET. Falta resolver dirección y nombre de prueba
   discrepantes del perfil remoto, según la última consulta documentada arriba.
3. Usar un tenant UAT de prueba y operador ADMIN con sesión vigente. Conservar
   controles actuales de empresa/membresía/rol/licencia. No fabricar JWT usando
   JWT_SECRET, saltar validaciones, activar licencias ni usar una empresa real.
4. Asociar a ese tenant su configuración e-CF Sandbox revisada: si el RNC es la
   empresa principal, usar companyTarget=TOKEN_PRIMARY, omitir por completo
   metadata.alanubeCompanyId y mantener config.alanubeCompanyId=null. Para una
   asociada, usar ASSOCIATED y ULID confirmado en ambos. Nunca convertir null
   silenciosamente a principal. credentialsSecretRef=env://ALANUBE_SANDBOX_TOKEN, allowedTypes con
   E32 y estado local AUTHORIZED_SANDBOX respaldado por la confirmación. Mantener
   enabled y productionEnabled desactivados. No alterar taxEnabled/ncfEnabled.
5. Completar artifacts/e32-first-trial/manifest.json con los datos confirmados
   y referencias de confirmación. Preservar clientRequestId. Establecer fecha
   real del ensayo; revisar incomeType=1/paymentType=1 del candidato. No poner
   tokens, certificados, clientes reales ni companyId local en el archivo.
6. Conservar el archivo DPAPI existente. Preflight solo comprueba presencia,
   no lo descifra ni hace una prueba nueva de autenticación. El envío futuro
   comprobará que puede cargarlo antes de iniciar su único proceso autorizado.

Los comandos siguientes se ejecutan desde la raíz indicada:

```powershell
npm run api:build
node scripts/isolated-uat/prepare-alanube-contracts.cjs --check
node scripts/isolated-uat/prepare-e32-query-contracts.cjs --check
```

Para inicializar/conservar el borrador sin red ni escrituras DB:

```powershell
. ./scripts/isolated-uat/_common.ps1
Assert-IsolatedEnvironment
node scripts/isolated-uat/init-e32-sandbox-trial.cjs
```

Ese script no inventa e-NCF ni ids. Solo completa RNC/vigencia ya configurados
cuando faltan; preserva el candidato consignado tras revisar las fuentes. El payload sintético lo genera
el código: dos líneas, total 168.00 DOP, ITBIS 18.00 y exento 50.00.

## Contexto de operador y preflight sin llamadas

### Obtener una sesión nueva mediante login UAT real

Procedimiento manual preparado, **no ejecutado por el agente**. El login local
crea una sesión normal en UAT; no es una llamada a Alanube ni una emisión. No
usar el ID de un usuario como autenticación ni firmar un JWT con JWT_SECRET.
No crear usuarios, cambiar contraseñas, habilitar licencias ni ejecutar seeds.
Usar credenciales de un ADMIN sintético existente, obtenidas del operador/vault.

1. Abrir dos terminales sin transcripción, HTTP tracing ni captura de depuración,
   desde el worktree FULLPOS-ECF-ALANUBE, rama feature/ecf-alanube.
2. En terminal A ejecutar `./scripts/isolated-uat/start-api.ps1`. Verifica que el
   banner indique UAT, base fullpos_alanube_uat, DB 127.0.0.1:56550 y API
   127.0.0.1:4002. Este launcher exige puerto API libre: si está ocupado, no
   autenticar contra un proceso desconocido ni detener procesos indiscriminadamente.
   No usar start-api-with-alanube-env.ps1: no hace falta descifrar el token Alanube.
3. En terminal B ejecutar el bloque siguiente. El contrato real es
   POST /auth/login con identifier/password; devuelve accessToken/user. No hay
   prefijo global /api en main.ts. AuthService comprueba contraseña, bloqueo y
   licencia antes de crear sesión; el CLI vuelve a validar firma/sesión/tenant/rol.

```powershell
. ./scripts/isolated-uat/_common.ps1
Assert-IsolatedEnvironment
if ((git branch --show-current).Trim() -ne 'feature/ecf-alanube' -or
    (Split-Path $RepoRoot -Leaf) -ne 'FULLPOS-ECF-ALANUBE') { throw 'UAT_WORKTREE_REQUIRED' }
if ((docker port $ContainerName 5432/tcp).Trim() -ne '127.0.0.1:56550') { throw 'UAT_BINDING_REQUIRED' }
if ((docker exec $ContainerName psql -U $DbUser -d $DbName -tAc 'SELECT current_database();').Trim() -ne 'fullpos_alanube_uat') { throw 'UAT_DATABASE_REQUIRED' }
$env:ALANUBE_ENABLE_REAL_CALLS = 'false'
$env:ECF_EMISSION_ENABLED = 'false'
$env:ECF_ALANUBE_AUTH_TESTS_ENABLED = 'false'
$env:ALANUBE_HTTP_TRANSPORT_ENABLED = 'false'
Add-Type -AssemblyName System.Net.Http
$e32Login = $null; $e32Response = $null; $e32Content = $null
$e32PasswordPointer = [IntPtr]::Zero
$e32Handler = [System.Net.Http.HttpClientHandler]::new()
$e32Handler.AllowAutoRedirect = $false
$e32Handler.UseProxy = $false
$e32Client = [System.Net.Http.HttpClient]::new($e32Handler)
$e32Client.Timeout = [TimeSpan]::FromSeconds(15)
try {
  $e32Identifier = Read-Host 'Identificador del ADMIN de prueba UAT'
  $e32Password = Read-Host 'Contraseña UAT' -AsSecureString
  $e32PasswordPointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($e32Password)
  $e32LoginBody = @{
    identifier = $e32Identifier
    password = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($e32PasswordPointer)
  } | ConvertTo-Json -Compress
  $e32Content = [System.Net.Http.StringContent]::new($e32LoginBody, [Text.Encoding]::UTF8, 'application/json')
  $e32Response = $e32Client.PostAsync('http://127.0.0.1:4002/auth/login', $e32Content).GetAwaiter().GetResult()
  if ([int]$e32Response.StatusCode -ne 200 -and [int]$e32Response.StatusCode -ne 201) { throw 'UAT_LOGIN_REJECTED' }
  $e32Login = $e32Response.Content.ReadAsStringAsync().GetAwaiter().GetResult() | ConvertFrom-Json
  if (-not $e32Login.accessToken -or $e32Login.user.role -ne 'ADMIN' -or -not $e32Login.user.companyId) { throw 'UAT_ADMIN_TENANT_REQUIRED' }
  $env:ECF_SANDBOX_OPERATOR_JWT = $e32Login.accessToken
  # El ID solo comprueba coincidencia con el sujeto del JWT; no lo sustituye.
  ./scripts/isolated-uat/e32-sandbox-preflight.ps1 -ActorId $e32Login.user.id -Manifest ./artifacts/e32-first-trial/manifest.json
} catch {
  # No imprimir excepción, respuesta HTTP, objetos de login ni sus propiedades.
  Write-Host 'UAT_LOGIN_OR_PREFLIGHT_BLOCKED: revisar estado local sin volcar credenciales.'
} finally {
  Remove-Item Env:ECF_SANDBOX_OPERATOR_JWT -ErrorAction SilentlyContinue
  if ($e32PasswordPointer -ne [IntPtr]::Zero) { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($e32PasswordPointer) }
  if ($e32Content) { $e32Content.Dispose() }
  if ($e32Response) { $e32Response.Dispose() }
  $e32Client.Dispose(); $e32Handler.Dispose()
  Remove-Variable e32Login,e32LoginBody,e32Password,e32Identifier -ErrorAction SilentlyContinue
}
```

No ejecutar `$e32Login`, `.accessToken`, `.refreshToken`, `Format-List`, curl con
Bearer, `Tee-Object`, redirecciones ni Start-Transcript. JWT y contraseña solo
residen transitoriamente en memoria; quitar referencias no garantiza borrado de
strings administrados. El preflight usa el access token, nunca refreshToken, y
lo elimina de su proceso hijo al terminar. Se descarta refreshToken; no se usa
renovación automática. La sesión creada sigue su expiración normal; limpiar el
entorno no la revoca. Ante 401/403/licencia inválida, no saltar controles.

### Si ya hay una sesión UAT vigente

Obtener el JWT de acceso de una sesión UAT existente por los canales locales
normales del operador. No pegarlo en chat, archivos, argumentos ni documentos.
No crear una sesión ni ejecutar login automáticamente en esta tarea.
En la terminal local se puede cargar sin eco con un prompt seguro:

```powershell
$operatorJwtSecure = Read-Host 'JWT de acceso de la sesión UAT' -AsSecureString
$operatorJwtPointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($operatorJwtSecure)
try {
  $env:ECF_SANDBOX_OPERATOR_JWT = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($operatorJwtPointer)
  ./scripts/isolated-uat/e32-sandbox-preflight.ps1 -ActorId $ActorId -Manifest ./artifacts/e32-first-trial/manifest.json
} finally {
  [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($operatorJwtPointer)
  Remove-Item Env:ECF_SANDBOX_OPERATOR_JWT -ErrorAction SilentlyContinue
}
```

## Verificar el emisor Sandbox sin emitir

HECHO / usuario + fuente oficial: el RNC 132109122 corresponde al nombre
**Alanube Soluciones S.R.L.** en el [ejemplo público E32](https://developer.alanube.co/changelog/api-fe-dom-actualizaci%C3%B3n-de-gesti%C3%B3n-de-secuencias).
El ejemplo usa ese RNC como comprador y luego como emisor corregido; permite
corroborar el nombre, pero no la dirección ni la empresa de nuestra credencial.
Se completó solo legalName en el borrador. No usar RNC ni identidad de FULLTECH.
La dirección de ejemplo "Casa de juan" no es evidencia de domicilio de Alanube.

### Portal, operado manualmente por el usuario

1. Entrar al portal desde el enlace Sandbox entregado por Alanube, sin compartir
   credenciales ni sustituirlo por una URL inventada. Confirmar país DOM y Sandbox.
2. Abrir el detalle/perfil empresarial disponible en ese portal y localizar el
   RNC 132109122. Revisar razón social y dirección de operación del emisor.
   Registrar únicamente esos campos no secretos y la fecha/referencia de revisión.
3. Comprobar qué empresa está vinculada a la credencial de integración. No copiar
   ni revelar el token. Si el portal indica empresa principal para ese RNC, usar
   TOKEN_PRIMARY y omitir metadata.alanubeCompanyId. Si indica asociada, copiar
   su ULID de proveedor y usar ASSOCIATED. El UUID interno UAT no sirve aquí.
4. Revisar el historial/rango disponible para E320009805001 sin pulsar emitir,
   crear factura, reservar secuencia, guardar configuración ni generar pruebas.
5. Si el portal no expone esos campos/vínculos, no inferirlos: usar la consulta
   GET autorizada por separado o el mensaje manual reducido al proveedor.

No se inspeccionó el portal ni hay documentación pública verificada de sus
menús: "detalle/perfil" describe lo que buscar, no nombres de botones confirmados.

### Consulta API preparada, NO autorizada ni ejecutada

Fuente oficial DOM: [GET empresa del token](https://developer.alanube.co/reference/getselfcompany-1),
`GET https://sandbox.alanube.co/dom/v1/company`. No necesita id para responder
qué empresa corresponde al token. El schema público tiene name, identification,
type (main/associated), address e id. Leer solo esos campos; no almacenar ni
imprimir certificado, webhooks, cabeceras, cuerpo completo ni credenciales.

Procedimiento tras autorización expresa **solo para este GET**, independiente
de una emisión:

1. Verificar worktree/UAT y todos los interruptores fiscales en false.
2. Cargar el token DPAPI en memoria; enviar exactamente un GET al host y ruta
   anteriores con Bearer, sin body, redirects ni reintentos; timeout 15 s y
   límite de respuesta 64 KiB. No abrir el explorador interactivo de emisión.
3. Registrar HTTP, fecha, hash SHA-256 y campos no secretos permitidos. Si 200,
   identification=132109122 y type=main, revisar name/address y usar TOKEN_PRIMARY.
   No exigir company.id para emitir con la principal.
4. Si el RNC difiere o type no confirma main, detener la selección primaria.
   Conseguir en portal/soporte el ULID de la empresa Sandbox autorizada. Solo con
   nueva autorización consultar [GET /company/{id}](https://developer.alanube.co/reference/getcompany-1)
   y comparar identification/name/address/type. No explorar IDs ni listar tenants.
5. Limpiar memoria/entorno; no cambiar configuración ni manifiesto automáticamente.
   Un 200 no demuestra numeración disponible ni aceptación fiscal.

La fase 31 hizo un GET /company con HTTP 200, pero descartó el cuerpo; no hay
identidad/dirección recuperable de ese informe. No volver a ejecutar
test-alanube-sandbox-auth.ps1 para este fin: clasifica autenticación y descarta
los campos que ahora se necesitan. No se ha solicitado ni autorizado repetirlo.

$ActorId es el UUID del operador esperado, no una empresa. La firma HS256,
expiración/token de acceso y JwtStrategy validan sesión/membresía/licencia/rol;
la empresa proviene de ese contexto autenticado. Seleccionar un UUID solo no
autentica. La clave JWT se toma del entorno UAT existente sin mostrarse.

Preflight verifica raíz/rama, Docker fullpos_alanube_uat_postgres con único binding
127.0.0.1:56550, nombre DB, schema, usuario/empresa/config, manifiesto/fechas,
payload/Ajv/totales, rango/autorización/vigencia, colisión local, identidad estable,
slot global sin consumir, secretos sin valores, consulta y barreras. El propio
CLI repite aislamiento Docker, de modo que invocarlo sin wrapper no salta ese control.

Solo READY_FOR_AUTHORIZATION permite pedir consentimiento. No significa GO fiscal
ni aceptación DGII. BLOCKED devuelve checks concretos y salida no cero. No hay
opción force/skip para ignorarlos. Si está listo, artifacts/e32-first-trial/payload.json
contiene el candidato revisable; el reporte muestra hashes sin cuerpo ni secretos.

## Consentimiento específico, todavía pendiente

Solicitar al usuario aprobación de este alcance exacto, con datos ya completos:

> Autorizo un único POST E32 a Alanube DOM Sandbox para el manifiesto SHA-256
> [hash revisado], la compañía de prueba [id confirmado], el e-NCF [autorizado]
> y total RD$168.00; y como máximo un GET posterior por id/idCompany. Autorizo
> cargar la credencial protegida solo en ese proceso y habilitar sus flags
> efímeros. Sin reintentos, producción, nuevas empresas ni webhooks. Ante
> resultado desconocido, detener todo nuevo POST y preservar evidencia.

Solo después de esa aprobación crear localmente
artifacts/e32-first-trial/authorization.json con los campos siguientes. No se
creó ese archivo ni se otorgó consentimiento en esta preparación:

```json
{
  "manifestFingerprint": "HASH_REAL_DEL_REPORTE_REVISADO",
  "actorId": "UUID_DEL_OPERADOR_AUTENTICADO",
  "expiresAt": "FECHA_ISO_UTC_FUTURA_MAXIMO_30_MINUTOS",
  "maxPosts": 1,
  "maxQueries": 1,
  "approvalReference": "REFERENCIA_A_LA_APROBACION_EXPRESA_DEL_USUARIO"
}
```

Son marcadores para sustituir, no datos de prueba válidos. La autorización no
es firma Alanube ni prueba fiscal. Se verifica hash/actor/TTL/límites y se registra
su hash antes de cualquier envío. No autogenerar aprobación desde un flag.

## Ejecución futura después de aprobar

Volver a cargar el JWT UAT en la variable temporal mediante el mismo prompt seguro
y envolver este comando en el mismo finally de limpieza anterior:

```powershell
./scripts/isolated-uat/e32-sandbox-send-once.ps1 `
  -ActorId $ActorId `
  -Manifest ./artifacts/e32-first-trial/manifest.json `
  -AuthorizationFile ./artifacts/e32-first-trial/authorization.json `
  -ExecuteOnce
```

El script hace preflight y valida consentimiento antes de descifrar DPAPI. Después
el hijo Node verifica todo otra vez. Solo ese hijo puede habilitar flags efímeros;
no modifica .env ni configuración persistente, no arranca API/schedulers. La
credencial no va en argumentos/logs y se limpia al salir. No usar otros launchers
ni prepareFiscalPost para saltarse el recorrido.

Orden reproducible:

| Paso | Control |
| --- | --- |
| A–F | Preflight, compañía, payload, numeración, identidad/switches/consentimiento |
| G | Commit de CLAIMED + intento SEND_TO_PROVIDER + historial antes de tocar red; slot global irreversible |
| H–I | Exactamente una invocación POST /invoices, Bearer, timeout 10s, redirects bloqueados, máximo 64 KiB; hash/HTTP antes de procesamiento posterior |
| J | Solo si 201/schema/id ULID/RNC/e-NCF se correlacionan y no hay id duplicado local: primer binding y un GET /invoices/{id}/idCompany/{idCompany} |
| K–L | Validación GET independiente, hash/observación en cuarentena; estados observados no implican aceptación fiscal |
| M | Reporte STOPPED_REVIEW_REQUIRED, HTTP/observaciones y prohibición de nuevo POST |
| N | Slot no puede volver a PREPARED; payload/manifiesto/historial no se reescriben ni borran |

El transporte general continúa bloqueando POST; el wire de un solo uso no se
registra en la API. MOCK_ONLY nunca puede usarlo. Sin Idempotency-Key DOM inventado.

## Detención y recuperación

Timeout/red/HTTP inesperado/schema incompleto/identidad contradictoria: conservar
UNKNOWN_RESULT, hashes e intento y detener POST. Un 201 válido o legalStatus
ACCEPTED sigue siendo observación no autenticada fiscalmente. Un GET 404/pending
no es rechazo definitivo. Sin id recibido: no adivinar, no reenviar, no reutilizar
número; solicitar localización al proveedor. Otra consulta requiere revisión y
autorización futura; este comando no es un poller ni habilita nuevos GET automáticos.

Si se interrumpió el proceso tras CLAIMED, verificar que el proceso original ya
terminó y recuperar solo el estado local, con JWT UAT válido, sin red ni DPAPI:

```powershell
. ./scripts/isolated-uat/_common.ps1
Assert-IsolatedEnvironment
node ./apps/api/dist/ecf/sandbox/e32-sandbox.cli.js --actor $ActorId --recover-only
```

Mantener el mismo prompt/limpieza JWT. La recuperación marca UNKNOWN_RESULT y
conserva el bloqueo, no restaura permiso para emitir. No matar procesos ajenos.
Ante error de persistencia, el claim previo sigue consumido. No borrar el trial,
editar SQL aplicado, desactivar triggers, restaurar encima de datos posteriores
ni repetir el comando para "probar de nuevo". Escalar y revisar evidencia primero.

Al finalizar informar intentos de red realmente observados, HTTP, ids no secretos,
hashes, consulta, estado local, errores y límites de la evidencia. No declarar
aceptación Alanube/DGII por mocks, HTTP o estructura. No commit/push/deploy.
