# Primera E32 Alanube DOM Sandbox — readiness

## Compatibilidad observada y propuesta de conciliación listas — 2026-10-14

**READY_FOR_SEPARATE_RECONCILIATION_AUTHORIZATION**, exclusivamente para revisión
humana local de la primera E32. No conciliación aplicada, llamadas Alanube nuevas
ni emisión. Reemplaza el bloqueo de compatibilidad de las secciones anteriores;
no concede aceptación DGII ni altera el contrato publicado.

Adaptador: apps/api/src/ecf/sandbox/alanube-dom-e32-compatibility.ts,
perfil versionado ALANUBE_DOM_E32_SANDBOX_OBSERVED_V1. Uso exclusivo de evaluación
local GET E32 principal, Sandbox, empresa verificada igual al tenant de contexto,
total positivo menor de250000, FINISHED/ACCEPTED/sequenceConsumed=true, identidad
y fecha fiscal iguales a la operación esperada. No está registrado como transporte,
controller, mapper global ni emisor. No confiar contexto recibido de un cliente.

| Campo | Publicado / observado | Tratamiento y riesgo controlado |
| --- | --- | --- |
| stampDate | format date / 2026-10-14T00:00:00.000Z | Solo variante exacta de medianoche Z con .000; fecha calendario válida extraída literalmente, igual a issueDate. No convertir a UTC−04: cambiaría la fecha. Rechaza otras horas/offsets. |
| trackId | uuid string / null | Se conserva null como no disponible bajo este perfil de respuesta aceptada E32 Sandbox; nunca fabricar UUID ni usarlo para identificar el documento. El significado publicado es identificador asignado DGII; null no prueba que DGII no lo haya asignado. No se afirma permiso oficial para null. |
| signatureDate | RFC3339 / 14-10-2026 16:59:42 | Formato exacto DD-MM-YYYY HH:mm:ss, calendario y reloj válidos. Representación 2026-10-14T16:59:42, LOCAL_WALL_CLOCK_UNZONED, timeZone=null e instant=null. No inventar zona ni tratarlo como instante de firma verificado. |

Las variantes se documentan como **OBSERVED_COMPATIBILITY**, no
CONFIRMED_OFFICIAL. Fechas conformes al contrato conservan su literal original.
No Date.parse dependiente de locale, conversión de zona, UUID sintético, coerción
global ni cambio de schema. Fechas imposibles, separadores alternativos, firma sin
segundos, offsets no observados para stampDate, trackId no nulo inválido o fallos
adicionales de schema bloquean. La interpretación DD-MM es explícita, no inferida
de la configuración regional del equipo.

Se evalúa el cuerpo completo original con Ajv: **publishedContract.ok=false**,
con los mismos tres errores conservados. Una vista separada usa la fecha literal,
mantiene el trackId no disponible y la firma sin zona fuera de campos wire
opcionales; el resto se valida nuevamente contra el schema oficial sin cambios.
**compatibility.ok=true**, validationViewSchemaValid=true y ningún error restante.
Los valores originales de las tres reglas se conservan en auditoría propuesta;
los bytes originales permanecen cifrados e inmutados. No presentar la vista
compatible como si fuera la respuesta wire ni como conformidad oficial.

Reevaluación desde DPAPI local, sin red: hash
b607a039a5faea11eb189ccfbcb7df6e8f5c6b88f61fbdfbf8d4cc43a2d61b3b
verificado, chainMatches/recoveryChainMatches/encryptedArchiveHashMatches=true;
RNC132109122, E320009805001 e id01M4Y3DEPXXG27G8BNQGMNQ04B exactos. Ninguna
asociación contradictoria en este tenant. ACCEPTED y consumo true coherentes con
POST; FINISHED es el estado de procesamiento recuperado, no prueba fiscal autónoma.

Propuesta local ignorada **artifacts/e32-first-trial/recovery-get-reconciliation-proposal.json**,
clave estable e32-reconcile:539a68567e93ad13009bdde0b3a6a74bd096f35f1373ca589923f6ed5de5f2c3.
Segunda generación: ALREADY_EXISTS_IDENTICAL; no sobrescritura. Generar propuesta
no implementa ni ejecuta una transacción de mutación histórica. Ver runbook para
filas, precondiciones, atomicidad, replay/rollback y autorización futura necesarios.
Objetivo propuesto UNKNOWN_RESULT → HUMAN_REVIEW_REQUIRED, vínculo remoto/e-NCF,
observación ACCEPTED/sequenceConsumed=true y reglas explícitas; trial consumido
y fiscalSnapshot se conservan. canApply=false hasta autorización separada y
ejecutor transaccional autenticado verificado; canGrantDgiiAcceptance=false.

Validaciones actuales:98 focalizadas (38 nuevas del adaptador/plan),94 PostgreSQL,
1039 backend PASS;102 opt-in omitidas en suite general (94PG ejecutadas aparte).
5 regresiones del recuperador PASS. Build completo Prisma+TypeScript PASS;
Prisma validate/status36 migraciones y generador GET --check PASS;
git diff --check PASS. Pruebas incluyen variantes saneadas del GET real, forma
oficial, calendario bisiesto, fechas imposibles/ambiguas, identificador no nulo
inválido, identidad/emisor/estado divergentes, respuesta incompleta, scope tenant
y propuesta determinista/replay divergente bloqueado. No se probó ni ejecutó una
mutación del histórico: solo preparación y regresión de flujos existentes MOCK_ONLY.
Backup antes de fixtures: ecf_before_compatibility_tests_20261014_175717.dump,
1320668bytes, SHA256FF483A28E7EF0EB98C7E1B86BB3E34F3EF698A2975956E28603FFBA821E12C58,
lectura completa pg_restore verificada. Sin migraciones ni cambios de secretos.
API UAT volvió a127.0.0.1:4002 con emisión desactivada tras build.

PostgreSQL histórico sigue UNKNOWN_RESULT/RESPONSE_PENDING_REVIEW, referencias
null,1POST/0QUERY_PROVIDER en DB; la única consulta remota sigue siendo la ya
registrada en journal local. **GO para autorizar la propuesta de revisión humana;
NO-GO para aceptación fiscal automática o nueva emisión.** Firma sin zona y trackId
ausente siguen explícitos como límites de evidencia, sin bloquear el vínculo de
identidad/revisión humana ni fingir aprobación del esquema oficial o certificación.

## Evidencia recuperada mediante único GET autorizado — 2026-10-14

**HECHO: consulta completada sin emisión ni conciliación.** GET exclusivo
https://sandbox.alanube.co/dom/v1/invoices/01M4Y3DEPXXG27G8BNQGMNQ04B,
2026-10-14T21:16:52.201Z (17:16:52 UTC−04), HTTP200.1 GET autenticado,
0 POST/PATCH/PUT/DELETE,0 reintentos,0 redirecciones seguidas. Credencial del
almacén DPAPI Sandbox existente, archivo anterior al POST histórico; no /company,
login ni consultas de otros documentos. No se activaron switches de emisión.

Antes de la consulta: worktree/rama y DB127.0.0.1:56550/fullpos_alanube_uat
verificados; tenant sintético, operación, manifiesto, payload e intento original
coincidentes; trial/documento UNKNOWN_RESULT con1POST/0GET registrados en DB.
Ningún GET previo registrado ni archivo de evidencia GET; advisory lock de sesión
y claim local exclusivo wx impiden otra ejecución de esta herramienta. No tiene
modo de reintento ni otra ruta HTTP. El claim queda consumido incluso ante error.

Endpoint público [consulta E32 principal](https://developer.alanube.co/reference/checkinvoices),
BearerAuth, GET /invoices/{id}, OpenAPI3.0.3. Esquema público completo actual igual
al snapshot fijado, SHA256 canónico88923437ce77a71ce19b908f8395d503e9f5be7efe061ea032688ec0f9f0c4bb.
Validación ejecutada con el contrato de **checkinvoices**, sin sustituirlo por POST
ni por modo asociado; schemaSha2565443aeddd56e0b10bd9d7c159a0604093813953c521707b1993b33734d118d50.

### Resultado observado y correlación

| Campo | Respuesta GET |
| --- | --- |
| id | 01M4Y3DEPXXG27G8BNQGMNQ04B |
| documentNumber | E320009805001 |
| companyIdentification | 132109122 |
| status | FINISHED |
| legalStatus | ACCEPTED |
| sequenceConsumed | true |

Id, e-NCF y emisor coinciden exactamente. La cadena con operación
959afb04-b593-4282-b40d-212ed800b507 y los hashes de manifiesto/payload/evento POST
coincide. REGISTERED→FINISHED es un cambio de procesamiento; legalStatus ACCEPTED
y sequenceConsumed=true permanecen consistentes con la observación original.
No se deduce aceptación fiscal únicamente de HTTP200 ni de FINISHED.

**Contrato completo: FAIL**, tres discrepancias reproducibles, sin normalización:

| Campo | Recibido | Contrato oficial |
| --- | --- | --- |
| stampDate | string 2026-10-14T00:00:00.000Z | string format date (YYYY-MM-DD) |
| trackId | null | string format uuid, sin nullable |
| signatureDate | string 14-10-2026 16:59:42 | string format date-time (RFC3339) |

No asumir zona horaria para signatureDate ni borrar nulls/ignorar errores para
forzar conformidad. Estos errores están demostrados en el **GET nuevo**. No prueban
por sí solos qué campos tenía el POST original, cuyos bytes siguen sin recuperarse.
Ahora existe evidencia suficiente para identificar el documento remoto y su emisor,
pero no conformidad íntegra para aplicar aceptación fiscal automática.

### Custodia y reproducción local

Archivos ignorados distintos del POST: recovery-get-claim.json,
recovery-get-observation.json (campos permitidos + validación) y
recovery-get-response.dpapi (bytes completos cifrados DPAPI CurrentUser).
Respuesta5984bytes; SHA256
b607a039a5faea11eb189ccfbcb7df6e8f5c6b88f61fbdfbf8d4cc43a2d61b3b.
Descifrado solo en memoria, hash y validación estricta reproducidos sin red.
El fallo inicial de la reverificación local era autoload del módulo Security de
Windows PowerShell al heredarse PSModulePath desde pwsh; se corrigió importando
el módulo de $PSHOME explícitamente. No requirió repetir el GET ni cambiar secretos.
historicalPostUnchanged=true; no se sobrescribió evidencia original.

e32-reconciliation-dry-run.cjs ahora reconoce la nueva evidencia, verifica su hash
contra el archivo cifrado y repite el schema desde memoria. Reporta chainMatches,
recoveryChainMatches y encryptedArchiveHashMatches=true, con los tres errores exactos.
No accede a Alanube ni modifica DB.5 tests de recuperación con fetch simulado,
sintaxis JS/PowerShell y generador GET --check PASS. Una nueva ejecución --check
del recuperador debe rechazarse porque ya existe evidencia/claim; no autoriza retry.

**PostgreSQL histórico sin cambios:** documento56cb2743-c4a0-4be4-a167-3cd5d0314f40
y trial2d552e31-4d6b-4ee2-a2b7-7caaf75484dd continúan UNKNOWN_RESULT;
safeErrorCode RESPONSE_PENDING_REVIEW; referencias remotas locales aún null.
El GET nuevo está en el journal local: el contador DB QUERY_PROVIDER sigue0
porque no se insertaron intentos ni eventos históricos durante esta recuperación.
Totales externos de esta prueba:1POST histórico +1GET de recuperación, sin reintentos.

**NO-GO para conciliación persistente automática/aceptación fiscal.** No falta
identidad; falta resolver las tres incompatibilidades con el contrato publicado
y las garantías de evidencia aplicables al estado fiscal objetivo. No crear otra
factura ni consumir otra secuencia. Plan de revisión transaccional condicionado
en runbook; sin ejecutor --apply ni autorización para modificar el histórico.

## Diagnóstico y corrección de conciliación — 2026-10-14

**HECHO: causa directa del estado del documento.** E32SandboxService.runOnce
llamaba recordUnknownOutcome incondicionalmente después del wire, antes de validar
el cuerpo. Para cualquier HTTP recibido elegía RESPONSE_PENDING_REVIEW. Esa
función cambia SEND_IN_PROGRESS a UNKNOWN_RESULT y crea su status log. Ninguna
rama posterior promovía el documento. Incluso una respuesta válida y correlacionada
quedaba UNKNOWN_RESULT: las pruebas anteriores lo exigían. No fue el mapper fiscal,
el cálculo de ITBIS ni una supuesta incompatibilidad REGISTERED/ACCEPTED.

**HECHO: segundo problema de diagnóstico.** correlated combinaba ausencia de
conflicto remoto, HTTP201, schema completo, ULID y coincidencia de e-NCF/RNC.
POST_OBSERVATION=E32_RESULT_UNKNOWN y remoteIdObserved=false solo indican que
esa conjunción falló; el nombre confundía «id observado» con «id vinculado».
El id y e-NCF del archivo seguro sí son strings válidos e iguales al envío;
sequenceConsumed es boolean true. Actualmente no hay otra asociación al id en el
tenant. No se conservaron companyIdentification ni los otros campos completos,
errores Ajv o resultados individuales del predicado. El hash no recupera los bytes.
**No es verificable qué subcondición concreta falló en aquella respuesta.** No
atribuirlo a stampDate, un null, el RNC u otro campo sin evidencia. governmentResponse
{} y response=null en la proyección NO permiten reconstruir el cuerpo original:
el minimizador también introduce null al faltar datos. No usar la proyección como
si fuera el JSON recibido ni alterar el contrato para hacerla pasar.

**Contrato verificado.** Documento público oficial
[POST E32](https://developer.alanube.co/reference/createinvoices), OpenAPI3.0.3,
API FE DOM1.0.0. El esquema público completo consultado hoy coincide con el snapshot
fijado; SHA256 canónico de comparación
aeb46720edf15264b1250bd72aa9213fec5a2a298e3ddc0df8add29be63c152a.
status admite REGISTERED/TO_SEND/WAITING_RESPONSE/TO_NOTIFY/FINISHED;
legalStatus admite ACCEPTED/ACCEPTED_WITH_OBSERVATIONS/REJECTED como propiedad
independiente. No hay regla que obligue FINISHED para legalStatus ACCEPTED.
id es string ULID, documentNumber string y sequenceConsumed boolean. El schema no
exige esas propiedades: la ausencia estructuralmente válida no acredita aceptación.
Los campos conocidos de la respuesta son compatibles; no se puede validar el
cuerpo completo perdido. La fuente documenta E32 síncrono para menos de250000DOP
y posible procesamiento diferido por fallo de comunicación. No inferir fiscalidad
solo del HTTP ni de un estado de procesamiento.

**Corrección mínima implementada, sin modificar históricos.**

- assessE32Response aplica el mismo schema oficial sin coerción/relajaciones,
  exige identidad/estado/numeración/sequenceConsumed y contexto de operación para
  una observación correlacionada. Conserva checks, motivos y errores Ajv seguros
  (path/keyword, sin valores). ACCEPTED con sequenceConsumed=false o response
  de procesamiento diferido contradictoria no se acepta.
- El observador captura esos diagnósticos mientras el cuerpo todavía está en
  memoria, antes de descartarlo. No guarda tokens, XML, URLs ni cuerpo completo.
- runOnce separa remoteIdObserved de remoteIdBound. Solo respuesta completa,
  válida y correlacionada pasa SEND_IN_PROGRESS → HUMAN_REVIEW_REQUIRED, con
  resultado del proveedor y sequenceConsumed en status log auditable. Resultado
  incierto, inválido, contradictorio, timeout o falta de correlación sigue UNKNOWN_RESULT.
- No se marca PROVIDER_ACCEPTED ni DGII_ACCEPTED automáticamente. Verificador
  de autenticidad y cuarentena siguen cerrados; fiscalSnapshot permanece null.
  Identidad, unicidad, tenant, latch consumido y prohibición de retry se conservan.

**UAT histórico leído de nuevo, sin cambios:** tenant
e7df7640-04ea-4000-9135-0c4451822205, documento56cb2743-c4a0-4be4-a167-3cd5d0314f40,
trial2d552e31-4d6b-4ee2-a2b7-7caaf75484dd, operación959afb04-b593-4282-b40d-212ed800b507.
Documento/trial UNKNOWN_RESULT, safeErrorCode RESPONSE_PENDING_REVIEW, referencias
remotas aún null,1 intento de POST y0 de GET. La cadena manifiesto/payload/operación/
hash de respuesta coincide: chainMatches=true en diagnóstico READ_ONLY. No se
interpretó sequenceConsumed=true como autorización para liberar/reutilizar la secuencia.

**Validación actual:**60 pruebas focalizadas,94 PostgreSQL y1001 backend PASS;
102 opt-in omitidas en ejecución general (94PG ejecutadas por separado +8restantes).
Build completo Prisma+TypeScript PASS; Prisma validate/status36 migraciones PASS;
generación contractual --check MATCH; git diff --check PASS. Hubo dos fallos
intermedios corregidos sin debilitar reglas: prueba de unicidad suponía slot global
vacío (ahora comprueba rollback de tenants sintéticos propios); prueba de defaults
heredaba referencias/perfil UAT del proceso (se repitió la suite con esas variables
opcionales retiradas solo del proceso de tests, sin cambiar env ni el test).
Backup previo a escrituras de fixtures: ecf_before_reconciliation_tests_20261014_170816.dump,
1211753bytes, SHA2565072BED1D950332FA599143DEF62301B58A9B629BB6B223A8E4F90F4569A0C39,
lectura completa de archivo pg_restore verificada. Sin migraciones, cambios de
producción/POS/Flutter/offline, solicitudes API Alanube ni login HTTP en esta tarea.
Solo se consultó documentación pública; tests fiscales usan MOCK_ONLY/fetch simulado.

**GO de corrección local; NO-GO de conciliación persistente y nuevas emisiones.**
La evidencia conservada permite informar ACCEPTED observado en Sandbox, no probar
el schema/correlación íntegros ni autenticidad fiscal. Procedimiento de solo lectura
repetible y pasos condicionados a evidencia/autorización en el runbook. No hay
modo --apply, no se ejecutó conciliación ni se solicita aprobar un cambio inseguro.

## Resultado real vigente — autorización consumida — 2026-10-14

**ACCEPTED observado en Alanube Sandbox**. Único POST autorizado ejecutado el
2026-10-14T20:59:46.475Z a https://sandbox.alanube.co/dom/v1/invoices.
Operación 959afb04-b593-4282-b40d-212ed800b507, e-NCF E320009805001.
HTTP201; id remoto **01M4Y3DEPXXG27G8BNQGMNQ04B**; status REGISTERED;
legalStatus ACCEPTED; sequenceConsumed **true**. No rechazo informado.
No confundir el resultado Sandbox con certificación ni aceptación en producción.

Preflight nuevo con login local201: los21 checks PASS y hashes coincidentes con
la autorización. Gravado100.00 ×18%=18.00; exento50.00 con billingIndicator4 e
ITBIS0.00; total168.00. Dirección ficticia conservada como dato explícito de prueba.
43 pruebas E32 y89 PostgreSQL PASS; api:build, Prisma validate/status36 migraciones
y git diff --check PASS. No migración aplicada en esta ejecución.

Backup previo verificado: ecf_before_authorized_e32_20261014_165749.dump,
1159996bytes, SHA256 A47C4AD2C492E6C3806BFC5AB768AD591DF9F575C077FB4D73BE303A514C7DDD.

Evidencia local ignorada: artifacts/e32-first-trial/real-post-observation.json
(campos permitidos, no respuesta completa), real-trial-result.json,
operator-preflight.json y authorized-send-backup.json.
Respuesta original5918bytes, SHA256
86191b9d6bf5b50c950deb0c7d6adcb55e9a4e6837836e5581cf6cbef66d9427,
coincidente con POST_OBSERVATION en PostgreSQL.

**Discrepancia local pendiente:** la respuesta no superó la validación conjunta
de schema/correlación del servicio; no se conoce cuál condición exacta falló con
la evidencia conservada. No se guardó el cuerpo completo por seguridad. Por ello
remoteIdObserved=false en real-trial-result significa «no vinculado automáticamente»,
no ausencia de id en la respuesta. El id, e-NCF y estados anteriores sí están
observados en el archivo seguro del mismo POST. No debilitar el validador ni
marcar DGII_ACCEPTED para ocultar esta discrepancia.

Documento y trial locales conservan UNKNOWN_RESULT, sin vínculo remoto automático.
Trial2d552e31-4d6b-4ee2-a2b7-7caaf75484dd consumido; DB confirma1 SEND_TO_PROVIDER
y0 QUERY_PROVIDER. No hubo GET: la consulta automática quedó cerrada al no superar
esa validación. No repetir POST para obtener una respuesta distinta. No reutilizar
E320009805001: sequenceConsumed=true. Próximo trabajo: conciliación local de esta
respuesta; cualquier consulta debe respetar autenticación y el máximo autorizado.

Config continúa enabled=false, productionEnabled=false, SANDBOX,
certificationStatus=NOT_STARTED. JWT/token eliminados del proceso operador al
terminar; no cambio de perfil, producción, POS tradicional, Flutter ni offline.
Sin deploy/commit/push/merge. Las secciones siguientes son antecedentes históricos,
no instrucciones para volver a ejecutar el envío. **NO-GO para otra emisión.**

## Preparación final con dirección ficticia explícita — 2026-10-14

**READY_WITH_PROVIDER_UNCERTAINTY**. Preflight autenticado
**READY_FOR_AUTHORIZATION**, 21 checks true, 0 blockers, completedAtUtc
2026-10-14T20:43:22.1484895Z. Login local nuevo HTTP201. authorizationGranted=false,
externalRequests=0, fiscalPosts=0. No se ejecutó POST /invoices ni consulta remota.

### Causa anterior y evidencia contractual

El campo exacto es **sender.address**, no company.address. El schema POST E32
descargado/fijado requiere string de máximo100 caracteres; no declara pattern,
enum, const ni condición de coincidencia con el perfil remoto. La dirección
propuesta por el usuario tiene61 caracteres y pasa schema y conformance.
El perfil remoto conserva el literal address; no se modificó.
El bloqueo anterior fue address=null (inválido en schema) más política preventiva
local al no tener una dirección confirmada. No hubo rechazo real de Alanube.

Fuente pública [POST E32](https://developer.alanube.co/reference/createinvoices)
y su OpenAPI fijado createinvoices.openapi.json. La documentación revisada no
establece permiso explícito ni prohibición específica de domicilio ficticio DOM
Sandbox, ni confirma si debe coincidir con el perfil. La ausencia de una restricción
estructural no es aceptación del proveedor. No se usa un ejemplo como autorización.
El [PATCH de perfil](https://developer.alanube.co/reference/updateselfcompany-1)
es una operación distinta, no ejecutada y no necesaria para validar localmente
este payload; su necesidad operativa no está confirmada por Alanube.

### Selección de prueba autorizada localmente

El adjunto 820a9ea8-d16d-45c4-a80f-4fa8555026cd autoriza preparar la dirección
**CALLE PRUEBA 123, HIGUEY, LA ALTAGRACIA, REPUBLICA DOMINICANA**, ficticia,
no verificada por Alanube y no representativa del domicilio fiscal de FULLTECH.
Manifest ignorado contiene syntheticAddressTest: propósito explícito,
tenantCompanyId local, referencia de autorización y providerVerified=false.
No hay valor por defecto ni selección implícita. company.address no se cambia.
No se cambia AppConfig ni datos fiscales tradicionales.

Guardas E32 exclusivas: APP_ENV=uat/UAT_LOCAL_ONLY=true, ALANUBE_ENV=sandbox,
URL PostgreSQL estricta127.0.0.1:56550/fullpos_alanube_uat sin overrides de query,
tenantCompanyId del manifiesto igual al tenant autenticado, slug/nombre exactos
de empresa sintética, FULLTECH/RNC132109122 y TOKEN_PRIMARY. CLI valida la
selección y servicio la revalida en DB antes de preparar o despachar, aun si
se falsifican los facts. Otro tenant, producción o selector omitido fallan.
La etiqueta no se envía como campo inventado del contrato Alanube; queda en
manifiesto/evidencia local y se incluirá en su hash/consentimiento.

### Payload revisable

- Emisor FULLTECH, RNC132109122, principal remota confirmada por GET histórico;
  sin company.id en request. Tenant local sintético e7df7640-04ea-4000-9135-0c4451822205.
- Fecha2026-10-14, contado paymentType1/incomeType1, DOP.
- Dirección ficticia explícita indicada arriba, no aprobada por Alanube.
- Consumidor final de prueba sin comprador identificado, total inferior al umbral
 250000 DOP; no se inventan datos reales ni RNC del receptor.
- Bien sintético, cantidad1, precio100.00, ITBIS18%=18.00.
- Servicio sintético exento, cantidad1, precio50.00.
- Subtotal150.00; gravado100.00; exento50.00; ITBIS18.00; total168.00 DOP.
- Candidato E320009805001, rango suministrado E320009805001–E320009806000,
  vence2028-12-31. Sin colisión local ni consumo por este flujo; disponibilidad
  en otros clientes/portal no fue consultada nuevamente.
- clientRequestId959afb04-b593-4282-b40d-212ed800b507 preservado.
- Endpoint futuro POST https://sandbox.alanube.co/dom/v1/invoices. No ejecutado.
- Manifest fingerprint1ed4a6946f379360a7196b3e6acf7825fc070a6120c9a156da477e9910544990.
- Payload fingerprint37f68474e054ed217655cc409718e6b85cf32f0fcf63560a032ff119a81d4f0d.

### Validación/evidencia y límites

Artefactos ignorados artifacts/e32-first-trial/: manifest.json, payload.json,
synthetic-address-validation.json (schema/conformance/sourcehash),
operator-preflight.json (login/checks/hashes, no JWT). Payload final coincide con
su fingerprint. Schema y conformance ok=true. Slot FIRST_E32_SANDBOX sigue vacío:
no preparación fiscal persistente ni intento de envío/consumo de latch real.
Pruebas de persistencia y timeout/concurrencia/consulta son MOCK_ONLY.

Pruebas ejecutadas:
- Jest e32-sandbox.spec:41 PASS; PostgreSQL:89 PASS (incluye aislamiento del override).
- Jest backend:982 PASS,97 omitidas (89 PG ejecutadas aparte y8 opt-in ajenas).
- npm run api:build:PASS final (Prisma generate5.22 + tsc).
- Prisma validate PASS; migrate status36 migraciones al día; contratos --check MATCH.
- Parser PowerShell0 errores; git diff --check PASS; escaneo focalizado8 archivos,
 0 patrones de claves privadas/JWT. No prueba exhaustiva de ausencia de secretos.

Se corrigió una incompatibilidad TS del tipo ProcessEnv en la nueva guarda;
primer build falló, repetición tuvo EPERM por DLL retenida por nuestra regresión
en curso. Se esperó su finalización y build completo pasó sin borrar DLL ni
matar procesos ajenos. API reiniciada solo loopback4002, login final201.
Primer login de esta tarea rechazó contraseña401; segundo login201 validó sesión,
empresa/rol/licencia actuales. No reutilizar JWT de anteriores evidencias.

Configuration sigue enabled=false, productionEnabled=false,
certificationStatus=NOT_STARTED. taxEnabled/ncfEnabled=false conservados.
No schema/migraciones nuevas ni cambios a Flutter/POS/offline/auth/licencia.
Cambios: policy/CLI/service/spec E32, specPG E32, helper de login, manifiesto
ignorado, este informe y next_steps. Sin commit/push/merge/deploy/producción/DGII.

### Riesgo pendiente y siguiente acción

La aceptación operativa de la dirección ficticia y del documento solo podrá
observarse con una respuesta real, sin equiparar HTTP201 ni validación a
aceptación fiscal. El rango proviene del paquete confirmado por usuario; no
existe garantía nueva de idempotencia del proveedor. Máximo1 POST, sin retry ni
poller; timeout/resultado desconocido detiene el flujo con latch irreversible.
Solicitud de autorización siguiente debe ligar exactamente manifiesto/payload
anteriores, 1 POST y máximo1 GET correlacionado; requiere sesión UAT vigente y
preflight actualizado al ejecutar. **Este informe no autoriza el envío.**

## Resultado definitivo de configuración local — 2026-10-14T20:17:55Z

**Configuración UAT PASS; dirección PENDIENTE; preflight BLOCKED solo E32_PAYLOAD.**
Login nuevo HTTP201, GET local /auth/me válido y PATCH oficial /ecf/config HTTP200
con ADMIN del tenant sintético. JWT solo memoria y eliminado al terminar.
Verificación posterior en DB, scoped a fullpos-alanube-uat-access: SANDBOX,
enabled=false, productionEnabled=false, certificationStatus=NOT_STARTED,
allowedTypes=[E32], alanubeCompanyId=null (principal del token). Referencia
protegida confirmada por preflight, nunca token en DB. Auditorías CONFIG_CREATED
y CONFIG_UPDATED pertenecen al ADMIN autenticado. taxEnabled/ncfEnabled=false
conservados. Backup previo verificado ya registrado abajo; sin migraciones nuevas.

Todos los checks del preflight son true salvo E32_PAYLOAD: address sigue null,
no se admite literal address ni se inventa un domicilio. OPERATOR_CONTEXT,
TEST_COMPANY_CONFIRMED, SECRET_REFERENCE, NUMBER_UNUSED_LOCALLY, numeración,
identidad, persistencia, contrato GET y slot único intacto: PASS. Contrato
estructural/mapper y pruebas simuladas PASS; payload real incompleto, no listo
para autorización. Único bloqueo externo restante: dirección/regla Sandbox.

Durante la interacción se corrigieron dos problemas del helper: selección
inequívoca del usuario sintético en modo ConfigureEcfSandbox (rechazos previos
por identificador) y SHA256 mediante .NET para no depender de Get-FileHash,
que no se cargó en esa ventana Windows PowerShell. Login201/config200/preflight
completado verifican funcionalmente la corrección. Parser PowerShell y diff PASS.
No contraseñas, hashes de contraseña, JWT ni respuestas completas guardadas.

Evidencia mínima ignorada: operator-preflight.json, completedAtUtc
2026-10-14T20:17:55.7384564Z. ExternalRequests=0, fiscalPosts=0.
No /company, Alanube autenticado, DGII, producción, POS/Flutter/offline ni
commit/push/merge/deploy. Mantener emisión apagada. Recibir respuesta concreta
al borrador de dirección, completar solo address confirmado y volver a preflight
con sesión vigente; después presentar payload/hash para autorización de un POST.

## Cierre de configuración del tenant y dirección — estado actual

2026-10-14. Configuración por PATCH /ecf/config, con guardas JWT/ADMIN existentes,
preparada exclusivamente para fullpos-alanube-uat-access. Backup completo previo:
ecf_before_tenant_config_20261014_194502.dump, 1060285 bytes, SHA256
75ED282A2B0F45AE1CCD3DFFA2A0343833FC6C4E1B3EC17DFF44CDA52DAD322B.
pg_restore lectura completa y copia/hash verificados; constancia ignorada en
tenant-config-backup.json. No restauración ni migración nueva.

El preflight exigía erróneamente AUTHORIZED_SANDBOX para preparación local.
Corregido solo en el flujo de primera E32: una configuración SANDBOX desactivada,
sin producción, con E32 y destino coherente puede estar preparada aunque la
certificación siga NOT_STARTED. BLOCKED/enabled/producción/destino contradictorio
siguen rechazados; consentimiento y demás barreras de red no se cambian.
Se rechaza también dirección vacía o literal address. 40 pruebas focalizadas PASS.

PATCH preparado conserva enabled=false, productionEnabled=false,
certificationStatus=NOT_STARTED (no se envía ni altera ese campo). Referencia
protegida, solo E32, destino principal sin company.id en el payload. Notes registra
RNC132109122, remoto01M3T6Y4R9BH35XGJ5PP12KV0T/main/FULLTECH y hash del GET ya
confirmado, separados de companyId local autenticado y de cualquier certificación.
El helper verifica /auth/me, nombre/slug sintéticos y backup antes de PATCH.
No recibe companyId del cliente. Backend conserva sus auditorías y permisos.

Estado operativo al registrar: ventana de login -ConfigureEcfSandbox abierta,
WAITING_FOR_OPERATOR/0 intentos; aún no se aplicó el PATCH ni se revalidó el
tenant con un JWT nuevo. No declarar configuración PASS hasta obtener resultado.

Dirección (solo fuentes públicas DOM):
- A: sender.address es requerido por el schema POST oficial, string <=100.
- B: no se encontró permiso explícito para domicilio sintético Sandbox. Un
  ejemplo informal no prueba autorización ni condiciones de uso de ese domicilio.
- C: no se encontró regla explícita de coincidencia con company.address.
- D: PATCH /company permite actualizar address, pero no demuestra que corregir
  el perfil sea requisito previo de E32. No se ejecutará cambio remoto.
Se mantiene sender.address=null; no se inventa dirección real ni de prueba.
Consulta exacta preparada en el borrador existente, no enviada. Falta únicamente
resolver esa política/dirección con Alanube en el ámbito externo.

Fuentes: [POST E32](https://developer.alanube.co/reference/createinvoices),
[perfil DOM](https://developer.alanube.co/reference/updateselfcompany-1),
[Sandbox versus certificación](https://developer.alanube.co/docs/proceso-de-certificaci%C3%B3n).
No se importaron reglas de CRI/PER/COL. No llamadas autenticadas nuevas ni DGII.

Validaciones de este bloque: build backend PASS (Prisma generate+tsc), 981 Jest
backend PASS/96 omitidas (88 PostgreSQL ejecutadas aparte PASS, 8 opt-in ajenas),
Prisma validate PASS y migrate status 36 al día, contratos --check MATCH,
parser PowerShell 0 errores, git diff --check PASS. Regresión monetaria/mapper,
idempotencia/concurrencia/persistencia/GET-conciliación MOCK_ONLY cubiertas por
esas suites. Cero POST fiscal, emisión, cambios a producción/POS/Flutter/offline,
commits/push/merge/deploy. La API se reinició solo en loopback para el build.

## Acceso ADMIN UAT resuelto — 2026-10-14T19:25:43Z

**ADMIN_ACCESS_GO**: alanube.admin@fullpos.local, empresa sintética dedicada
fullpos-alanube-uat-access. Auditoría inicial confirmó cero ADMIN en esta base;
se creó solo empresa STANDARD/TRIAL siete días, usuario ADMIN y OWNER/ACTIVE
mediante bcryptjs coste10 oficial, tras backup verificado. El operador definió
contraseña nueva oculta; no se usa ni cambia la contraseña antigua del env.
Login local HTTP201, JWT solo memoria, OPERATOR_CONTEXT=true con JwtStrategy.
Relectura DB: no bloqueado, empresa ACTIVE, TRIAL válida hasta 2026-10-21,
una sesión activa, NCF/impuestos tradicionales desactivados. Usuarios previos
modificados: 0. API sigue 127.0.0.1:4002. No problemas nuevos de arranque.

Backup previo: ecf_before_admin_access_20261014_192227.dump, 1059034 bytes,
SHA256 F4D87719212FD540BFB7B8F904A2A455161E341F0DBA0C75864317DE6E519CC4,
pg_restore lectura completa y hash/tamaño verificados. Sin restore ni seed general.
Procedimiento/evidencias: ECF_ALANUBE_UAT_ADMIN_ACCESS.md y artefactos ignorados.
Guardas nuevas 3 PASS, JWT/preflight E32 35 PASS, sintaxis JS/PowerShell y diff PASS.

**Preflight E32 BLOCKED** con acceso ya válido. Restan:
1. TEST_COMPANY_CONFIRMED/SECRET_REFERENCE: tenant nuevo aún no tiene configuración
   e-CF (count=0 confirmado). Prepararla como tarea fiscal local explícita manteniendo
   emisión apagada; no inventar datos ni declarar certificación DGII.
2. E32_PAYLOAD: falta dirección válida Sandbox; FULLTECH/RNC132109122 se conservan.
Todos los demás checks son true, incluidos actor, numeración y ausencia de colisión
local. No activación fiscal como efecto secundario de resolver acceso. No contactos
Alanube ni /company, cero solicitudes externas/POST fiscales, ningún cambio en
producción, POS/Flutter, auth, licencias existentes, migraciones o Git de escritura.

## Sesión UAT interactiva autorizada: progreso real

### Resultado posterior al intento interactivo y build

El operador completó un intento local: POST /auth/login, **HTTP 401 Invalid
credentials**, 2026-10-14T19:00:10.0301839Z. No JWT obtenido ni persistido. El
stack del servidor señala AuthService.login línea 59 (identificador sin usuario).
Diagnóstico por identificador configurado, sin imprimirlo: configuredUatAdminExists=false.
No se listaron empresas ni se eligió un usuario por ID para simular autenticación.
No se creó usuario, contraseña, sesión artificial ni licencia.

Por tanto permanece un bloqueo **interno de datos UAT**: disponer de credenciales
de un ADMIN existente de esta base. Si no existe, preparar su provisión sintética
como operación UAT separada, con alcance/backup revisados; no ejecutar seed ni
crear una cuenta/activar licencia implícitamente. Se pidió aclaración al operador.
Las verificaciones por tenant (perfil e-CF, secretRef, licencia, colisión) quedan
NOT_EVALUATED; no declararlas PASS ni inventar un tenant para continuarlas.

Build finalmente **PASS**: tras Ctrl+C quedaba vivo nuestro hijo node PID31120,
verificado como único dueño de la DLL Prisma del worktree y listener local4002.
Se detuvo exclusivamente ese PID, sin borrar DLL, y npm run api:build completó
Prisma generate 5.22 + tsc con exit0. API reiniciada con launcher corregido,
listener verificado 127.0.0.1:4002/PID33860. Prisma validate PASS.
No se tocó ningún otro proceso ni se modificó configuración persistente.

Preflight repetido tras el intento: **BLOCKED**, E32_MANIFEST=true,
E32_PAYLOAD=false (address=null), OPERATOR_CONTEXT=false. No puede quedar
únicamente un bloqueo externo hasta superar login/licencia/configuración real.
Único dato externo solicitado: dirección válida Sandbox para FULLTECH/RNC132109122.
El nombre observado FULLTECH se conserva por instrucción del usuario.

Archivos de esta corrección: apps/api/src/ecf/ecf.module.ts,
apps/api/src/ecf/ecf.module.spec.ts, apps/api/src/main.ts,
scripts/isolated-uat/start-api.ps1, scripts/isolated-uat/e32-operator-login-preflight.ps1,
este informe, runbook, master_context, next_steps y borrador de consulta.
Artefacto ignorado: operator-preflight.json, solo status/HTTP/checks, sin secretos.
Resto del registro de progreso inferior es histórico donde difiera.

2026-10-14. El usuario autoriza API y login local; conserva FULLTECH/RNC
132109122 como identidad Sandbox. Ya no se pide aclarar el nombre. No repetir
GET /company. Dirección pendiente: no usar `address`, no modificar perfil remoto.

Fallo reproducido al arrancar: Nest UnknownDependenciesException al inyectar
Array opcional de EcfSecretResolverService. Corregido con factory ConfigService
explícita en EcfModule; prueba del módulo completo sin red PASS y barrera de
secretos productivos preservada. Además, el arranque inicial enlazaba [::]:4002;
main.ts ahora fuerza 127.0.0.1 solo para UAT_LOCAL_ONLY, sin fallback abierto.
Launcher UAT desactiva telemetría y emisión y elimina token Alanube del entorno.

API corregida iniciada/verificada en 127.0.0.1:4002; GET local /health/db:
HTTP 200, status/db=ok. Base fullpos_alanube_uat, Docker 127.0.0.1:56550.
Se abrió ventana interactiva para helper e32-operator-login-preflight.ps1.
Informe ignorado operator-preflight.json: WAITING_FOR_OPERATOR, 0 intentos de
login, 0 solicitudes externas, 0 POST fiscales al registrar este progreso.
No se sustituye autenticación por ID; falta entrada del operador en esa ventana.

Validación actual: 1 prueba de composición Nest PASS, 237 e-CF PASS, 976 backend
PASS (96 omitidas, 88 PG probadas antes y 8 opt-in ajenas). tsc separado PASS.
api:build intentado con API en marcha falló EPERM al renombrar DLL Prisma en uso;
no borrar DLL ni matar procesos ajenos. Repetir build tras detener únicamente
nuestro runtime UAT, después de completar la interacción de login.
No declarar build PASS ni autenticación PASS antes de verificarlos.

**Estado intermedio BLOCKED**: dirección externa pendiente y login interactivo
pendiente. Las verificaciones por tenant solo se cierran después de ese login.
No se ha activado emisión ni realizado llamada nueva a Alanube. No cambios en
auth/licencias/ventas/Flutter, sin migraciones ni semillas ni commit/push/deploy.

## Resultado vigente: consulta única autorizada de empresa Sandbox

2026-10-14T18:48:56.5416763Z. **BLOCKED** por dirección ambigua y contexto
operativo UAT pendiente. Esta sección sustituye los pendientes anteriores de
identificación principal/asociada. No se requiere otra consulta para ese vínculo.

HECHO / VERIFIED_BY_LIVE_READ: una solicitud autenticada, exclusivamente
GET https://sandbox.alanube.co/dom/v1/company, token DPAPI existente, HTTP 200.
Sin redirects, cookies, proxy, reintentos ni cuerpo de solicitud. Timeout 15 s,
lectura máxima 64 KiB. Respuesta: 472 bytes, SHA-256
`dcf9103473cc527d696f96f8c91fa9faf4d2bdccd93a84e7820015f26a537364`.
Solo se extrajeron los campos permitidos; cuerpo completo/headers/secretos no
se imprimieron ni persistieron. No se tocó configuración remota.

| Campo observado | Valor literal |
| --- | --- |
| id | 01M3T6Y4R9BH35XGJ5PP12KV0T |
| identification | 132109122 |
| type | main |
| name | FULLTECH |
| address | address |

El RNC coincide y la compañía es **principal del token**. No hace falta company.id
en POST E32 ni consultar otra empresa. El identificador remoto se registra aquí
como evidencia; no se usa como UUID UAT ni se añade a un payload de principal.

**Discrepancia real**: propuesta/ejemplo público vinculan el RNC con Alanube
Soluciones S.R.L., mientras el perfil real de la credencial devuelve FULLTECH.
No se reemplazó el RNC por el de FULLTECH. El nombre observado se copió al
borrador como dato remoto, no como validación de una identidad fiscal distinta.
La dirección literal `address` parece un placeholder: no es una dirección fiscal
Sandbox verificada. Se conserva sender.address=null hasta aclararlo. No se
inventa domicilio ni se modifica el perfil remoto para superar la validación.

Manifiesto ignorado actualizado: clientRequestId y numeración conservados;
companyTarget=TOKEN_PRIMARY, metadata.alanubeCompanyId omitido, legalName=FULLTECH,
companyAuthorizationRef ligada al hash de este GET. No payload final autorizado.

### Pendientes exactos y siguiente acción

1. En el portal Sandbox suministrado, revisar el perfil del id/RNC indicado:
   confirmar si FULLTECH es el nombre esperado para la simulación y obtener la
   dirección válida. No guardar cambios remotos. Si también muestra `address`,
   usar el borrador reducido ECF_ALANUBE_E32_PROVIDER_CONFIRMATION_REQUEST.md.
   No hace falta reconfirmar entrega del paquete, principal/asociada ni ULID.
2. API UAT 127.0.0.1:4002 **no estaba escuchando** y OPERATOR_JWT_PRESENT=False.
   El login normal requiere POST **local** /auth/login. La autorización recibida
   dice ningún POST; no se ejecutó login ni se abrió otra sesión. El operador
   dispone de los pasos y el bloque sin eco en el runbook. No usar un ID como
   sustituto del JWT ni firmar tokens artificiales, activar licencias o seeds.
3. Tras validar la dirección y el login, revisar la configuración del tenant
   autenticado (SANDBOX, sin producción, E32, secretRef y perfil de principal),
   y verificar no colisión local/disponibilidad en portal del candidato.
   Son comprobaciones pendientes, no fallos demostrados del proveedor.

Preflight repetido: BLOCKED; WORKTREE/UAT_DATABASE/PERSISTENCE_SCHEMA/
SANDBOX_ENVIRONMENT/SWITCHES_DISABLED/SINGLE_TRIAL_UNUSED/E32_MANIFEST/
NUMBERING_AUTHORIZATION/OPERATION_IDENTITY=true. E32_PAYLOAD=false por dirección
null; OPERATOR_CONTEXT=false. Las comprobaciones por tenant no se evaluaron sin
JWT (company/secretRef/número). authenticatedRequests=0 describe **ese preflight**;
esta tarea realizó **1 GET real** autorizado, **0 POST** de cualquier tipo.

Validaciones actuales: 35 pruebas E32 PASS, contratos POST/GET --check MATCH,
base fullpos_alanube_uat y slot FIRST_E32_SANDBOX con 0 filas, interruptores
desactivados. Solo se modifican documentación/manifiesto; no código backend,
schema, migraciones, auth, licencias, POS ni Flutter. Sin emisión ni consumo de
secuencias por este flujo, sin cambios remotos, producción, commit/push/merge/deploy.
No se volverá a ejecutar GET /company bajo esta autorización ya utilizada.

## Registro anterior a la consulta real (histórico donde discrepe)

## Resultado vigente tras la aclaración del usuario — 2026-10-14

Actualización posterior: el usuario identifica ese RNC como Alanube Soluciones
SRL en la propuesta comercial; el ejemplo oficial E32 lo corrobora como
**Alanube Soluciones S.R.L.** Se completó legalName del borrador, sin sustituir
el RNC. Sigue sin verificarse **address** y el vínculo main/associated de esta
credencial. No se revisó la propuesta original ni el portal autenticado.
El runbook ahora incluye login UAT real con password en prompt seguro y JWT
solo en memoria, más procedimiento GET /company para una autorización futura.
No se ejecutó login, llamada autenticada Alanube ni emisión en esta actualización.
Validaciones repetidas para esta actualización documental: 35 pruebas E32 PASS;
6 bloques PowerShell del runbook analizados, 0 errores de sintaxis (sin ejecutar
login ni envío); ambos generadores contractuales --check MATCH; git diff --check
PASS. Preflight actualizado BLOCKED, numbering/identidad de operación correctos,
actor no autenticado y manifiesto incompleto. Puede calcular hash de un borrador
inválido: no equivale a payload validado ni se escribe payload.json final.

**BLOCKED**, exclusivamente por contexto operativo incompleto. Esta sección
sustituye las conclusiones del registro histórico inferior; no se requieren
certificación productiva, registro de compañía nueva ni confirmación repetida
del paquete Sandbox entregado por Alanube.

- HECHO / USER_CONFIRMED: Alanube entregó oficialmente Sandbox DOM, RNC
  132109122, secuencias 9805001–9806000, vencimiento 2028-12-31, token y portal.
  No se abrió el archivo privado original ni se autenticó nuevamente el token.
- HECHO / fuente pública: el schema POST E32 exige encf de 13 caracteres;
  su ejemplo E320000000005 y el ejemplo E320000016202 del changelog muestran
  E32 seguido de diez dígitos. Derivación técnica del rango suministrado:
  E320009805001–E320009806000. Se consignó E320009805001 como candidato en
  el manifiesto ignorado, preservando su UUID. Esto no reserva numeración,
  no demuestra disponibilidad remota ni afirma consumo en el portal.
- HECHO / VERIFIED_IN_CODE: selección explícita TOKEN_PRIMARY omite company;
  selección asociada conserva ULID obligatorio. Un manifiesto antiguo sin
  selector conserva el comportamiento asociado. Primaria con id contradictorio
  se rechaza. GET /invoices/{id} para primaria y /idCompany/{idCompany} para
  asociada. No se infiere cuál corresponde a esta credencial.
- HECHO / VERIFIED_BY_TEST: respuesta sin companyIdentification puede
  correlacionarse por id/e-NCF y contexto de la petición; un RNC presente que
  contradiga el manifiesto se rechaza. Correlación no autentica aceptación fiscal.
  Las evidencias permanecen en cuarentena y el documento en UNKNOWN_RESULT.

### Únicos pendientes para completar el preflight

1. **OPERATOR_CONTEXT**: el preflight ejecutado no obtuvo un JWT de acceso UAT
   válido. El operador debe cargarlo localmente sin eco, siguiendo el runbook.
   Se valida con JwtStrategy real: sesión/usuario/empresa/membresía/ADMIN/licencia.
   No se crea un JWT artificial ni se altera una licencia para avanzar.
2. **Manifiesto del emisor**: address sigue null; legalName ya está corroborado
   por usuario y fuente pública. Confirmar dirección de prueba y si el RNC es
   la empresa principal del token. En ese caso usar TOKEN_PRIMARY y eliminar
   metadata.alanubeCompanyId; si es asociada, proporcionar el ULID verificado.
   No se toma un nombre, dirección o ULID de un ejemplo como identidad autorizada.
3. Con ese contexto, verificar configuración **del tenant autenticado**:
   SANDBOX, productionEnabled=false, allowedTypes incluye E32, estado local
   AUTHORIZED_SANDBOX y referencia protegida. El estado local no es certificación
   DGII. Para primaria, alanubeCompanyId debe ser null. Verificar no colisión
   local y revisar en portal el candidato no consumido antes de aprobarlo.

TEST_COMPANY_CONFIRMED, SECRET_REFERENCE y NUMBER_UNUSED_LOCALLY dieron false
porque no se pudo evaluar su tenant sin operador autenticado: **no prueban**
credencial incorrecta, colisión de número ni bloqueo nuevo de Alanube.
NUMBERING_AUTHORIZATION, UAT_DATABASE, PERSISTENCE_SCHEMA, WORKTREE,
SWITCHES_DISABLED y SINGLE_TRIAL_UNUSED sí dieron true. Resultado BLOCKED,
authorizationGranted=false, authenticatedRequests=0; el payload sigue inválido.
No hay aún un documento final listo para autorizar.

### Candidato y validaciones actuales

Candidato: RNC 132109122, e-NCF E320009805001 (no consumido por este flujo),
contado/paymentType=1, incomeType=1, fecha actual al ejecutar, dos líneas
sintéticas: bien 100.00 + ITBIS 18.00 y servicio exento 50.00; total **168.00 DOP**.
Sin comprador identificado por estar bajo el umbral E32 documentado. Dirección
y vínculo de la credencial pendientes; no se generó payload.json final ni consentimiento.

Comandos ejecutados tras la corrección:

| Comando | Resultado |
| --- | --- |
| npm --workspace apps/api test -- --testPathPatterns=e32-sandbox.spec | 35 PASS |
| ./scripts/isolated-uat/test-ecf-postgres.ps1 | 88 PASS, solo datos sintéticos y wire MOCK_ONLY |
| npm --workspace apps/api test | 975 PASS, 96 omitidos: 88 PG ejecutados aparte + 8 opt-in ajenos |
| npm run api:build | PASS, Prisma generate 5.22 y tsc |
| npx prisma validate (apps/api, entorno UAT importado) | PASS |
| node scripts/isolated-uat/prepare-alanube-contracts.cjs --check | MATCH |
| node scripts/isolated-uat/prepare-e32-query-contracts.cjs --check | MATCH |
| ./scripts/isolated-uat/e32-sandbox-preflight.ps1 | BLOCKED esperado, sin red autenticada |
| git diff --check | PASS; advertencia LF/CRLF en schema previo |

SELECT current_database() verificó fullpos_alanube_uat; slot FIRST_E32_SANDBOX:
**0 filas**. Sin migraciones nuevas en esta corrección. Los tests retienen sus
fixtures MOCK_ONLY. No POST, GET autenticado, emisión, commit/push/merge/deploy,
cambio de producción, POS, Flutter, auth ni licencia. Worktree/rama/HEAD siguen
los indicados abajo. Se conservaron los cambios locales anteriores.
Inspección segura del entorno: OPERATOR_JWT_PRESENT=False, binding Docker
127.0.0.1:56550, interruptores desactivados. Escaneo focalizado de los 13 archivos
fuente/documentales modificados: 0 coincidencias de claves privadas, JWT literales
o URL PostgreSQL con contraseña; no se leyeron archivos de credenciales.

Archivos de implementación de esta corrección: sandbox/e32-sandbox.policy.ts,
e32-sandbox.cli.ts, e32-sandbox.wire.ts, e32-sandbox.service.ts,
e32-sandbox.spec.ts y documents/ecf-e32-trial-postgres.integration-spec.ts
(todos bajo apps/api/src/ecf). Documentación: este informe, runbook, borrador
de consulta, master, next_steps, provider_blockers y first_sandbox_issuance_plan.
Artefacto local ignorado: artifacts/e32-first-trial/manifest.json.

Fuentes: [POST E32](https://developer.alanube.co/reference/createinvoices),
[secuencias y ejemplo E32](https://developer.alanube.co/changelog/api-fe-dom-actualizaci%C3%B3n-de-gesti%C3%B3n-de-secuencias),
[GET principal](https://developer.alanube.co/reference/checkinvoices),
[GET asociada](https://developer.alanube.co/reference/checkinvoicesbycompany).
El esquema fijado del POST no requiere company y lo describe para una compañía
diferente de la principal. No se implementaron reintentos por sequenceConsumed.

## Registro histórico anterior a la última aclaración (superado donde discrepe)

2026-10-14. **BLOCKED** por confirmación externa y contexto/configuración operativa.
Código local preparado y probado; ningún envío real ejecutado ni autorizado.
Worktree FULLPOS-ECF-ALANUBE, feature/ecf-alanube; HEAD
6b3e38ed57bc53f9a55e66cf2eccf315afffd3f1, cambios anteriores preservados.

## Estado concreto

| Componente | Estado real |
| --- | --- |
| Contrato POST E32 | Schema DOM oficial previo fijado por hash; Ajv y reglas locales existentes preservados |
| Mapper | Campos de la prueba comparados contra schema; no diferencias nuevas que exijan cambiar mapper |
| Datos sintéticos | Factory fija: dos líneas, 150.00 base, 18.00 ITBIS, 168.00 total, DOP |
| Payload final | Pendiente de compañía/identidad y e-NCF autorizados; no se inventó número ni id |
| Empresa | No confirmada por Alanube; no se infiere de la credencial ni de un ejemplo público |
| Credencial | Archivo DPAPI existente y secretRef global configurado; no descifrado ni autenticado nuevamente |
| Numeración | Rango numérico local, vigencia presente, asignación completa a E32 sin confirmar |
| Transporte | Clase exclusiva E32/CLI, real preparada y bloqueada por autorización, runtime UAT y validación; fetch solo mocked en tests |
| Idempotencia | Identidad v2 + manifest/payload inmutables + claim global previo a red; máximo un POST, sin retry |
| Consulta | GET E32 por id/idCompany implementado, schema propio oficial y dependencias resueltas/fijadas; no ejecutado realmente |
| Conciliación | Correlación de id/RNC/e-NCF y observaciones en cuarentena; siempre conserva estado fiscal desconocido |
| Evidencia | Hash de bytes de respuesta, metadata mínima, historial inmutable; sin raw persistido ni aceptación fiscal |
| Operador | Requiere JWT UAT de acceso válido y JwtStrategy existente: sesión, usuario, empresa, membresía, rol y licencia |
| Webhook | Público deshabilitado; no necesario para esta primera E32 con consulta directa |
| Emisión | Cero; interruptores/configuración persistente no activados |

## Bloqueos restantes, sin requisitos exclusivos de E34

| Bloqueo | Impacto | Falta | Responsable | Acción |
| --- | --- | --- | --- | --- |
| Compañía Sandbox | No hay destino empresarial confirmado | company.id/idCompany, identidad y habilitación E32 | Alanube + responsable FULLTECH | Enviar el borrador de confirmación y conservar respuesta |
| Numeración E32 | No existe e-NCF candidato autorizado | Rango E32 completo, número disponible y vigencia | Alanube | Confirmación escrita; no transformar automáticamente rango numérico |
| Contexto UAT/configuración específica | No se verifica tenant/permiso ni secretRef de la empresa | JWT UAT vigente y configuración Sandbox de ese tenant | Operador FULLTECH | Usar sesión existente; completar manifiesto y config al recibir confirmación, sin alterar licencias |
| Consentimiento del envío | Ningún POST autorizado | Aprobación expresa ligada al manifest hash, un POST y máximo un GET | Usuario | Solo después de READY_FOR_AUTHORIZATION y revisión del payload |

No se exige saldo de original E34, sus reglas de crédito, webhook público ni
certificación productiva DGII para este ensayo E32. AUTHORIZED_SANDBOX en la
configuración es un control local que debe respaldar el operador; no representa
certificación productiva ni puede asignarse sin evidencia para obtener READY.

## Origen y verificación del perfil existente

HECHO: ECF_ALANUBE_SANDBOX_CREDENTIALS.md y .env.alanube.uat.local.example ya
registran RNC 132109122, rango numérico 9805001–9806000 y 2028-12-31. El documento
histórico atribuye esos valores al paquete Sandbox recibido (HISTORICAL_REPORT).
El usuario confirmó ahora que son configuración local pendiente, sin confirmación
documental adicional. No se abrió FULLTECH.txt ni se verificó el adjunto original.

Inspección local sin imprimir valores: RNC/formato válido, rango no expresado
como e-NCF E32 completos, vencimiento/formato vigente y prefijo sin configurar.
Se copió al borrador ignorado solo el RNC/fecha ya configurados, sin elevarlos
a evidencia externa; los e-NCF e identificadores siguen pendientes. El UUID
clientRequestId se creó una vez y se conserva. No hay trial SANDBOX real preparado
en base ni slot FIRST_E32_SANDBOX consumido.

## Documentación oficial consultada (sin autenticación)

- [POST E32](https://developer.alanube.co/reference/createinvoices): request,
  response y umbral 250000 DOP; respuesta inicialmente síncrona puede pasar a
  procesamiento asíncrono. Nunca reenviar ante AEP2006/timeout/resultados incompletos.
- [GET E32](https://developer.alanube.co/reference/checkinvoices) y
  [GET por compañía](https://developer.alanube.co/reference/checkinvoicesbycompany):
  endpoints y esquemas distintos del POST. Referencias del schema GET apuntan a
  /purchases/{id}; se recuperó el [schema DOM referenciado](https://developer.alanube.co/reference/checkpurchases),
  no reglas fiscales de E41 ni de otro país. Algunas referencias usan %7B/%7D;
  el generador las decodifica y resuelve solo contra fuentes DOM fijadas.
- [Introducción DOM](https://developer.alanube.co/docs/getting-started): Bearer
  suministrado por Alanube y base Sandbox. No prueba identidad/habilitación actual.
- [Certificación](https://developer.alanube.co/docs/proceso-de-certificaci%C3%B3n):
  distingue producción de simulaciones Sandbox a nombre de Alanube; no afirma
  que este token/RNC/rango concreto esté habilitado. No se consultó DGII.
- [Consulta de empresa](https://developer.alanube.co/reference/getcompany-1):
  GET /company/{id} retorna información, no se ejecutó. La documentación pública
  no identifica nuestra compañía ni confirma su rango. No se hizo POST /company.
- [Secuencias DOM](https://developer.alanube.co/changelog/api-fe-dom-actualizaci%C3%B3n-de-gesti%C3%B3n-de-secuencias):
  informa sequenceConsumed; no se infiere permiso para reutilizar una secuencia.

Se descartaron resultados de búsqueda COL/otros países. No se añadió un header
Idempotency-Key sin contrato DOM confirmado. El bloqueo contra repetición es local
y persistente; no se atribuye garantía de idempotencia al proveedor.

Hashes de fuentes nuevas: checkinvoices
F55DB04BD29C0EA53A51219492F8F3A573652137F426A0CBCEBB9BC15EAB4201;
checkinvoicesbycompany
0E783B1977A7545C83058B689186385ED78CC8697F9A036FF3364D6A994941E2;
dependencia checkpurchases
320ADCB00390315385F64DEF0AF0486E0E18E68C37635DFA2C9739C4576AF426.
POST E32 previo permanece 483A7220F503AF4FAEEE1D42CF2124449CF8524105F94172D633099CEAF836DF.

## Comparación del payload de la prueba

| Campos | Contrato / implementación |
| --- | --- |
| company.id | ULID explícito del proveedor; no UUID local ni fallback a cuenta principal |
| idDoc.encf/incomeType/paymentType | e-NCF E32 explícito, ingreso 1 y contado 1 sujetos a revisión del candidato |
| sender.rnc/companyName/address/stampDate | Identidad confirmada y fecha del ensayo; sin datos de clientes reales |
| totals | totalTaxedAmount/i1AmountTaxed=100; itbisS1=18; itbisTotal/itbis1Total=18; exemptAmount=50; totalAmount=168 |
| itemDetails | Dos líneas sintéticas: indicador gravado 1 y exento 4, bien 1/servicio 2, cantidad 1, precios/importes 100 y 50 |
| buyer/otherCurrency | Omitidos para este subconjunto bajo umbral en DOP; no se inventa un campo currency |

Ajv valida esquema oficial sin coerción. Decimal y núcleo fiscal comprueban
totales. No se declara conformidad fiscal integral por un JSON válido.

## Persistencia, seguridad y recuperación

Nueva migración SOLO UAT: 20261014220000_ecf_e32_single_trial. Dos tablas nuevas
de trial/eventos, FK por tenant, payload/manifest inmutables, historial append-only.
Slot SANDBOX global FIRST_E32_SANDBOX; MOCK_ONLY por empresa, incompatible con wire
real. Claim irreversible PREPARED→CLAIMED antes de red, luego UNKNOWN_RESULT o
RESPONSE_RECORDED. Incluso un fallo antes de enviar obliga a revisión; no reset.

Backup artifacts/uat-backups/ecf_before_e32_readiness_20261014.dump: 781532 bytes,
SHA-256 6D0B121A9E80472B4F466E091AECC7BCC489845148B81558A3A463E549A7DF22.
Identidad y binding 127.0.0.1:56550/fullpos_alanube_uat comprobados; lectura completa
pg_restore --file=/dev/null; ensayo de SQL ROLLBACK y deploy PASS. No restauración
a otra base, db push, migrate reset ni alteración de SQL aplicado. No se aplicó
drift histórico; el diagnóstico no mostró diferencias de las tablas nuevas.

Primer binding remoto: solo documento nuevo reclamado, respuesta 201 conforme,
id ULID/RNC/e-NCF coincidentes y sin asociación local contradictoria. No reescribe
documentos históricos. Hash de respuesta se conserva antes de binding/receipts/GET.
El resultado fiscal siempre UNKNOWN_RESULT: ni legalStatus ni HTTP autorizan
DGII_ACCEPTED. Sin id tras timeout no se puede consultar automáticamente; escalar
al proveedor con identidad/fecha/hash, detener POST y no adivinar/reutilizar número.

El wire exclusivo no se registra como transporte general. CLI verifica raíz,
rama, Docker, DB, JWT real, tenant y consentimiento con hash/actor/TTL ≤30 minutos,
1 POST/1 GET. Cambios de flags solo dentro del hijo después de consentimiento;
no cambia .env, configuración de empresas ni emisión productiva. La API normal
y E34 siguen bloqueados. No se arranca Nest ni scheduler; licencia se valida
mediante servicios existentes sin modificarlos. Preflight no descifra DPAPI.

## Validaciones ejecutadas

```text
npm --workspace apps/api test -- --testPathPatterns=e32-sandbox.spec
PASS: 31 tests locales E32 (incluye JWT, preflight, GET, wire/timeout/seguridad).
npm --workspace apps/api test -- --testPathPatterns=src/ecf
PASS: 232 tests, 87 PostgreSQL omitidos aquí y ejecutados aparte.
./scripts/isolated-uat/test-ecf-postgres.ps1
PASS: 87 tests PostgreSQL (19 del trial E32, 68 previos).
npm --workspace apps/api test
PASS: 971 tests, 95 omitidos (87 PostgreSQL aparte; 8 opt-in ajenos pendientes).
npm run api:build
PASS final: Prisma generate 5.22.0 + tsc.
npm --workspace apps/api exec -- tsc -p tsconfig.build.json
PASS separado.
npx prisma validate / npx prisma migrate status
PASS: 36 migraciones al día, exclusivamente UAT.
node scripts/isolated-uat/prepare-alanube-contracts.cjs --check
PASS: contratos previos intactos.
node scripts/isolated-uat/prepare-e32-query-contracts.cjs --check
PASS: GET y dependencias fijados.
./scripts/isolated-uat/e32-sandbox-preflight.ps1
BLOCKED esperado por configuración/contexto/confirmaciones pendientes, salida no cero.
Smoke compilado del preflight con fetch bloqueado
PREFLIGHT_NETWORK_CALLS=0; sin autenticación ni emisión.
```

Tests externos solo mocks. PostgreSQL comprueba idempotencia, locks/concurrencia,
slot global, tenant/FK, historial, recuperación y persistencia; ningún mock es
evidencia Alanube/DGII. Correcciones propias: nullable narrowing TypeScript y
fixtures que usaban UUID de compañía e incomeType ausente; corregidos, sin
relajar schemas. Auth CLI se endureció antes de cierre para exigir JWT/session.

El generador detectó referencias GET ausentes antes de completarse: se recuperó
la dependencia oficial DOM y se fijó su hash, sin sustituirla por campos supuestos.
Escaneo final: 137 archivos, 0 coincidencias en patrones de claves privadas, JWT
y URLs PostgreSQL con credenciales; no es garantía exhaustiva. git diff --check
PASS. Rutas tradicionales, Flutter, auth y license sin diff; solo se reutilizan
sus validadores. Checksum del SQL nuevo coincide con la migración aplicada.

Auditoría UAT de cierre: 82 trials MOCK_ONLY y 284 eventos; 100 empresas fixture
locales de ejecuciones repetidas (incluida la inicial fallida), retenidas sin
purgar ni desactivar triggers. Slot FIRST_E32_SANDBOX: 0 filas. No representan
altas externas ni emisiones. El smoke compilado incluso con --execute-once sin
requisitos terminó BLOCKED y PREFLIGHT_NETWORK_CALLS=0.

Herramientas: terminal/PowerShell, git, rg, apply_patch, Node/npm/Python, Jest,
Prisma/TypeScript, Docker/psql/pg_dump/pg_restore y web pública oficial. Sin
subagentes ni herramientas de UI. No se ejecutó el script de envío real.

## Archivos de este bloque

```text
apps/api/prisma/schema.prisma
apps/api/prisma/migrations/20261014220000_ecf_e32_single_trial/migration.sql
apps/api/src/ecf/alanube/alanube-schema-validator.ts
apps/api/src/ecf/alanube/contracts/alanube-e32-query.generated.ts
apps/api/src/ecf/documents/ecf-document-idempotency.service.ts
apps/api/src/ecf/documents/ecf-e32-trial-postgres.integration-spec.ts
apps/api/src/ecf/sandbox/e32-sandbox.policy.ts
apps/api/src/ecf/sandbox/e32-sandbox.wire.ts
apps/api/src/ecf/sandbox/e32-sandbox.service.ts
apps/api/src/ecf/sandbox/e32-sandbox.cli.ts
apps/api/src/ecf/sandbox/e32-sandbox-operator.ts
apps/api/src/ecf/sandbox/e32-sandbox.spec.ts
scripts/isolated-uat/download-alanube-e32-query-contracts.ps1
scripts/isolated-uat/prepare-e32-query-contracts.cjs
scripts/isolated-uat/init-e32-sandbox-trial.cjs
scripts/isolated-uat/e32-sandbox-preflight.ps1
scripts/isolated-uat/e32-sandbox-send-once.ps1
docs/ECF_ALANUBE_E32_SANDBOX_READINESS.md
docs/ECF_ALANUBE_FIRST_E32_SANDBOX_RUNBOOK.md
docs/ECF_ALANUBE_E32_PROVIDER_CONFIRMATION_REQUEST.md
docs/ECF_ALANUBE_MASTER_CONTEXT.md
docs/ECF_ALANUBE_NEXT_STEPS.md
docs/ECF_ALANUBE_PROVIDER_BLOCKERS.md
docs/ECF_ALANUBE_FIRST_SANDBOX_ISSUANCE_PLAN.md
```

No dependencias nuevas. .gitignore/AGENTS/package files/otros cambios previos no
pertenecen a este bloque. Draft y backup bajo artifacts/ ignorado. No producción,
POS/Flutter/offline/licencias/NCF/ITBIS ni taxEnabled/ncfEnabled modificados.
Sin commit/push/merge/reset/clean/stash/rebase/deploy ni otros worktrees.

Siguiente acción: el usuario envía manualmente el
[mensaje E32](ECF_ALANUBE_E32_PROVIDER_CONFIRMATION_REQUEST.md); con respuesta
se completa configuración/manifiesto y contexto JWT UAT, se repite preflight y
solo entonces se solicita autorización ligada al hash. Ver [runbook](ECF_ALANUBE_FIRST_E32_SANDBOX_RUNBOOK.md).
