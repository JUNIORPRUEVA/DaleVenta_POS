# Fullpos Cloud — auditoría fases 91–100

Fecha: 2026-10-14. Worktree exclusivo FULLPOS-ECF-ALANUBE.
Rama feature/ecf-alanube, HEAD conservado
6b3e38ed57bc53f9a55e66cf2eccf315afffd3f1. Cambios previos preservados.

## Dictamen y fases

**NO-GO para primera emisión Sandbox y producción.** Implementación local
validada; autenticidad fiscal externa no demostrada. Ningún test final falla.

| Fase | Estado | Implementación | Pruebas | Bloqueos |
| --- | --- | --- | --- | --- |
| 91 | PASS | Auditoría de evidencias snapshot/log/attempt, niveles y procedencia explícitos | Código, schema, historial y pruebas existentes | No elevar históricos |
| 92 | PARTIAL | Ingestión interna, hash, correlación y receipt inmutable sin raw | PostgreSQL real y validación de entrada | Ingestión operativa auténtica, artefactos y retención |
| 93 | PARTIAL | Verificador extensible; DI productiva bloqueada; prueba TEST_ONLY aislada | Ed25519 efímero solo en spec; persistencia sintética en PostgreSQL | Contrato oficial y prueba real de autenticidad |
| 94 | PASS local | Tenant autenticado, operación/fingerprints, doc/intento, FK compuestas, replay | Cruces, contradicciones, carreras y restricciones reales | Primer binding remoto requiere diseño auténtico |
| 95 | PARTIAL | Conciliación read-only consistente, revisión conservadora, sin retry/liberación | Timeout/red/reinicio, respuestas tardías, persistencia | Semántica y garantías de consulta remota |
| 96 | PARTIAL | Envelope LOCAL acotado, tamaño/JSON, correlación, replay e historial | Eventos sintéticos, malformed, replay concurrente | No receptor público; contrato/auth wire pendientes |
| 97 | PARTIAL | Revisión pública E34; reglas estructurales existentes conservadas | Schemas/mapper/guard y regresión E34 | DGII integral, conceptos/impuestos/plazos, sin contacto DGII |
| 98 | PASS local | 21 unitarias nuevas + 28 PostgreSQL de evidencia, más suites existentes | 201 e-CF y 68 PostgreSQL | No equivalen a aceptación externa |
| 99 | PASS local | Build, tsc, validate/status, contratos, regresión y seguridad | 940 backend, checks y smoke compilado PASS | Drift histórico documentado, 8 opt-in ajenas no ejecutadas |
| 100 | PASS | Auditoría, matriz confianza, bloqueos y continuidad | Documentación y revisión final | Primera emisión NO-GO |

## Auditoría y plan ejecutado

HECHO / VERIFIED_IN_CODE: modelo real EcfElectronicDocument (no EcfDocument),
EcfElectronicDocumentAttempt, logs, snapshot fiscal y reservas. Los estados de
fixtures y sus hash/ref son sintéticos/internos, no autenticidad DGII. El
intérprete anterior ya conserva estados del proveedor como observaciones. La
máquina de estados pura tiene hasEvidence, pero no demuestra origen: no se
conectó la nueva bandeja a esa autorización ni a assertEvidence del ledger.
No hay sender activo, consulta remota implementada ni receptor webhook público.
El controller conserva JWT/RolesGuard/permisos de configuración existentes.

Plan mínimo ejecutado: cuarentena inmutable sin raw ni alta confianza; correlación
tenant/documento/intento/operación/fingerprints y referencia remota ya asociada;
verificador productivo bloqueado; lectura de conciliación sin efectos fiscales;
webhook interno sin contrato inventado; migración UAT segura y pruebas/revisión.
AGENTS permite multifase por autorización expresa del usuario; el texto genérico
de WORKFLOW de detenerse entre fases se interpreta bajo esa excepción autorizada.
Sin subagentes ni writers adicionales iniciados. Sin dependencias nuevas.

## Implementación real y límites

EcfEvidenceIngestionService requiere TenantUser; no acepta companyId en el input.
Rechaza claims empresariales en el objeto externo. Documento/intento se buscan
por tenant y se bloquean en ese orden; se verifica identidad estable documental,
fingerprint del documento y requestFingerprint del intento. PREPARE sintético
en tests no prueba una solicitud de red efectivamente enviada.

Los receipts se correlacionan con filas locales, no buscando tenant por un id
externo. Si body.id aparece debe corresponder al id ya asociado. Si varias filas
del tenant comparten ese id remoto, se rechaza la asociación ambigua en lugar de
elegir una. Es una defensa local conservadora, no garantía de unicidad Alanube.
No se admite
binding nuevo/desconocido ni selección por empresa declarada. e-NCF externo
explícito contradictorio se rechaza; no se asigna numeración. La identidad y los
ids remotos quedan congelados por trigger al tener receipts; una futura primera
respuesta requiere asociación/versionado auténticos, no modificar estos controles.

Body en memoria: Buffer UTF8/JSON objeto, 64 KiB máximo, profundidad 32. Hash
SHA-256 sobre bytes exactos y expectedHash opcional comprobado. No se guardan
body, headers, firmas, credenciales ni mensajes externos. Separados: metadata
técnica, hash de operación/correlación, autenticidad, resultado estructural/schema
hash y observación segura. El campo source es declaración, no prueba del transporte.

La validación Ajv usa los schemas oficiales fijados existentes para respuestas
de emisión, NO se afirma que el schema POST cubra GET. Un 200 no documentado ahí
queda OFFICIAL_SCHEMA_INVALID, sin fiscalidad. Schema inválido correlacionado
se registra en cuarentena; JSON/hash/correlación inválidos se rechazan con código
sin persistir cuerpo ni adivinar documento. No hay auditoría pública de rechazos
porque no se habilitó receptor; diseñarla antes de una recepción operativa.

Idempotencia por (tenant,source,eventKey), hash correlacionado estable y unique.
Replay idéntico devuelve fila; divergente entra en conflicto. Lock documento/
intento y advisory transaccional por tenant/source/event serializan carreras
también entre documentos distintos; unique protege acceso SQL directo. Colisiones
del advisory solo serializan más trabajo, no autorizan duplicados. No retry POST.

Receipt append-only y FK compuestas tenant/documento/intento; no UPDATE/DELETE
ni promoción sintética. Trigger protege identidad documental y del intento.
La migración además reemplaza FK global de intentos por FK compuesta tras auditar
datos existentes. No reclasifica ni cambia snapshot/log de documentos históricos.

La DI usa siempre EcfBlockedAuthenticityVerifier. La extensión de prueba puede
devolver TEST_ONLY_AUTHENTICATED solo bajo SYNTHETIC. Ed25519 del spec con claves
efímeras NO es un mecanismo Alanube inventado. No existe ruta de confianza fiscal
alta en schema ni en producción. Los receipts nunca escriben estados, snapshot,
logs fiscales, reservas ni secuencias. Conservación append-only local no equivale
a política legal de artefactos; necesita revisión antes de operación pública.

Conciliación: transacción RepeatableRead, consulta tenant/doc/receipts/reserva;
hashes múltiples o schema inválido/sin id requieren revisión manual. Distintos
hashes no se interpretan automáticamente como contradicción fiscal. No polling,
consulta externa, rechazo definitivo, orden fiscal por timestamp, TTL, retry
POST ni liberación. UNKNOWN_RESULT conserva reservas tras reinicio/timeout.

Webhook: validateAlanubeWebhookEnvelope es un envelope LOCAL de pruebas/intake,
no un contrato wire. Valida claves, formatos, fechas, payload y límites de entrada;
ingestor exige correlación id conocido y replay. No endpoint público nuevo, auth
endpoint ni algoritmo HMAC/headers inventados. Una notificación sin autenticidad
solo observa. Permisos HTTP previos intactos; futura exposición necesita autorización.

## Migración, backup y datos UAT

Target comprobado antes de escrituras: contenedor fullpos_alanube_uat_postgres,
binding exclusivo 127.0.0.1:56550, current_database()=fullpos_alanube_uat. Auditoría
previa: 213 documentos, 51 reservas, 78 eventos y 0 intentos de tenant incoherente.

Backup: artifacts/uat-backups/ecf_before_phase99_evidence_20261014.dump.
661282 bytes; SHA-256
ED9C31727939C17BF9DAC5A8E39F3A71A00876DAC08043933D593823BDAC76B8.
pg_dump custom; lectura completa pg_restore --file=/dev/null antes de aplicar,
copia local y hash. No se ensayó restauración a otra base.

Única migración nueva y aplicada SOLO UAT:
20261014200000_ecf_evidence_quarantine. Ensayo de SQL completo sustituyendo COMMIT
por ROLLBACK PASS; deploy PASS al primer intento. SQL aplicado no editado. Prisma
mapping de FK/onUpdate alineado con SQL. 35 migraciones, status actualizado.
migrate diff read-only no detecta cambios en la tabla nueva; persisten diferencias
históricas de defaults/índices en intentos y otros modelos ya documentadas en 81–90.
No se aplicó SQL de drift, db push, reset ni backfill.

Los receipts, documentos y ledgers sintéticos permanecen; no se desactivaron
triggers ni se eliminaron fixtures previos. Tras cuatro ejecuciones UAT de este
bloque (una fallida inicial y tres aprobadas, la última amplió ambigüedad remota):
8 empresas ecf-91-100-*, 59 receipts; total UAT 126 reservas y 192 eventos.
0 receipts cruzados de tenant
o intento/documento. Esas empresas son fixtures locales, no registros Alanube.

Recuperación: conservar respaldo y datos posteriores; ensayar restauración en
otra UAT aislada antes de cualquier sustitución autorizada. No revertir mediante
DROP/DELETE ni editar SQL aplicado. No se hizo rollback destructivo.

## Pruebas y correcciones declaradas

```text
npm --workspace apps/api test -- --testPathPatterns=ecf-evidence.policy.spec
PASS: 21 tests unitarios.

npm --workspace apps/api test -- --testPathPatterns=src/ecf
PASS: 29 suites / 201 tests; 3 suites / 68 PostgreSQL omitidos aquí.

./scripts/isolated-uat/test-ecf-postgres.ps1
PASS final: 3 suites / 68 tests (12 idempotencia + 28 E34 + 28 evidencia).

npm --workspace apps/api test
PASS: 103 suites / 940 tests; 4 suites / 76 tests omitidos.
68 PostgreSQL ejecutados aparte; 8 opt-in ajenos no verificados.

npm run api:build
PASS final: Prisma generate 5.22.0 y tsc.

npm --workspace apps/api exec -- tsc -p tsconfig.build.json
PASS separado.

npx prisma validate
PASS, apps/api con entorno UAT verificado.

npx prisma migrate deploy
PASS, una migración nueva SOLO UAT.

npx prisma migrate status
PASS: 35 migraciones, base actualizada.

npx prisma migrate diff --from-schema-datamodel prisma/schema.prisma --to-schema-datasource prisma/schema.prisma --script
Diagnóstico read-only, drift histórico no aplicado.

node scripts/isolated-uat/prepare-alanube-contracts.cjs --check
PASS: schemas/hashes/generados inalterados.

node (smoke JavaScript compilado con fetch bloqueado)
PASS: verificador bloqueado, tenant/metadata rechazados antes de DB;
network=0, database=0. No API iniciada ni solicitud remota.

git diff --check
PASS; aviso LF/CRLF de schema sin error de whitespace.

git diff --name-only -- <rutas tradicionales protegidas>
Vacío: Flutter/sales/cash/inventory/purchases/cotizaciones/tax/license.
```

Fallas propias corregidas: primera UAT falló por retorno PostgreSQL void de
pg_advisory_xact_lock no deserializable por Prisma; se hizo cast a text. El fixture
E34 omitía estado local y log de evidencia exigidos: se corrigió el fixture, no
se relajó el trigger. Build concurrente con UAT dio EPERM al renombrar DLL Prisma;
causa compatible con carga simultánea por nuestra prueba. Tras terminar UAT,
build secuencial PASS sin matar procesos ni borrar DLL. Ninguna prueba deshabilitada.

## Cobertura pedida 1–20 y naturaleza de pruebas

- 1–3: confianza sintética/sin autenticidad y contrato de prueba. Unit usa firma
  efímera real bajo TEST_ONLY; PostgreSQL usa verificador simulado TEST_ONLY para
  comprobar persistencia. Ninguno demuestra autenticidad Alanube.
- 4–10: referencias desconocidas/contradictorias, otro tenant, replay, duplicados,
  orden y no transiciones: PostgreSQL real + máquina de estados existente.
- 11–13: timeout/red/reinicio: eventos internos sintéticos y recreación real del
  cliente/servicio; no crash de proceso operativo ni respuesta remota real.
- 14–16: corrupción/hash/schema: unit + PostgreSQL real; bytes no persistidos.
- 17: webhook sin autenticación: envelope sintético, receipt real bloqueado;
  sin receptor público y sin firma oficial simulada como si fuese Alanube.
- 18–19: referencia fiscal inválida, original E34 y reservas: suites E34 y
  evidencia en PostgreSQL; UNKNOWN_RESULT sigue reteniendo saldo.
- 20: contratos incompletos/guard E34: regresión preemisión existente, sin
  habilitación de flags. Verificador no crea autoridad fiscal.

PostgreSQL demuestra locks/unique/FK/triggers/persistencia/tenant/replay/ledger;
unit/mocks demuestran lógica e interfaces. No prueban certificación DGII ni
respuesta real de Alanube. Total único ejecutado backend+PG: 1008 tests; los 201
e-CF están incluidos en 940, no sumarlos otra vez.

## Archivos de este bloque (17)

```text
apps/api/prisma/schema.prisma
apps/api/prisma/migrations/20261014200000_ecf_evidence_quarantine/migration.sql (nuevo)
apps/api/src/ecf/documents/ecf-evidence.policy.ts (nuevo)
apps/api/src/ecf/documents/ecf-evidence-authenticity.service.ts (nuevo)
apps/api/src/ecf/documents/ecf-evidence-ingestion.service.ts (nuevo)
apps/api/src/ecf/documents/ecf-evidence.policy.spec.ts (nuevo)
apps/api/src/ecf/documents/ecf-evidence-postgres.integration-spec.ts (nuevo)
apps/api/src/ecf/ecf.module.ts
apps/api/src/ecf/alanube/alanube-webhook.contract.ts
apps/api/src/ecf/alanube/alanube-reconciliation.service.ts
docs/ECF_ALANUBE_MASTER_CONTEXT.md
docs/ECF_ALANUBE_NEXT_STEPS.md
docs/ECF_ALANUBE_FIRST_SANDBOX_ISSUANCE_PLAN.md
docs/ECF_ALANUBE_TECHNICAL_INFORMATION_REQUEST.md
docs/ECF_ALANUBE_EVIDENCE_TRUST_MATRIX.md (nuevo)
docs/ECF_ALANUBE_PROVIDER_BLOCKERS.md (nuevo)
docs/ECF_ALANUBE_PHASES_91_100_FINAL_AUDIT.md (nuevo)
```

e-CF ya era untracked y schema/AGENTS/packages/etc tenían trabajo anterior.
No atribuir el diff global ni archivos históricos a este bloque. Scripts y
schemas/matriz generados previos no cambiados. Backups locales ignorados.

## Contratos, seguridad y siguiente acción

Fuentes y revisión detallada E34 en [bloqueos](ECF_ALANUBE_PROVIDER_BLOCKERS.md).
[GET E34](https://developer.alanube.co/reference/checkcreditnotes) existe:
no se afirma que no haya endpoint. No basta para verificar garantía de resultados.
[Webhook DOM](https://developer.alanube.co/changelog/api-fe-dom-mejoras-en-lo-webhooks-para-notificaciones-de-documentos-electr%C3%B3nicos)
documenta auth previa, no la damos por contrato completo de firma.
[E34](https://developer.alanube.co/reference/createcreditnotes) conserva estructura
conocida; no se inventaron reglas nuevas por conceptos/impuestos/plazos.

Autenticidad, conciliación remota, webhook operativo y conformidad DGII siguen
PARTIAL/BLOCKED. Emisión cero, Sandbox/producción NO-GO. Alanube autenticado solo
histórico fase31; cero nuevas llamadas autenticadas. Sin contacto DGII, altas,
numeración ni envío automático de solicitud técnica.

Producción sin acceso ni cambios; POS/Flutter/offline/sync/caja/turnos/inventario/
compras/cotizaciones/impresión/licencias/NCF/ITBIS intactos. taxEnabled/ncfEnabled
sin cambio; e-CF opcional/desactivado, kill switches y POST bloqueados.
Sin commit/push/merge/rebase/reset/clean/stash/deploy ni otros worktrees.

Próxima acción: obtener confirmaciones oficiales de autenticidad/consulta/webhook
y reglas E34; diseñar binding verificable de primera respuesta y custodia de
artefactos; después revisar orquestación fiscal y permisos. No emitir ni conectar
receipts no autenticados a una transición fiscal.

Herramientas usadas: terminal/PowerShell, git, rg, apply_patch, Node/npm/Python,
Jest, Prisma/tsc, Docker/psql/pg_dump/pg_restore y web pública. Context7 no expuesto
(catálogo consultado); sin subagentes, Figma, Playwright o Vision.

Auditoría final de secretos: 119 archivos e-CF/scripts/docs/migraciones, 0 archivos
señalados por patrones de claves privadas, JWT y conexiones con credenciales.
Es un escaneo acotado, no una garantía exhaustiva; sin abrir secretos ni FULLTECH.txt.
Checksum del SQL aplicado coincide con _prisma_migrations. Auditoría de datos:
0 receipts de confianza elevada y 0 originales sintéticos sobreacreditados.
Rama/HEAD finales confirmados sin cambio; git diff --check PASS.
