# Fullpos Cloud — contexto maestro e-CF Alanube

## Última evidencia: acceso ADMIN UAT funcionando

2026-10-14: auditoría encontró 0 ADMIN. Backup aislado verificado, creación
exclusiva de empresa/ADMIN/membresía sintéticos con bcrypt10 oficial y trial
estándar de 7 días. alanube.admin@fullpos.local; operador definió nueva contraseña
oculta, nunca guardada en archivos ni mostrada. Login real HTTP201, preflight
OPERATOR_CONTEXT=true; DB confirma ADMIN, OWNER/ACTIVE, empresa ACTIVE y TRIAL
vigente hasta 2026-10-21. Ningún usuario previo/licencia existente alterados.
API127.0.0.1:4002 activa. Documentación: ECF_ALANUBE_UAT_ADMIN_ACCESS.md.
Preflight E32 BLOCKED por configuración e-CF inexistente de este nuevo tenant y
dirección Sandbox pendiente. Resolver acceso no activó configuración fiscal.
Sin llamadas Alanube, emisión, producción, POS ni operaciones Git de escritura.

## Último progreso local: API UAT iniciada y login interactivo pendiente

Resultado posterior: operador realizó un POST local de login, HTTP401 Invalid
credentials (sin JWT). ADMIN configurado no existe en esta base, confirmado por
consulta de identificación sin divulgarla. Bloqueo interno real de cuenta UAT;
no elegir usuario por ID ni crear sesión/licencia artificial. Esperar información
de ADMIN existente o preparar provisión sintética separada. Build final PASS al
liberar únicamente nuestro PID31120 dueño de DLL; API reiniciada PID33860 en
127.0.0.1:4002. Prisma validate PASS. Preflight BLOCKED, controles por tenant
NOT_EVALUATED. Dirección válida es único dato externo, no único bloqueo total.

Usuario autoriza API/login local, mantiene FULLTECH/RNC 132109122. No exigir
aclaración adicional del nombre; solo dirección Sandbox externa pendiente.
Se corrigió registro Nest de resolver opcional mediante factory y se agregó
prueba de composición EcfModule. UAT solo loopback en main.ts; launcher desactiva
telemetría/emisión. API127.0.0.1:4002 /health/db HTTP200. Helper interactivo abierto
con contraseña oculta y JWT solo memoria; informe WAITING_FOR_OPERATOR/0 intentos
al registrar progreso. 237 e-CF, 976 backend, tsc PASS. Build Prisma EPERM con
runtime usando DLL, pendiente repetir sin ese proceso. No autoproclamar solo
bloqueo externo hasta validar sesión/tenant/licencia. Ver readiness/runbook.

## Última evidencia real: GET de empresa autorizado y consumido

2026-10-14T18:48:56.5416763Z: 1 GET /dom/v1/company con token DPAPI, HTTP 200;
0 POST. VERIFIED_BY_LIVE_READ: id 01M3T6Y4R9BH35XGJ5PP12KV0T,
identification=132109122, type=main, name=FULLTECH, address=address (literales).
Hash de respuesta y detalles en ECF_ALANUBE_E32_SANDBOX_READINESS.md.
Principal confirmada: manifiesto actualizado TOKEN_PRIMARY, sin company.id,
nombre remoto observado, mismo RNC/UUID/rango; address sigue null por placeholder.
BLOCKED por dirección/nombre de prueba discrepantes con propuesta y JWT UAT
ausente/API4002 sin listener. Login POST local no ejecutado bajo prohibición de
cualquier POST; runbook listo para operador. No repetir GET con este permiso.
35 pruebas E32 PASS; preflight BLOCKED; producción y POS sin modificaciones.

## Última aclaración y verificación E32 — 2026-10-14

Precisión de continuidad: nombre Alanube Soluciones S.R.L. corroborado con la
propuesta según el usuario y el ejemplo oficial E32; agregado al manifiesto
ignorado. Dirección y vínculo principal/asociada siguen NOT_VERIFIED. GET DOM
/company consulta empresa del token y permite resolverlo tras autorización
separada; no ejecutado. Login real UAT POST /auth/login, respuesta accessToken,
procedimiento documentado sin exponer secretos; no ejecutado. No usar IDs de
usuario como autenticación. Ver runbook actualizado; pendientes concretos allí.

USER_CONFIRMED: Alanube entregó oficialmente el paquete Sandbox RNC 132109122,
secuencias 9805001–9806000, vencimiento 2028-12-31 y acceso. Sustituye la
declaración anterior de configuración no autorizada. VERIFIED_IN_CODE/BY_TEST:
destino explícito TOKEN_PRIMARY sin company.id y GET por id, o asociado con
ULID/GET por compañía; respuesta sin RNC permitido por contrato, contradicciones
rechazadas, sin aceptación fiscal. Formato oficial de 13 caracteres produce
candidato E320009805001; solo borrador ignorado, no número reservado/consumido.
Validación actual: 35 focalizadas, 88 PostgreSQL, 975 backend PASS (96 omitidos,
88 PG aparte), build/Prisma/contratos PASS. BLOCKED: no JWT ADMIN UAT válido
disponible al preflight; nombre/dirección y empresa primaria/asociada pendientes.
Las verificaciones por tenant dependen de ese JWT, no son fallos demostrados
del proveedor. No exige certificación productiva. Ver informe de readiness y
runbook actualizados. Cero llamadas autenticadas; slot real vacío. Sin migración
nueva ni cambio a POS, producción, auth/licencia, ni operaciones Git de escritura.

## Registros anteriores (históricos donde discrepen con la última aclaración)

## Estado vigente — preparación primera E32 (2026-10-14)

- VERIFIED_IN_CODE / VERIFIED_BY_TEST: recorrido exclusivo CLI E32 con manifiesto
  fijo sintético 168.00 DOP, preflight, JWT UAT + JwtStrategy existente, trial
  global de un solo uso, transporte dedicado, primer binding y GET por compañía.
  Claim commit antes de red; timeout/crash no permiten repetir POST. Observaciones
  y hashes en cuarentena; no DGII_ACCEPTED ni fiscalSnapshot fabricado.
- Contratos GET oficiales resueltos contra dependencias públicas DOM y fijados
  por hash; no usar schema POST para GET. Mapper previo correcto para el candidato.
  No nuevas dependencias, rutas HTTP públicas ni modificación de auth/licencias.
- VERIFIED_BY_TEST: 31 locales E32, 232 e-CF, 87 PostgreSQL y 971 backend PASS.
  95 omitidos en backend: 87 PG aparte y 8 opt-in ajenos no verificados. Build,
  tsc, Prisma validate/status (36), generación contractual y controles de seguridad.
- Una migración SOLO UAT: 20261014220000_ecf_e32_single_trial con backup verificado,
  ensayo ROLLBACK y aplicación PASS. Fixtures MOCK_ONLY conservados; slot real
  FIRST_E32_SANDBOX sin consumir. Sin números fiscales reservados/consumidos.
- BLOCKED real: empresa/idCompany/habilitación E32 y e-NCF completo disponible
  no confirmados. Perfil local RNC/rango/vigencia NO es autorización, confirmado
  expresamente por usuario. Draft ignorado preserva UUID; no inventar IDs/e-NCF.
- Contexto JWT UAT/config del tenant y consentimiento final pendientes. DPAPI
  existe, no descifrado; autenticación Alanube solo histórica, sin nuevas llamadas.
- E34/conformidad productiva/webhook no son requisitos de este primer E32. La
  documentación Alanube distingue certificación productiva de simulación Sandbox;
  no se infiere habilitación de nuestra identidad. Producción/POS intactos.
- Leer E32_SANDBOX_READINESS, FIRST_E32_SANDBOX_RUNBOOK y
  E32_PROVIDER_CONFIRMATION_REQUEST (mensaje exacto NO enviado). Próxima acción:
  confirmar empresa/numeración con Alanube, completar config/manifest/JWT y repetir
  preflight. Solo READY_FOR_AUTHORIZATION permite pedir aprobación específica.

## Estado vigente — fases 91–100 (2026-10-14)

Este bloque prevalece sobre registros históricos inferiores.

- VERIFIED_IN_CODE / VERIFIED_BY_TEST: ingestor interno sin endpoint/sender;
  tenant por requireTenant, correlación documento/intento/identidad/fingerprints,
  id remoto conocido, hash exacto y bandeja EcfEvidenceReceipt append-only.
- Solo metadatos/hashes/códigos; bytes/headers/firmas/credenciales no persistidos.
  64 KiB/profundidad 32 son políticas locales, no límites del proveedor.
- Niveles SYNTHETIC/INTERNAL/PROVIDER_DECLARED. Verificador productivo siempre
  BLOCKED_PENDING_PROVIDER_CONTRACT; TEST_ONLY_AUTHENTICATED solo sintético.
  Sin promoción histórica, aceptación/rechazo fiscal ni escritura en ledger.
- Replay tenant/source/event; locks documento/intento y advisory transaccional.
  Schema inválido correlacionado queda en cuarentena. Conciliación RepeatableRead
  conserva UNKNOWN_RESULT/reservas y exige revisión ante hashes múltiples/schema
  inválido/sin id. No polling, retry POST, liberación ni binding remoto nuevo.
- VERIFIED_BY_TEST: 201 e-CF PASS; 68 PostgreSQL PASS (12 idempotencia, 28 E34,
  28 evidencia); 940 backend PASS, 76 omitidas (68 PostgreSQL aparte; 8 opt-in
  ajenas no verificadas). Build/tsc/validate/status/contracts check PASS.
- Una migración SOLO UAT: 20261014200000_ecf_evidence_quarantine; backup leído
  íntegramente, ensayo SQL ROLLBACK y deploy PASS. 35 migraciones al día. Drift
  histórico de defaults/índices y otras tablas no aplicado ni ocultado.
- PARTIAL: autenticidad externa, conciliación remota, webhook operativo y reglas
  fiscales integrales. E34/emisión NO-GO; sin contacto DGII ni Alanube autenticado.
- Leer EVIDENCE_TRUST_MATRIX, PROVIDER_BLOCKERS y PHASES_91_100_FINAL_AUDIT.
  Próximo paso: contratos/prueba de autenticidad y binding de primera respuesta,
  custodia de artefactos y orquestación antes de cualquier transición fiscal.

Actualizado: 2026-10-14, fases 81–90. Las secciones siguientes conservan
registros históricos; este primer estado es el vigente. No contiene credenciales.

## Estado vigente — fases 81–90

- VERIFIED_IN_CODE / VERIFIED_BY_TEST: EcfE34CreditService interno, sin endpoint
  ni sender; tenant derivado por requireTenant. Verifica original E31/E32,
  estado DGII_ACCEPTED, snapshot y log de evidencia coincidentes, e-NCF, fechas,
  moneda y referencia de la nota. Documento comercial/HTTP/proveedor aceptado
  no sustituye evidencia fiscal. Las pruebas de evidencia son sintéticas.
- Saldo fiscal separado de caja, pagos, CxC e inventario. Decimal estricto a
  centavos. Importe solicitado = total del snapshot local de la nota; no float.
  Disponible = original − APPLIED − RESERVED − UNKNOWN_RESULT. DRAFT no aplica
  ni reserva por sí solo; rechazo/cancelación distinguidos de crédito aplicado.
- Reservas únicas por nota y tenant, identidad/fingerprint inmutables, lock de
  documentos en orden estable; trigger PostgreSQL vuelve a comprobar presupuesto.
  UNKNOWN_RESULT nunca expira/libera automáticamente. APPLIED/REJECTED requieren
  snapshot, estado y evidencia/log coincidentes; sin pipeline oficial se bloquean.
- Nuevas relaciones compuestas por empresa, unicidad de e-NCF por tenant,
  snapshot fiscal inmutable y ledger/eventos append-only. No se reservó ni
  consumió numeración: son reservas monetarias internas exclusivamente.
- VERIFIED_BY_TEST: 28 suites / 180 pruebas e-CF PASS; 2 suites / 40 PostgreSQL
  PASS (12 previas + 28 E34); backend 102 suites / 919 pruebas PASS, 48 omitidas
  (40 PostgreSQL ejecutadas aparte, 8 opt-in ajenas no verificadas).
- Build completo, tsc separado, Prisma validate/status, generación contractual
  y diff check PASS. migrate diff es diagnóstico: diferencias históricas fuera
  del bloque nuevo documentadas, no aplicadas. Mapping de índices nuevos alineado.
- Dos migraciones aplicadas SOLO UAT: 20261014180000_ecf_e34_credit_integrity y
  20261014183000_ecf_fiscal_reference_uniqueness. Backups verificables y recuperación
  de dos intentos SQL fallidos/rollback en informe 81–90. Sin pérdida de filas.
- UAT retiene fixtures sintéticos ecf-81-90-* para auditoría: el ledger y sus
  evidencias no tienen bypass de borrado para tests. No son documentos reales.
- Fases 81–86 y 88–90 PASS en alcance local; 87 PARTIAL: condiciones DGII,
  acreditación por conceptos/tasas y autenticidad/ingestión oficial de evidencia
  no demostradas. Fase74: deficiencias de integridad local resueltas; conformidad
  legal y fase66 siguen PARTIAL. No simular aceptación externa con fixtures.
- E34 tiene bloqueo preemisión incondicional adicional, incluso si un mapping
  afirma contrato completo. No rutas HTTP ni permisos nuevos. Antes de exponer
  estos servicios se necesitan autorización y orquestación fiscal auditadas.
- Próxima acción: verificar/implementar ingestión de evidencia auténtica,
  semántica DGII y conciliación DOM; después revisar integración transaccional
  del sender. No emisiones ni llamadas autenticadas autorizadas en este bloque.
  Leer ECF_ALANUBE_PHASES_81_90_FINAL_AUDIT.md y NEXT_STEPS.md.

El estado 71–80 siguiente es histórico y se conserva por trazabilidad.

## Estado vigente — fases 71–80

- VERIFIED_BY_TEST: 27 suites / 161 pruebas e-CF PASS, PostgreSQL opt-in 12 PASS,
  regresión general 101 suites / 900 pruebas PASS (2 suites / 20 pruebas omitidas;
  12 PostgreSQL ejecutadas por separado, 8 opt-in ajenas no verificadas).
- VERIFIED_BY_TEST: api:build completo, tsc separado, Prisma validate/status,
  git diff --check y smoke del JavaScript compilado PASS. Smoke: 7 payloads,
  cero invocaciones de red/secret resolver, POST bloqueado.
- VERIFIED_IN_CODE y VERIFIED_BY_TEST: mapper ahora usa rnc/companyName,
  stampDate, totales por tasa ITBIS, subDiscounts y referencia E34 oficiales;
  metadata fiscal explícita separada. Sin e-NCF/ingreso/pago predeterminados.
- VERIFIED_BY_TEST: Ajv 8.17.1 + ajv-formats 3.0.1 validan schemas derivados
  íntegramente de los snapshots DOM públicos fijados por hash. No coerción,
  defaults ni eliminación de propiedades. Overlay local rechaza campos no
  documentados. Generador offline detecta deriva; código generado se compila
  dentro del API y no depende de artifacts/ en runtime.
- VERIFIED_BY_TEST: snapshots E31/E32/E34 coinciden con el HTML oficial actual,
  OpenAPI 3.0.3/API FE DOM 1.0.0. Matriz campo por campo en
  ECF_ALANUBE_CONTRACT_MATRIX_PHASES_71_74.md. Schemas y hashes en código generado.
- VERIFIED_BY_TEST: estados del proveedor y legalStatus son observaciones,
  nunca aceptación fiscal local. Schema/body/tipo HTTP se verifican antes de
  exponer observaciones. Errores no reenvían mensajes sensibles del proveedor.
- VERIFIED_BY_TEST: guard exige contexto de empresa, RNC y company.id proveedor,
  permisos, autorización,
  Sandbox, certificación, estado, identidad v2, fingerprint interno y del payload,
  revalidación actual y aprobación completa del registry. Todo permanece bloqueado.
- UAT: sin migraciones nuevas. Backup previo a fixtures:
  artifacts/uat-backups/ecf_before_phase79_20261014.dump, 582346 bytes,
  SHA-256 124766F9533361B41F173AC88EE587F9C6A4EC6248B9FA51B3CBEC064FED6CE7.
  Verificado por lectura íntegra pg_restore, sin ensayo de restauración.
- Fases 71,72,73,75,76,77,78,79,80 PASS en alcance local documentado;
  74 PARTIAL: estructura E34 verificada, existencia/saldo/relación económica del
  original no demostrados por JSON Schema. Fase66: brecha estructural abordada;
  continúa PARTIAL para conformidad fiscal integral fuera del subconjunto soportado.
- BLOCKED: emisión y producción; garantías DOM idempotencia/conciliación,
  webhook/firma/replay, rate limits, reseller/activación y autorización legal.
- No llamadas autenticadas nuevas, DGII, emisiones, alta de empresas ni consumo
  de secuencias. POS tradicional, Flutter, offline, licencias e indicadores
  taxEnabled/ncfEnabled no se modificaron. Cambios previos preservados.
- Próximo paso: confirmar semántica condicional y evidencia de originales/saldos
  E34, variantes oficiales de respuesta y preguntas técnicas del proveedor;
  diseñar flujo de evidencia/persistencia antes de cualquier sender futuro.
  Informe vigente: ECF_ALANUBE_PHASES_71_80_FINAL_AUDIT.md.

## Estado final de este bloque (prevalece sobre el registro inicial inferior)

- VERIFIED_BY_TEST: idempotencia estable v2, concurrencia, conflicto por payload,
  aislamiento, timeout, recreación del cliente e historial. 99 pruebas locales
  e-CF y 12 PostgreSQL aprobadas; suite PostgreSQL opt-in separada.
- VERIFIED_BY_TEST: 100 suites / 838 pruebas backend general PASS; 2 suites y
  18 pruebas omitidas en esa ejecución. No confundir omisiones con PASS; las
  pruebas e-CF PostgreSQL se ejecutaron aparte. La suite opt-in ahora contiene
  12 casos (se añadieron dos ensayos de migración después del run general).
- VERIFIED_BY_TEST: build completo (Prisma 5.22.0 + tsc), tsc separado,
  prisma validate, migrate status y diff check PASS. EPERM inicial superado por
  reejecución sin matar procesos ni borrar DLL; auth.password-reset pasó en
  regresión completa posterior sin cambiar código auth.
- VERIFIED_BY_TEST: migración 20261014160000 aplicada solo UAT; respaldo
  `artifacts/uat-backups/ecf_before_phase63_20261014.dump`, 582256 bytes,
  SHA-256 `0C899ED8EB69007F6CA612DED19DB1D40C28872E23C3027DF77D8C3466C84BE0`.
  pg_restore leyó el archivo completo; no se realizó restauración de recuperación.
- VERIFIED_BY_TEST: copias públicas OpenAPI 3.0.3 recuperadas. Ver informe 65.
  El mapper sigue incompleto, valida presencia oficial y declara rutas faltantes.
- VERIFIED_IN_CODE: no POST fiscal desde cliente seguro ni transporte real;
  no reintento EMISSION; barrera requiere registry completo. HTTP 2xx y fallos
  de red no generan aceptación. Recuperación interna persiste UNKNOWN_RESULT
  con CAS e historial; no existe worker ni conciliación real conectada.
- Fases: 61 PASS, 62 PASS, 63 PASS, 64 PASS, 65 PASS, 66 PARTIAL,
  67 PASS (endurecimiento local; sender sigue desconectado), 68 PASS,
  69 PASS (alcance local), 70 PASS (auditoría entregada).
- BLOCKED: emisión, garantías proveedor DOM, firma/replay, reseller y activación.
  No afirmar DGII autorizado. No se hicieron llamadas autenticadas externas.
- Próxima acción: revisar snapshots oficiales y completar DTO/mapper/validación
  contractual, resolver solicitud técnica y diseñar sender en tarea separada.
  `ECF_ALANUBE_PHASES_61_70_FINAL_AUDIT.md` contiene archivos y evidencias.

El texto inferior conserva el punto de partida y sus etiquetas históricas.

## Objetivo y límites

Integrar e-CF opcional Alanube DOM para República Dominicana sin alterar el POS
tradicional. Empresa desarrolladora: FULLTECH, SRL (contexto del propietario).
No producción, emisión Sandbox/productiva, DGII, llamadas autenticadas Alanube,
commit, push, merge, deploy, Flutter, offline ni cambios a NCF/ITBIS tradicional.

## Identidad verificada

- VERIFIED_IN_CODE: worktree `C:\Users\pc\DEV\PROYECTOS\PRODUCTOS\FULLPOS-ECF-ALANUBE`,
  rama `feature/ecf-alanube`, HEAD `6b3e38ed57bc53f9a55e66cf2eccf315afffd3f1`.
- Existen cambios locales previos, incluidos `AGENTS.md`, schema, AppModule,
  uat-safety y archivos nuevos e-CF. Preservarlos; no atribuirlos a esta sesión.

## Arquitectura real

VERIFIED_IN_CODE: AppModule → EcfModule → EcfController → EcfService → Prisma.
JWT, RolesGuard y permisos protegen configuración, onboarding, historial y
provider/status. Tenant derivado del usuario autenticado en esos endpoints.
No endpoint de emisión. Servicio documental interno sin exposición HTTP.

VERIFIED_IN_CODE: AlanubeSafeHttpClient usa transporte por DI; simulado por
defecto. La factory selecciona transporte real solo con transport enabled,
real calls y Sandbox. La existencia del transporte no autoriza su uso.
Fiscal core, mapper, state machine, retry, conciliación y webhook son componentes
locales; no constituyen una integración fiscal operativa completa.

VERIFIED_IN_CODE: adaptador de ventas puro, sin conexión a sales.create.
Cola es política inerte, sin worker de emisión. Observabilidad y auditoría son
helpers, sin flujo de envío persistido ni exporter completo.

## Decisiones técnicas

- e-CF desactivado por defecto; no cambiar taxEnabled ni ncfEnabled.
- Aislar por companyId autenticado; no aceptar tenant del cliente HTTP.
- Configurar proveedor no equivale a certificación DGII.
- HTTP 200 no acredita aceptación fiscal.
- Contratos incompletos y emisión bloqueada; fixtures son datos sintéticos.
- Identidad de operación separada de fingerprint; implementación 62 pendiente
  al crear este documento.

## Fases 3–60

| Bloque | Evidencia y clasificación |
| --- | --- |
| 3–5 | VERIFIED_IN_CODE: configuración, onboarding, evidencia, auditoría, permisos. HISTORICAL_REPORT: ejecución original. |
| 6–9 | VERIFIED_IN_CODE: núcleo E31/E32/E34, Decimal, mapper y secret resolver. HISTORICAL_REPORT: almacenamiento local DPAPI; no abrir credenciales. |
| 10–30 | VERIFIED_IN_CODE: documentos, estados, transporte y políticas. HISTORICAL_REPORT: backup y migración UAT aplicados. |
| 31 | HISTORICAL_REPORT: una llamada GET /company, HTTP 200 AUTH_CONFIRMED; no repetida. |
| 32 | HISTORICAL_REPORT: auditoría; hallazgos de transporte/provider status parcialmente resueltos después. |
| 33–60 | VERIFIED_BY_TEST al recuperar: 25 suites / 81 pruebas e-CF PASS. Contratos PARTIAL; webhook y reseller BLOCKED. |

## Fases 61–70: plan autorizado y estado inicial

61 auditoría idempotencia; 62 corrección; 63 migración UAT con backup; 64 pruebas
PostgreSQL; 65 fuentes públicas oficiales; 66 contratos ejecutables confirmados;
67 seguridad de envío; 68 solicitud técnica sin envío; 69 UAT/regresión;
70 auditoría final. Estado inicial: 61 auditada, 62–70 pendientes. No sustituir
evidencia real con el contexto del usuario; actualizar al cierre.

## Configuración y UAT

VERIFIED_IN_CODE: ALANUBE_ENV, ALANUBE_ENABLE_REAL_CALLS,
ALANUBE_HTTP_TRANSPORT_ENABLED, ECF_EMISSION_ENABLED,
ECF_ALANUBE_AUTH_TESTS_ENABLED. No activar banderas ni resolver token.
HISTORICAL_REPORT: token Sandbox cifrado DPAPI; autenticación fase31 únicamente.

VERIFIED_BY_TEST (consulta local al recuperar): contenedor
`fullpos_alanube_uat_postgres`, puerto publicado solo `127.0.0.1:56550`, base
`fullpos_alanube_uat`, cero documentos e-CF. Antes de escribir: identidad,
aislamiento, backup verificado, auditoría conflictos e integridad.

## Contratos y migraciones

VERIFIED_IN_CODE: registry parcial E31/E32/E34; mapper BLOCKED_PENDING_SCHEMA.
No OpenAPI completo verificado en esta sesión todavía. Consulta, idempotencia
proveedor, webhooks, firmas, certificación/reseller y límites siguen pendientes.

Migraciones existentes: `20261014120000_add_ecf_onboarding_base`,
`20261014143000_add_ecf_document_idempotency`. HISTORICAL_REPORT: aplicadas UAT;
consultar historial real antes de migrar. No editar migraciones aplicadas.

## Riesgos y validación inicial

VERIFIED_IN_CODE: unique(companyId,payloadFingerprint) demasiado restrictivo;
clave incluye fingerprint; carrera find/create necesita manejo explícito.
VERIFIED_BY_TEST: tsc PASS; build completo FAIL EPERM DLL Prisma. Ejecución
amplia accidental de Jest: 73 suites PASS, auth.password-reset FAIL por
PrismaClient indefinido. No declararlos fallos corregidos sin repetir checks.
BLOCKED: emisión, contratos completos, aceptación DGII, certificación/reseller.

## Fuentes internas y reanudación

Leer AGENTS.md y reglas scoped, docs/PRODUCT_SPEC.md, ARCHITECTURE.md,
ENVIRONMENTS.md, TESTING.md, WORKFLOW.md; luego informes ECF fase6 a fase60,
FIRST_SANDBOX_ISSUANCE_PLAN.md y NEXT_STEPS.md. `docs/EXECUTION_STATE.md`
describe otro objetivo histórico y no debe sobrescribirse con este desarrollo.

En conversación nueva: verificar worktree/rama/status, preservar cambios,
leer este documento y auditoría más reciente, contrastar código y tests, no
repetir autenticación fase31 ni asumir autorización de emisión. Próxima acción:
62 identidad estable y pruebas, luego 63 backup/migración UAT.
