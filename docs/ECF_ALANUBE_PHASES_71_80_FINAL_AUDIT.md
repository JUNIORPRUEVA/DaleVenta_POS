# Fullpos Cloud — auditoría fases 71–80 y continuidad fase66

Fecha: 2026-10-14. Worktree exclusivo FULLPOS-ECF-ALANUBE, rama
feature/ecf-alanube. HEAD conservado:
`6b3e38ed57bc53f9a55e66cf2eccf315afffd3f1`.

## Resultado

Implementada conformidad estructural ejecutable del subconjunto soportado DOP
E31/E32/E34; metadata fiscal explícita, mapper corregido, schemas verificados,
interpretación conservadora de respuestas y barrera preemisión reforzada.
No se declara integración fiscal completa ni autorización de emisión.

| Fase | Estado | Evidencia y límite |
| --- | --- | --- |
| 71 | PASS | Tres snapshots de hash esperado, DOM/OpenAPI/version/endpoints verificados; coinciden con HTML oficial actual. Matriz y generador reproducibles. |
| 72 | PASS | Auditoría por campo E31 en matriz; nombres oficiales, required, tipos, fechas, ITBIS/exentos/descuentos y metadata probados. Opcionales/condicionales no soportados explícitos. |
| 73 | PASS | E32 separado: sin sequenceDueDate obligatoria ni buyer incondicional; fixtures válidos/invalidaciones. No se asume equivalencia con E31. |
| 74 | PARTIAL | E34 referencia/fecha/código, patrón excluyendo E33/E34 y motivo mapeados/probados. JSON Schema no acredita existencia, pertenencia ni saldo del original; evidencia económica pendiente. Emisión siempre bloqueada. |
| 75 | PASS | DTO metadata separado, núcleo interno reutilizado, payload por lista explícita oficial. Sin aliases internos ni numeración/pago ficticios predeterminados. |
| 76 | PASS | Ajv contra schemas oficiales derivados con refs resueltas; required/tipos/estructuras/fechas/enums/rangos/deriva. Conformidad estructural del subconjunto; no aceptación proveedor ni todas las condiciones fiscales textuales. |
| 77 | PASS | Respuesta por tipo/status validada; id ULID y estado explícitos para observación. HTTP, timeout/red, auth, rate limit, validación, 5xx e inesperadas cubiertos. Cero estados aceptados generados. |
| 78 | PASS | Empresa autenticada/documento/RNC/company.id proveedor, permisos, autorización, Sandbox, estado, certificación, identidad v2, fingerprints, payload revalidado y registry completo obligatorios. Pruebas prueban transporte/secret resolver no invocados. |
| 79 | PASS | e-CF, PostgreSQL, build completo, tsc, Prisma validate/status, smoke compilado, regresión, diff y auditoría de patrones secretos. Omisiones y fallos iniciales declarados. |
| 80 | PASS | Este informe y contexto maestro, próximos pasos y plan de emisión actualizados. |

Fase66: brecha de nombres/metadata/validación estructural corregida para los casos
soportados. Continúa PARTIAL para conformidad fiscal integral: semántica
condicional completa, evidencia del original E34, variantes/resolución fiscal y
garantías externas no están demostradas. No se vuelve a ocultar esta limitación.

## Contratos oficiales y matriz verificable

OpenAPI 3.0.3, API FE DOM 1.0.0, país DOM. Consulta 2026-10-14.
Procedencia: `document.api.schema` de `ssr-props` en HTML público. No tokens,
Try It ni API autenticada. La comparación de los tres JSON actuales con los
snapshots conservados resultó MATCH. No se detectó cambio entre fase65 y hoy.

| Tipo / fuente oficial | Endpoint | SHA-256 del snapshot original |
| --- | --- | --- |
| [E31](https://developer.alanube.co/reference/createinvoicefiscals) | POST /fiscal-invoices | 8E665554B8EFC8F41189449E64327F5888F44B05625E48B90BD09F6B8EAE3459 |
| [E32](https://developer.alanube.co/reference/createinvoices) | POST /invoices | 483A7220F503AF4FAEEE1D42CF2124449CF8524105F94172D633099CEAF836DF |
| [E34](https://developer.alanube.co/reference/createcreditnotes) | POST /credit-notes | 7B118AC204B241B79E5F4EAF7D2445C094933B6A979D83BDBB56AB53B18698E0 |

Fuentes originales locales: artifacts/alanube-public-contracts/*.openapi.json.
La matriz ECF_ALANUBE_CONTRACT_MATRIX_PHASES_71_74.md enumera todos los campos
request: obligatorio/opcional/condicional y soportado/no soportado. Un required
en objeto opcional solo aplica al incluir el padre. Condiciones textuales no
son automáticamente equivalentes a restricciones JSON Schema.

Generación: prepare-alanube-contracts.cjs verifica hashes, país/título/versión,
resuelve únicamente refs locales (falla si faltan o son cíclicas/externas), conserva
restricciones y elimina anotaciones sin valor validatorio. Los schemas se
compilan a JavaScript con el API; no se cargan archivos ignorados en runtime.
`--check` detecta deriva de fuente generada/matriz sin escribir ni conectarse.

Fingerprints SHA-256 de constraints request + responses resueltas:

- E31: 6aebf0b7109f3e6d866de44eb171605e2f5e7600e45e13ba3c02b264a08639ba.
- E32: b3436ce66bb57ab45c957a9e28cbc68c3595bf1a85605654d7b0d0608bf4bac6.
- E34: a54a0c4fb63538d32b9242c87bc8bbc9888f5b44fbe922fd2eb53561765727dd.

No se mezcló idempotencia Colombia con DOM. Las referencias históricas a schema
ausente o mapper incompatible están superadas para el subconjunto probado, no
se reescribieron los informes históricos para borrar sus limitaciones.

## DTO, mapping y validación

Modelo interno EcfFiscalDocument sin alteraciones. EcfIssuanceMetadata separado:
encf explícito, paymentType, incomeType según tipo, sequenceDueDate E31,
creditNoteIndicator/modificationCode E34, paymentDeadline para crédito y
alanubeCompanyId explícito de configuración confiable. No se generan secuencias.

Mapping: sender rnc/companyName/stampDate, buyer rnc/companyName, company.id,
totales por tasas, ITBIS, exentos, líneas y subDiscounts monetarios. E34 usa
ncfModified/ncfModifiedDate/modificationCode/reasonForModification. No transmite
companyId local, notas internas, refundKind, hashes ni auditoría como payload.

Se reutilizan Decimal/money/sumMoney del núcleo existente. No cambio a ITBIS ni
redondeo del POS. Metadata ausente produce BLOCKED_PENDING_SCHEMA con rutas de
errores; válida produce CONFIRMED_PARTIAL, nunca CONFIRMED_OFFICIAL. Moneda
extranjera/NON_BILLABLE no se serializan silenciosamente: fallan explícitamente.
Otras funcionalidades no soportadas constan en matriz, no tienen defaults.

Ajv 8.17.1 y ajv-formats 3.0.1 añadidos como dependencias necesarias y fijadas;
no había validador JSON Schema instalado. Sin coerción/defaults/removal ni
schemas remotos. Overlay de seguridad local additionalProperties=false sobre
objetos request documentados; no se afirma que esa restricción proceda de Alanube.
ULID validado localmente; fechas reales verificadas. strictTypes=false admite
maxLength sobre números en OpenAPI (ese keyword solo restringe strings); los
tipos y restricciones numéricas sí se validan. MultipleOf monetario usa precisión
acotada para representación binaria; aritmética sigue en Decimal.

Además: identidad de emisor, e-NCF del tipo correcto, comprador E31/E32 de alto
importe, vencimiento de pago a crédito, modificación textual E34 con total cero
y límite local conservador de ítems. La regla E32 de comprador >=250000 conserva
la política previa más estricta; no cambia reglas de ventas tradicionales.

## Respuestas, errores y seguridad

Schemas documentados 201/400/404/500 resueltos por tipo. Sin contexto de tipo,
schema documentado o cuerpo conforme, no hay evidencia suficiente de éxito.
Los cuerpos de respuesta tienen propiedades no requeridas: se exige id/estado
explícitos antes de exponer una observación. Un cuerpo vacío nunca crea aceptación.

REGISTERED/TO_SEND/WAITING_RESPONSE/TO_NOTIFY/FINISHED son procesamiento. Incluso
legalStatus ACCEPTED observado en E32 permanece UNKNOWN_RESULT localmente:
no se convierte automáticamente en aceptación fiscal. No se exponen mensajes
crudos del proveedor. Códigos ALANUBE_* son locales, no códigos fiscales inventados.

El clasificador solo permite retryable para READ explícito; EMISSION por defecto
no reintenta. La política de reintentos fiscales y el bloqueo POST de cliente y
transporte se mantienen. No se conectaron worker, sender, webhook ni conciliación.

La barrera exige dos fingerprints: snapshot interno e inmutable payload. Un
futuro sender deberá persistir/obtener esos valores y configuración desde datos
confiables por tenant, nunca aceptar estos campos como declaraciones del cliente.
La preparación actual no persiste automáticamente metadata/payload externo;
su flujo de persistencia/autorización futuro sigue siendo un pendiente explícito.

## Validaciones ejecutadas

```text
npm install --workspace apps/api --save-exact ajv@8.17.1 ajv-formats@3.0.1 --ignore-scripts --no-audit --no-fund
PASS; 5 paquetes instalados, sin upgrades de dependencias previas.

node scripts/isolated-uat/prepare-alanube-contracts.cjs
PASS; source y matriz generados de snapshots de hash esperado.

node scripts/isolated-uat/prepare-alanube-contracts.cjs --check
PASS; hashes y fuentes generadas MATCH.

npm --workspace apps/api test -- --testPathPatterns=src/ecf
PASS final: 27 suites / 161 pruebas. 12 PostgreSQL opt-in omitidas aquí.

./scripts/isolated-uat/test-ecf-postgres.ps1
PASS: 12 pruebas reales PostgreSQL; idempotencia/concurrencia/aislamiento/estados/
timeout/recreación/historial/restricciones y migración en tablas temporales.

npm run api:build
PASS final; Prisma generate 5.22.0 + TypeScript.

npm --workspace apps/api exec -- tsc -p tsconfig.build.json
PASS separado.

npx prisma validate
PASS, apps/api, entorno UAT verificado.

npx prisma migrate status
PASS, base aislada actualizada; 32 migraciones. No migrate deploy en esta tarea.

npm --workspace apps/api test
PASS final: 101 suites / 900 pruebas, 2 suites / 20 pruebas omitidas.
12 PostgreSQL se ejecutaron por separado; 8 opt-in ajenas no verificadas.

Smoke local mediante node sobre apps/api/dist
PASS: siete payloads sintéticos, schema válido, CONFIRMED_PARTIAL, POST bloqueado,
cero fetch y cero resolución de secretos. No API dev server ni red externa.

git diff --check
PASS; solo aviso previo LF/CRLF del schema Prisma, sin editarlo aquí.

Auditoría Python final de patrones secretos (claves privadas/JWT/URLs con password)
0 archivos señalados en 103 archivos, incluido este informe.
Sin abrir .env, DPAPI ni FULLTECH.txt. No equivale a análisis exhaustivo de secretos.
```

Fallos durante implementación: tipo unknown entregado a compile Ajv y cast de
Object.fromEntries fueron corregidos con tipos explícitos; tests anteriores que
aceptaban drafts sin metadata o esperaban aliases se actualizaron para validar
el contrato real y conservar pruebas negativas. Un test de texto de blockers
falló al actualizar el estado del schema; se corrigió descripción y se preservó
su aserción. No se deshabilitaron tests ni se rebajaron guards para pasar.
Python urllib recibió HTTP403 del sitio público; PowerShell y web sí pudieron
consultarlo. No fue un fallo de autenticación Alanube ni se añadieron credenciales.

## UAT y Git

Contenedor fullpos_alanube_uat_postgres, binding 127.0.0.1:56550→5432,
current_database fullpos_alanube_uat, verificados antes de escribir.
Backup previo: artifacts/uat-backups/ecf_before_phase79_20261014.dump,
582346 bytes; SHA-256
124766F9533361B41F173AC88EE587F9C6A4EC6248B9FA51B3CBEC064FED6CE7.
pg_restore leyó el archivo completo; no se hizo ensayo de restauración.
Sin migraciones nuevas ni cambios a Prisma schema. Fixtures eliminados por UUID
exclusivos; cero documentos e-CF y cero compañías fixture al finalizar.

Worktree/rama/HEAD originales. Cambios locales anteriores preservados, incluidos
AGENTS.md, .gitignore, schema, app.module, uat-safety y migraciones anteriores.
No se tocaron otros worktrees ni se agregaron archivos al índice Git.
Sin commit/push/merge/reset/clean/stash/rebase/deploy.

## Archivos de esta tarea (no atribuir todo el directorio untracked)

```text
apps/api/package.json
package-lock.json
apps/api/src/ecf/alanube/contracts/alanube-dom-schemas.generated.ts (nuevo)
apps/api/src/ecf/alanube/alanube-schema-validator.ts (nuevo)
apps/api/src/ecf/alanube/alanube-contract.fixtures.ts (nuevo, solo usado por tests)
apps/api/src/ecf/alanube/alanube-contract-validation.spec.ts (nuevo)
apps/api/src/ecf/alanube/alanube-official-required-fields.ts
apps/api/src/ecf/alanube/alanube-official-required-fields.spec.ts
apps/api/src/ecf/alanube/alanube-contract-matrix.ts
apps/api/src/ecf/alanube/alanube-contract-matrix.spec.ts
apps/api/src/ecf/alanube/alanube-safe-http.client.ts
apps/api/src/ecf/alanube/alanube-safe-http.client.spec.ts
apps/api/src/ecf/alanube/alanube-response-interpreter.ts
apps/api/src/ecf/alanube/alanube-response-interpreter.spec.ts
apps/api/src/ecf/alanube/alanube-error-classifier.ts
apps/api/src/ecf/alanube/alanube-error-classifier.spec.ts
apps/api/src/ecf/ecf-contract-registry.ts
apps/api/src/ecf/ecf-pre-emission.guard.ts
apps/api/src/ecf/ecf-pre-emission.guard.spec.ts
apps/api/src/ecf/fiscal-core/alanube-dom.contract.ts
apps/api/src/ecf/fiscal-core/alanube-dom.mapper.ts
apps/api/src/ecf/fiscal-core/ecf-fiscal-core.spec.ts
scripts/isolated-uat/prepare-alanube-contracts.cjs (nuevo)
docs/ECF_ALANUBE_CONTRACT_MATRIX_PHASES_71_74.md (nuevo)
docs/ECF_ALANUBE_PHASES_71_80_FINAL_AUDIT.md (nuevo)
docs/ECF_ALANUBE_MASTER_CONTEXT.md
docs/ECF_ALANUBE_NEXT_STEPS.md
docs/ECF_ALANUBE_FIRST_SANDBOX_ISSUANCE_PLAN.md
```

## Bloqueos, riesgos y siguiente paso

Falta prueba económica/tenant del original E34 y saldo disponible, persistencia
del snapshot externo/metadata para un sender futuro, condiciones fiscales fuera
del subconjunto DOP, variantes síncronas/asíncronas y criterios probados de
aceptación/rechazo fiscal. Los schemas públicos tienen límites: condiciones en
prosa y respuestas sin campos required; no bastan para declarar validez legal.

Garantías externas pendientes: idempotencia DOM, resultado desconocido sin id,
conciliación, firma/replay webhook, rate limits, certificación, reseller,
activación y numeración Sandbox. La solicitud técnica anterior sigue preparada,
no enviada. Próxima acción: revisar la matriz y resolver exactamente esas reglas
y evidencias; luego diseñar persistencia/autorización del futuro sender con
alcance separado y pruebas. No activar switches ni emitir para “probar”.

Alanube: solo autenticación histórica fase31; ninguna nueva llamada autenticada.
DGII: sin contacto, sin certificación verificada de clientes. Emisión: bloqueada,
cero documentos enviados, cero secuencias consumidas, cero empresas registradas.
Producción: sin acceso ni cambios. POS tradicional/Flutter/offline/caja/inventario/
NCF/ITBIS/licencias e indicadores taxEnabled/ncfEnabled: sin modificaciones.

Herramientas: terminal/PowerShell, git, lectura/rg, apply_patch, Node/npm,
Python, web pública, Docker/psql/pg_dump/pg_restore, Jest, Ajv, Prisma y tsc.
Context7 no expuesto: se consultó documentación oficial
[Ajv v8](https://ajv.js.org/guide/schema-language.html) y
[strict mode](https://ajv.js.org/strict-mode.html). Sin Figma/Playwright/Vision ni
subagentes. No UI modificada; no corresponde validación visual/hardware.

## Estado

NO-GO para conformidad fiscal integral/primera emisión (66 y 74 PARTIAL).
GO del bloque local validado y documentación entregada. Ningún check final
ejecutado queda fallando; las limitaciones funcionales/externas se mantienen
explícitas y bloqueadas. Esto no autoriza emisión ni producción.
