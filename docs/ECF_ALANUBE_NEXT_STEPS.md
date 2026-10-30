# Continuidad e-CF Alanube

## Aislamiento UAT: base de datos efímera para pruebas (2026-10-15)

La UAT histórica `fullpos_alanube_uat` (127.0.0.1:56550) queda **intacta y solo
de lectura** para el operador; las suites PostgreSQL se ejecutan sobre una base
**efímera exclusiva** y dejan de acumular fixtures en la histórica.

- Contenedor efímero `fullpos_alanube_ecf_test_postgres` (127.0.0.1:56551,
  volumen `fullpos_alanube_ecf_test_postgres_data`, `restart: no`).
- Base/usuario `fullpos_alanube_uat_test` / `fullpos_alanube_uat_test_user`;
  identificador `ECF_TEST_DB_MARKER=ECF_EPHEMERAL_TEST_DB`.
- Allowlist estricta `apps/api/src/ecf/ecf-local-target.ts`: solo loopback +
  (nombre, puerto) exactos. Se rechazan hosts remotos, producción, puerto/nombre
  erróneos, query/hash y protocolos no PostgreSQL.
- Scripts `scripts/ecf-test-db/`: `up.ps1`, `migrate.ps1`, `run-tests.ps1`,
  `verify.ps1`, `down.ps1`, `_test-common.ps1`. `down.ps1` destruye únicamente
  los recursos efímeros exactos y rechaza identificadores que solapen con la UAT
  histórica. `run-tests.ps1` compara los conteos de la UAT histórica antes y
  después y aborta si cambiaron.

Resultado verificado: suite completa **113/114 suites, 1161 PASS, 8 omitidas**
ejecutada íntegramente sobre la base efímera; conteos de la UAT histórica
**idénticos antes/después** (708 empresas / 568 trials / 3462 documentos); el
documento histórico sigue `HUMAN_REVIEW_REQUIRED`. 36 migraciones aplicadas al
esquema efímero y 3 triggers append-only presentes.

## Cobertura E32 de rechazo/estados/idempotencia verificada (2026-10-14)

Auditoría de pruebas E32 y cierre de huecos de cobertura, sin nuevas fases ni
arquitecturas. Sin POST/GET a Alanube, sin emisión, sin APPLY, sin tocar el
documento histórico conciliado (HUMAN_REVIEW_REQUIRED) ni producción.

Cubierto y verificado (unidad + PostgreSQL UAT sintético):
- Rechazo explícito: `legalStatus=REJECTED` se registra como observación
  (`E32_OBSERVED_REJECTED`) → HUMAN_REVIEW_REQUIRED, `fiscalSnapshot` null, sin
  liberar secuencia ni reintentar; HTTP 200 no lo convierte en rechazo ni aceptación.
- Estado operativo vs legal (matriz): REGISTERED/FINISHED/WAITING_RESPONSE +
  ACCEPTED o ACCEPTED_WITH_OBSERVATIONS → ACCEPTED; + REJECTED → REJECTED;
  TO_SEND/WAITING_RESPONSE sin legalStatus → PENDING; REGISTERED/TO_NOTIFY/FINISHED
  sin legalStatus → UNKNOWN (conservador); `status` fuera del enum oficial se
  rechaza por schema (`OFFICIAL_SCHEMA`).
- HTTP 200/201 nunca equivalen a aceptación fiscal (assessment, interpreter, wire, PG).
- Timeout/desconexión/unknown: UNKNOWN sin reintento automático; latch consumido no
  rehabilita POST; crash tras claim no restaura permiso.
- Secuencia consumida no se reutiliza (slot global single-use, sin reset/borrado).
- Correlación empresa/RNC/e-NCF/operación/id remoto y conflicto remoto.
- Reglas de compatibilidad observadas sin alterar el contrato oficial.
- HUMAN_REVIEW_REQUIRED y UNKNOWN_RESULT no se promueven automáticamente a
  DGII_ACCEPTED ni PROVIDER_ACCEPTED (máquina de estados + PostgreSQL).

Cambios mínimos aplicados (solo pruebas y esta documentación):
- `e32-response-assessment.spec.ts`: rechazo explícito + matriz operativo/legal +
  estado fuera de enum.
- `ecf-document-state-machine.spec.ts`: HUMAN_REVIEW_REQUIRED/UNKNOWN_RESULT no
  auto-promocionan; PROVIDER_ACCEPTED exige evidencia.
- `ecf-e32-trial-postgres.integration-spec.ts`: rechazo a nivel de servicio.
- `e32-reconciliation-executor.integration-spec.ts`: la prueba de preservación
  histórica distingue el estado previo (UNKNOWN_RESULT) del posterior autorizado
  (HUMAN_REVIEW_REQUIRED) sin debilitar invariantes.

Errores reales detectados y corregidos: 1 (prueba de preservación con premisa
pre-conciliación; actualizada al estado post-conciliación autorizado).

Pruebas: 1161 backend PASS (8 omitidas; incluye 108 PostgreSQL UAT) y build/tsc +
Prisma validate PASS. Riesgo pendiente: clasificar REGISTERED/TO_NOTIFY sin
legalStatus como UNKNOWN es conservador (evita falsas aceptaciones) pero puede
exigir conciliación de documentos aún en proceso; documentado, no modificado.

GO para avanzar a E31/E34 con la misma postura; NO-GO para emisión real o
certificación.

## Compatibilidad PASS; propuesta de revisión humana lista

Perfil ALANUBE_DOM_E32_SANDBOX_OBSERVED_V1 implementado sin cambiar schemas.
El GET local cifrado pasa compatibilidad/correlación/hash; contrato publicado
sigue FAIL registrado. Firma se conserva sin zona/instante, trackId null sin UUID
inventado y fecha fiscal exacta.98focalizadas/94PG/1039backend y build/Prisma PASS.
Propuesta artifacts/e32-first-trial/recovery-get-reconciliation-proposal.json:
UNKNOWN_RESULT → HUMAN_REVIEW_REQUIRED, vincular id01M4Y3DEPXXG27G8BNQGMNQ04B /
E320009805001, registrar ACCEPTED observado/consumo true y reglas; conservar trial
consumido y fiscalSnapshot. Archivo generado dos veces idéntico, sin aplicar DB.
Próxima acción: autorización separada para esa propuesta, seguida de preparación
y validación del ejecutor transaccional autenticado; no hay --apply/bypass.
GO de preparación para revisión humana; no aceptación DGII ni nueva emisión.
Histórico sigue UNKNOWN_RESULT, sin nuevas llamadas Alanube o cambios producción/POS.
Detalle de riesgos/propuesta/rollback y comandos locales en readiness y runbook.

## Evidencia GET recuperada: identidad PASS; contrato FAIL

Único GET autorizado2026-10-14T21:16:52.201Z HTTP200 al id01M4Y3DEPXXG27G8BNQGMNQ04B.
FINISHED/ACCEPTED, sequenceConsumed=true, E320009805001 y RNC132109122 exactos.
Nueva evidencia separada del POST, respuesta completa cifrada DPAPI y hash
b607a039a5faea11eb189ccfbcb7df6e8f5c6b88f61fbdfbf8d4cc43a2d61b3b verificado.
No repetir GET ni borrar recovery-get-claim.json.0 nuevas emisiones.
Schema oficial actual igual al snapshot; falla stampDate (timestamp donde espera
date), trackId=null (espera uuid string), signatureDate DD-MM-YYYY HH:mm:ss
(espera date-time RFC3339). No inventar timezone ni relajar validación.
Diagnóstico READ_ONLY ahora repite la validación desde el archivo cifrado sin red;
cadena de evidencia/correlación PASS. Histórico DB intacto UNKNOWN_RESULT,
1POST/0GET en tablas; el GET externo nuevo consta en journal local, no DB.
NO-GO para conciliación persistente automática. Readiness contiene evidencia y
runbook propuesta transaccional de revisión humana limitada al documento, rollback
y pruebas; exige resolver contrato y autorización separada antes de aplicar.

## Conciliación: corrección local verificada; histórico sin modificar

runOnce marcaba UNKNOWN_RESULT incondicionalmente antes de interpretar el body.
Corregido: diagnóstico estricto por checks + observación de resultado/sequence;
respuesta completa/correlacionada requiere revisión humana sin falsa aceptación
DGII.60 focalizadas/94PG/1001backend y build/Prisma PASS. Contrato público actual
coincide con snapshot; REGISTERED y ACCEPTED son compatibles.
El submotivo histórico de correlación no puede recuperarse porque faltan body
completo y errores de validación; no adivinarlo. Documento/trial original siguen
UNKNOWN_RESULT,1POST/0GET, chainMatches=true. Diagnóstico seguro repetible:
e32-reconciliation-dry-run.cjs (READ_ONLY, sin --apply ni HTTP). Ver runbook para
evidencia faltante y propuesta condicionada a autorización separada. NO-GO para
conciliar persistentemente o realizar otra emisión. No hubo llamadas API Alanube.

## Resultado vigente: primera E32 Sandbox ACCEPTED; no repetir

2026-10-14T20:59:46.475Z: único POST autorizado, HTTP201,
E320009805001, id01M4Y3DEPXXG27G8BNQGMNQ04B, status REGISTERED,
legalStatus ACCEPTED, sequenceConsumed=true. Operación
959afb04-b593-4282-b40d-212ed800b507.1 POST,0 GET,0 reintentos.
Autorización consumida. No volver a ejecutar -ExecuteAuthorizedFirstE32 ni
e32-sandbox-send-once para esta operación. No reutilizar su e-NCF.

Pendiente concreto: la validación conjunta de schema/correlación no permitió
vincular automáticamente la respuesta real. Localmente documento/trial quedan
UNKNOWN_RESULT con latch consumido; no significa rechazo del proveedor.
Conservar controles y revisar conciliación con la evidencia segura del POST.
No afirmar la causa exacta: no está identificada con los campos conservados.
Ver sección vigente ECF_ALANUBE_E32_SANDBOX_READINESS.md y artifacts/e32-first-trial/
real-post-observation.json. No DGII ni producción; emisión general sigue apagada.
Las secciones siguientes son antecedentes, no autorizaciones vigentes.

## Preparación final: READY_WITH_PROVIDER_UNCERTAINTY

Preflight real2026-10-14T20:43:22Z READY_FOR_AUTHORIZATION,21 checksPASS,login201.
Usuario autoriza dirección ficticia propuesta, seleccionada explícitamente en
manifest con etiqueta no verificada por proveedor y scope exclusivo de tenant
sintético/UAT/Sandbox. Payload168.00 validado; 41 focalizadas/89PG/982backend y
build/Prisma PASS. Ver sección vigente de readiness para resumen/fingerprints.
No emisión ni llamadas Alanube nuevas, slot real vacío, flags/config desactivados,
certificación NOT_STARTED. Solicitar autorización expresa para1 POST Sandbox
sin retry y máximo1 GET correlacionado, indicando incertidumbre de dirección.
No ejecutar envío hasta recibir consentimiento separado. Sesión/fecha/preflight
deben estar vigentes al ejecutar; no usar JWT histórico ni extender permisos.

## Estado final local: configuración PASS, solo dirección pendiente

2026-10-14T20:17:55Z: login201 y PATCH /ecf/config200 completados con ADMIN
autenticado. Tenant sintético configurado SANDBOX, emisión desactivada,
certificación NOT_STARTED. Auditorías confirmadas, NCF/impuestos intactos.
Preflight BLOCKED exclusivamente E32_PAYLOAD por address=null. Todos los demás
checks PASS. No repetir configuración ni /company. Única acción externa: obtener
dirección/regla válida Sandbox del borrador preparado. Después completar address,
revalidar sesión/preflight y solicitar consentimiento fiscal separado. No envío.

## Cierre del tenant en curso

Ver sección actual de readiness. Build/981 backend/88 PG/40 focalizadas y Prisma
PASS. Preparación Sandbox ya no exige falsear certificación: NOT_STARTED se
conserva, emisión desactivada. PATCH oficial de configuración preparado con
backup, JWT/ADMIN y validación del tenant sintético. Ventana de login abierta,
pendiente entrada del operador; no declarar PATCH aplicado aún. Dirección
sender.address sigue null: falta regla/dato permitido Sandbox, no se inventa.
Consulta concreta actualizada en borrador existente; no enviar automáticamente.

## Acceso UAT completado: siguiente acción fiscal local

ADMIN_ACCESS_GO: alanube.admin@fullpos.local, contraseña definida por operador
sin eco/archivos. Login HTTP201 y OPERATOR_CONTEXT=true. Empresa sintética nueva
STANDARD/TRIAL siete días hasta 2026-10-21; OWNER/ACTIVE y licencia comprobados.
API127.0.0.1:4002 disponible. Ver ECF_ALANUBE_UAT_ADMIN_ACCESS.md.
Preflight E32 BLOCKED: falta configuración e-CF del tenant recién creado y
dirección válida Sandbox. No confundirlo con acceso pendiente ni repetir login
para ocultarlo. Próxima tarea: preparar configuración fiscal local de esta empresa
sintética con emisión apagada, más obtener dirección de pruebas. No contactar
Alanube/emitir bajo autorización de acceso. No repetir -CreateSyntheticAdmin.

## Acción inmediata: completar ventana de login UAT

Actualización: el intento interactivo terminó HTTP401 Invalid credentials,
sin JWT. El identificador ADMIN configurado por defecto no existe en esta UAT
(diagnóstico booleano, sin exponerlo). Confirmar si el operador dispone de otro
ADMIN existente; no repetir con credenciales Alanube ni sustituir login por ID.
Si no hay cuenta UAT, preparar provisión sintética separada sin seeds implícitos.
Build completo PASS tras liberar solo nuestro PID31120; API reiniciada y
escuchando 127.0.0.1:4002/PID33860, Prisma validate PASS. Preflight BLOCKED.
Siguen pendientes controles por tenant; aún no puede declararse solo un bloqueo
externo. La dirección Sandbox sí es el único dato externo que falta.

API iniciada en 127.0.0.1:4002 y /health/db=200. Ventana PowerShell de
e32-operator-login-preflight.ps1 abierta, esperando entrada del ADMIN. Introducir
contraseña solo allí, nunca chat. Ver operator-preflight.json (solo datos seguros).
No cerrar validaciones de tenant hasta preflight autenticado. El usuario ya
autorizó POST de login local; no incluye POST externo. No repetir /company.
Factory Nest e-CF y enlace loopback corregidos; 237 e-CF/976 backend PASS.
Conservar FULLTECH/RNC confirmado. Único dato externo: dirección válida Sandbox.
Build completo pendiente de revalidar sin DLL Prisma ocupada; tsc PASS.

## Siguiente acción tras el GET real autorizado

GET /company consumido una vez, HTTP 200: principal confirmada,
RNC 132109122, id 01M3T6Y4R9BH35XGJ5PP12KV0T. Perfil devuelve name=FULLTECH y
address=address. **BLOCKED**: resolver esa dirección placeholder y confirmar el
nombre esperado de simulación en portal/soporte; borrador de consulta reducido.
No volver a preguntar si es principal/asociada ni sustituir RNC por FULLTECH.
Manifiesto TOKEN_PRIMARY actualizado con nombre observado y dirección null.
Luego ejecutar login ADMIN UAT del runbook (POST solo local, no ejecutado bajo
la prohibición de POST actual) y preflight. Sin JWT no se evalúa configuración
por tenant. 35 pruebas E32 PASS; preflight BLOCKED; slot real vacío, flags off.
No repetir GET bajo permiso ya consumido; ninguna factura autorizada.

## Acción vigente tras la confirmación oficial del paquete Sandbox

Última precisión: nombre corroborado **Alanube Soluciones S.R.L.** para RNC
132109122; borrador actualizado. Falta dirección y vínculo main/associated del
token. El runbook contiene pasos exactos de login UAT sin JWT en logs/archivos/
argumentos y procedimiento de un GET /company sujeto a autorización futura.
Usar portal Sandbox entregado para revisar esos datos; no inventar menús ni
dirección. El informe de fase 31 no conservó cuerpo y no resuelve el vínculo.

2026-10-14: **BLOCKED operativo**, no por certificación productiva. Revisar
ECF_ALANUBE_E32_SANDBOX_READINESS.md, sección vigente, y el runbook actualizado.
RNC/rango/vigencia ya confirmados por el usuario como entregados por Alanube.
Candidato con formato oficial: E320009805001; rango hasta E320009806000.
Faltan dirección del emisor, selección explícita empresa principal o
asociada y JWT de sesión ADMIN UAT vigente cargado localmente sin eco. Con ese
contexto comprobar configuración/secretRef del tenant y colisión local, más
disponibilidad en portal. No enviar una consulta redundante de certificación.
35 pruebas focalizadas, 88 PostgreSQL, 975 backend y build/Prisma PASS.
Slot Sandbox real vacío; cero llamadas autenticadas/emisiones. Sin migración
nueva en esta corrección. Una vez READY, presentar payload/hash y solicitar
autorización expresa para un POST y máximo un GET, sin reintentos.

## Registro previo (superado donde discrepe con la acción vigente)

## Siguiente acción vigente — primera E32

Código seguro de preparación terminado/probado; resultado actual BLOCKED.
Enviar manualmente ECF_ALANUBE_E32_PROVIDER_CONFIRMATION_REQUEST.md: confirmar
empresa Sandbox/idCompany y e-NCF E32 completo disponible con vigencia. El usuario
confirma que RNC/rango numérico locales aún NO están autorizados documentalmente.
No inventar prefijo ni identificadores, no abrir FULLTECH.txt ni llamar al API.

Con respuesta: completar manifiesto/config específica del tenant, usar JWT UAT
vigente (no seleccionar empresa por archivo) y ejecutar e32-sandbox-preflight.ps1.
Mantener licencia/permisos existentes; nunca fabricar JWT ni activar licencias.
Solo si READY_FOR_AUTHORIZATION revisar payload/hash y solicitar un POST E32 +
como máximo un GET. No ejecutar e32-sandbox-send-once.ps1 en la preparación.

Leer E32_SANDBOX_READINESS y FIRST_E32_SANDBOX_RUNBOOK para comandos, checks,
backup, migración y recovery-only sin red. Pruebas: 232 e-CF, 87 PG, 971 backend.
E34/webhook/certificación productiva no bloquean el ensayo E32 aislado. Su sender
es exclusivo y latched; UNKNOWN_RESULT nunca autoriza otro POST.

## Continuidad vigente — fases 91–100 (2026-10-14)

- Dónde estamos: cuarentena interna de evidencia implementada; 201 e-CF,
  68 PostgreSQL y 940 backend PASS. Omisiones y límites en informe 91–100.
- Funciona: minimización sin raw persistido, hash, correlación multiempresa,
  receipts append-only, replay concurrente y conciliación local conservadora.
- Simulado: autenticación TEST_ONLY en specs y evidencia fiscal de fixtures.
  Producción usa verificador bloqueado; hash/schema/id no prueban autenticidad.
- Bloqueado: consulta remota/receptor público, estados fiscales por receipts,
  liberación E34, sender/emisión, Alanube autenticado y contacto DGII.
- Falta: contratos, binding auténtico de primera respuesta, archivo/retención de
  artefactos, reglas fiscales E34, certificación/reseller y permisos operativos.
- Siguiente acción: revisar PROVIDER_BLOCKERS y solicitud técnica no enviada,
  obtener confirmaciones y diseñar binding/verificación. No conectar receipts
  sintéticos/internos a assertEvidence ni elevar históricos por un cambio de flag.
- Leer AGENTS, MASTER_CONTEXT, PHASES_91_100_FINAL_AUDIT, EVIDENCE_TRUST_MATRIX,
  PROVIDER_BLOCKERS, código evidence y migración 20261014200000.
- Comandos seguros: test e-CF, api:build, tsc, contracts --check y diff --check.
  Para PostgreSQL verificar UAT y backup antes de test-ecf-postgres.ps1, que conserva
  fixtures. No ejecutar build/prisma generate mientras los tests usan su DLL.
- No tocar producción/POS/Flutter/offline/sync/caja/inventario/licencias/NCF/ITBIS,
  taxEnabled/ncfEnabled, secretos ni switches. Sin commit/push/merge/deploy/otros
  worktrees. No purgar fixtures ni editar migraciones aplicadas.

Actualizado: 2026-10-14, cierre de fases 81–90.

## Continuidad vigente — integridad E34

- Dónde estamos: original/evidencia/empresa y ledger de crédito implementados
  y probados con PostgreSQL real aislado. 180 pruebas e-CF, 40 PostgreSQL y
  919 backend PASS. Ver informe 81–90 antes de interpretar estados históricos.
- Funciona: saldo original/aplicado/reservado/desconocido/disponible/rechazado,
  parciales/acumuladas, idempotencia, locks y restricciones que impiden exceso.
  Evidencia y fiscalSnapshot separados del resumen comercial y del dinero cobrado.
- Reintentos: reutilizar mismo documento/identidad; no cambiar payload reservado.
  UNKNOWN_RESULT conserva importe hasta resultado final respaldado por evidencia;
  no liberar por timeout, reinicio, HTTP o mera intervención sobre flags.
- Dos migraciones nuevas aplicadas solo UAT con backup previo. No reaplicar ni
  editar migraciones aplicadas. Hay fixtures sintéticos persistentes protegidos
  por auditoría, identificados ecf-81-90-*. No intentar eliminarlos desactivando
  triggers. Restablecer una UAT separada desde backup si se necesita otro estado.
- Simulado/no verificado: evidencia legal de fixtures. No hay ingestor oficial,
  sender ni endpoint de reservas. El método interno exige usuario autenticado
  y tenant; una futura exposición HTTP necesitará permisos explícitos.
- Bloqueado: toda emisión E34 por barrera adicional, producción, llamadas
  autenticadas, DGII y altas. Esquemas estructurales no certifican DGII.
- Siguiente acción: obtener/verificar evidencia auténtica y reglas fiscales
  condicionales por concepto/tasa y saldo original, resolver garantías DOM de
  conciliación/idempotencia/firma; diseñar ingestión y orquestación auditadas.
  No añadir un flag que salte el bloqueo E34 ni aceptar companyId del cliente.
- Comandos seguros: test e-CF, api:build, tsc, git diff --check. La UAT se valida
  con test-ecf-postgres.ps1 solo tras verificar aislamiento y backup: ahora cubre
  ambas suites y conserva fixtures E34 append-only. No confundir retención con
  datos de producción ni aceptación fiscal real.
- Leer: AGENTS, MASTER_CONTEXT, PHASES_81_90_FINAL_AUDIT, policy/service E34,
  migraciones 180000/183000 y matriz/plan de Sandbox. Restricciones originales
  completas siguen vigentes: POS/Flutter/offline/licencias/NCF/ITBIS intactos;
  sin commit/push/merge/reset/clean/stash/rebase/deploy ni exposición de secretos.

## Registro histórico 71–80

## Continuidad vigente — 71–80

- Dónde estamos: DTO/mapper DOP E31/E32/E34 y schemas oficiales automatizados.
  71–73 y 75–80 PASS en alcance local; 74 PARTIAL por evidencia económica del
  original; 66 continúa PARTIAL para conformidad fiscal integral.
- Funciona: 161 pruebas e-CF, 12 PostgreSQL y 900 generales PASS. Build completo,
  tsc, Prisma validate/status, diff y smoke del código compilado PASS.
- Contratos: OpenAPI DOM 3.0.3/API FE DOM 1.0.0, hashes fijados, referencias
  resueltas, matriz completa por campo. No datos de otros países. Payloads
  válidos reciben CONFIRMED_PARTIAL, nunca autorización de envío.
- Metadata explícita: encf, paymentType, incomeType según tipo, sequenceDueDate
  E31, creditNoteIndicator/modificationCode E34; paymentDeadline si crédito.
  company.id se mapea solo desde alanubeCompanyId explícito y el guard exige
  coincidencia con configuración confiable del tenant; no habilita fallback
  automático a la compañía principal del token.
  Sin valores ficticios fuera de fixtures. Operaciones sin metadata se bloquean.
- Limitaciones: DOP sin NON_BILLABLE/otros impuestos/moneda extranjera;
  opcionales y condiciones no implementadas se enumeran en matriz. E34 valida
  referencia, fecha/código y patrón oficial, pero no prueba saldo o existencia
  real del original. No inventar esa evidencia ni derivar certificación de HTTP.
- Simulado/desconectado: sender/worker, ventas tradicionales, consulta real y
  receiver webhook. POST fiscal sigue bloqueado por cliente y transporte.
- Próxima acción concreta: revisar matriz y pendientes del informe 71–80;
  confirmar reglas condicionales, evidencia del original y garantías DOM con
  la solicitud técnica ya preparada. No hay permiso para enviarla automáticamente.
- Comandos seguros adicionales: `node scripts/isolated-uat/prepare-alanube-contracts.cjs --check`,
  `npm --workspace apps/api test -- --testPathPatterns=src/ecf`, `npm run api:build`.
  Para regenerar fuente se necesitan los snapshots de hash esperado; las pruebas
  normales usan el código generado y no descargan nada. No reemplazar snapshots
  silenciosamente si cambia el proveedor.
- UAT: sin nuevas migraciones; antes de repetir fixtures verificar identidad
  y crear backup nuevo. El backup fase79 y las comprobaciones están en auditoría.
- Leer primero: AGENTS, MASTER_CONTEXT, PHASES_71_80_FINAL_AUDIT,
  CONTRACT_MATRIX_PHASES_71_74, solicitud técnica y plan de emisión.
- No tocar: producción, POS, Flutter, NCF/ITBIS, caja/inventario/offline/sync,
  licencias, secretos ni switches. No commit/push/merge/reset/clean/stash/deploy,
  llamadas autenticadas, DGII, alta de empresas ni emisión.

## Registro histórico 61–70

## Estado vigente (sustituye al registro inicial inferior)

- Dónde estamos: fase70 auditada; 61–65 y 67–70 PASS en alcance local;
  66 PARTIAL por conformidad contractual integral pendiente.
- Funciona: identidad de operación v2 independiente del fingerprint, conflicto
  por payload divergente, carreras resueltas con unique/P2002 fuera de transacción,
  recuperación UNKNOWN_RESULT e historial atómicos. 99 pruebas e-CF + 12 UAT PASS.
- Migración aplicada solo UAT: 20261014160000_ecf_stable_operation_identity.
  Backup previo verificado; datos sintéticos eliminados por IDs exclusivos del
  test. Los ensayos de migración usaron tablas temporales, sin reescribir datos
  públicos. Cero documentos e-CF y cero empresas fixture al finalizar.
- Regresión: 100 suites / 838 pruebas backend PASS. Build completo, Prisma
  validate, migrate status, tsc y diff check PASS; EPERM inicial no reapareció.
- Simulado/desconectado: transporte por defecto, adaptación de ventas,
  conciliación/webhook/cola sin sender/worker. No ruta pública fiscal.
- Contratos: OpenAPI públicos recuperados en artifacts/alanube-public-contracts;
  ver hashes y limitaciones en CONTRACT_RESEARCH_PHASE65. Verificador ejecutable
  de presencia detecta campos faltantes; no valida schema completo.
- Bloqueado: POST fiscal en cliente/transporte, reintentos EMISSION,
  aceptación por HTTP, producción, nuevas llamadas autenticadas y DGII.
- Falta: DTO/mapping integral de metadatos fiscales explícitos y validación
  completa request/response, garantías de idempotencia DOM, autenticidad/replay
  webhook, reglas reseller/activación, rate limits y numeración Sandbox.
- Siguiente fase recomendada (sin inventar numeración aprobada): completar
  conformidad contractual local con los schemas recuperados; revisar/enviar
  manualmente ECF_ALANUBE_TECHNICAL_INFORMATION_REQUEST.md. Nada se envió.
- Comandos: además de los comandos locales inferiores, ejecutar
  `./scripts/isolated-uat/test-ecf-postgres.ps1` solo con backup e identidad UAT
  verificados; crea y elimina únicamente fixtures sintéticos del propio test.
  `npm run api:build` y `npm --workspace apps/api test` validan el backend.
- Leer al retomar: AGENTS, MASTER_CONTEXT, PHASES_61_70_FINAL_AUDIT,
  CONTRACT_RESEARCH_PHASE65, TECHNICAL_INFORMATION_REQUEST, FIRST_SANDBOX_ISSUANCE_PLAN.
- No tocar producción, POS tradicional, credenciales ni banderas de emisión.
  No commit/push/merge/deploy. Nueva emisión necesita autorización específica,
  contratos completos y revisión de sender: las banderas actuales no bastan.

## Registro inicial histórico

- Dónde estamos: worktree FULLPOS-ECF-ALANUBE, feature/ecf-alanube; cambios
  previos preservados. Auditoría 61 confirma defectos de identidad/fingerprint.
- Funciona: configuración/onboarding y núcleo local; 25 suites / 81 tests PASS.
- Simulado: transporte por defecto; sin worker, sender ni conexión POS.
- Bloqueado: contratos completos, consulta, firma webhook, reseller,
  certificación y toda emisión. Build completo encontró EPERM Prisma.
- Falta: identidad estable, migración UAT, PostgreSQL/concurrencia, revisión
  pública oficial, seguridad y auditoría 70.
- Siguiente fase: 62; después 63 solo UAT con backup y auditoría previa.
- Comandos locales seguros: `git status --short`, `git diff --check`,
  `npm --workspace apps/api test -- --testPathPatterns=src/ecf`,
  `npm --workspace apps/api exec -- tsc -p tsconfig.build.json`.
- Leer: AGENTS.md, ECF_ALANUBE_MASTER_CONTEXT.md, informes 33–60 y primera
  emisión. El estado de ejecución genérico pertenece a un trabajo anterior.
- No tocar: producción, secretos, FULLTECH.txt, POS tradicional, Flutter,
  offline, caja, inventario, NCF/ITBIS. No commit/push/merge/deploy; no llamadas
  autenticadas ni emisión. No matar procesos indiscriminadamente por EPERM.

## ESTADO VIGENTE AL 2026-10-15 — Etapas D (E34) y E (numeración) completadas

Esta sección sustituye a las anteriores para las etapas D y E. La restricción
"no tocar Flutter" del registro histórico queda superada **solo** para la etapa F
del plan maestro (integración Flutter de e-CF), que sigue pendiente y sin empezar.

### Etapa D — Orquestador E34 (nota de crédito)

- `EcfEmissionService.dispatchOnce` incorpora la **guarda de seguridad E34**: un E34
  no se despacha sin una reserva en estado `RESERVED` cuyo `originalDocumentId`
  coincida con el del documento. Códigos: `E34_DISPATCH_REQUIRES_RESERVATION`,
  `E34_RESERVATION_NOT_ACTIVE`, `E34_ORIGINAL_REFERENCE_REQUIRED`. La comprobación
  ocurre dentro del claim `FOR UPDATE`, antes de cualquier salida de red.
- `EcfE34CreditService.prepareNote(user, { originalId, document, metadata, ... })`
  exige tipo E34, original de la misma empresa, original en `DGII_ACCEPTED` y tipo
  E31/E32; prepara y reserva en una sola operación.
- Defecto real corregido: `prepare()` devolvía el documento **anterior** a la
  escritura del resumen de emisión, por lo que el llamante nunca veía el `encf`
  persistido. Ahora devuelve la fila persistida dentro de la transacción.
- Cobertura: `ecf-e34-emission-postgres.integration-spec.ts` — **13/13 PASS**
  (parcial, total, saldo insuficiente, original no aceptado, original de otra
  empresa, idempotencia y divergencia, rechazo y timeout que **mantienen** la
  reserva, respuesta contradictoria, un único dispatch bajo concurrencia,
  cross-tenant).

### Etapa E — Numeración e-CF (E31/E34)

- Modelos `EcfSequence` y `EcfSequenceAuditLog`; migración aditiva
  `20261015090000_ecf_numbering_ranges` (aplicada **solo** a la BD efímera).
- `EcfSequenceService`: `register`, `renew`, `allocate` (+ `allocateIn` para la
  transacción del llamante). Bloqueo `FOR UPDATE` y `next_number` que solo
  incrementa: el número se consume de forma **permanente**. E32 **no** es
  asignable (`ECF_SEQUENCE_TYPE_UNSUPPORTED`): conserva su slot single-use.
- El no-reuso es una garantía de base de datos, no solo lógica de aplicación:
  trigger `ecf_sequence_guard` (identidad de rango inmutable, `next_number`
  irreversible), índice único **parcial** `WHERE active` (permite conservar el
  historial al renovar) y ledger de asignaciones append-only.
- `EcfEmissionService.prepare` asigna el e-NCF cuando el llamante no lo fija, con
  clave de operación: un reintento **reutiliza** el número ya consumido en lugar de
  gastar otro.
- Formato: prefijo + 10 dígitos (13 caracteres), `^E(31|34)\d{10}$`.
- Cobertura: `ecf-sequence-postgres.integration-spec.ts` — **13/13 PASS**
  (formato, 20 asignaciones concurrentes sin repetición, agotamiento, rango
  expirado, aislamiento por empresa, no reuso tras cancelar el documento, reintento
  por clave de operación, E32 no asignable, renovación por debajo del frente
  consumido rechazada, guardas a nivel de base de datos).
- `scripts/ecf-test-db/reset.ps1`: reconstrucción del esquema efímero con
  `--skip-seed` (los suites crean sus propias fixtures; el seed exige
  `ADMIN_PASSWORD`).

### Validación (real, ejecutada)

- Suite completa sobre la BD efímera: **117/118 suites, 1212 PASS, 8 skipped**.
- `ISOLATION OK`: UAT histórica idéntica antes/después (708 empresas / 568 trials /
  3462 documentos). El e-NCF histórico `E320009805001` no se tocó.
- `npx tsc -p tsconfig.build.json --noEmit` → 0 errores. `prisma validate` OK.
  `git diff --check` limpio.

### Pendiente

- F: integración Flutter (auditar `apps/fulltech_app` primero; e-CF OFF por defecto,
  selección E31/E32, estados, flujo E34, permisos, multiplataforma).
- G: E2E con datos sintéticos. H: auditoría de seguridad final. I: certificación.

### Restricciones que siguen vigentes

Sin producción, sin deploy, sin commit/push/merge, sin POST/GET reales a Alanube,
sin emisiones fiscales, sin APPLY sobre históricos, sin borrar volúmenes, sin
habilitar e-CF por defecto y sin `DGII_ACCEPTED` sin evidencia fiscal suficiente.
