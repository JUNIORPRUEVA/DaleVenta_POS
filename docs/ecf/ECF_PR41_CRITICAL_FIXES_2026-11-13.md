# PR41 — admisión fiscal, impresión ordinaria y Node LTS

Fecha: 2026-11-13 (America/Santo_Domingo).
Rama: `agent/ecf-predeploy-20261113`, base `production-main`.
PR: <https://github.com/JUNIORPRUEVA/DaleVenta_POS/pull/41>.

## Alcance y causa verificada

1. La capacidad POS anterior comprobaba certificación/rangos, pero podía indicar
   disponibilidad sin permisos fiscales, activación productiva o credenciales
   propias. El cobro guardaba la venta y preparaba el e-CF después.
2. Tres llamadores de ticket/PDF usaban `fiscalTaxEnabled` para decidir consultar
   la representación e-CF. Una venta ordinaria histórica con ITBIS y tipo NULL
   dependía así de una consulta electrónica innecesaria.
3. La API Docker y el gate backend utilizaban Node20. La etapa Astro ya fijaba
   Node22.23.4. La corrección unifica el backend en esa versión LTS, conservando
   Nest11 y Prisma5.22.

## Correcciones

- La política compartida de admisión comprueba empresa/proveedor, ambiente,
  certificación, permiso `prepareEcfDocuments`, activación por empresa, flags del
  servidor y presencia de credencial ACTIVE propia del RNC/ambiente. El permiso
  para cobrar u otra autorización administrativa no concede permiso fiscal.
  No se descifran secretos ni se consulta a DOSA en esta comprobación.
- El servidor revalida dentro de la transacción, bloqueando la configuración
  fiscal. Venta, inventario, numeración, auditoría de asignación y borrador fiscal
  comparten commit/rollback. Los fallos de datos fiscales y del mapeador, incluso
  después de asignar número, dejan la operación local sin confirmar.
- El envío externo queda después del commit. Si se pierde la respuesta del
  proveedor, se conserva la identidad fiscal y se utiliza la recuperación
  idempotente existente. Esto no convierte una llamada HTTP y PostgreSQL en una
  transacción distribuida ni permite borrar una venta de resultado incierto.
- Ticket y PDF consultan e-CF solo por identidad electrónica. La respuesta de
  historial añade `hasElectronicFiscalDocument` para vínculos históricos NULL,
  siempre limitados a la empresa. NORMAL sigue siendo explícitamente ordinario.
  Los impuestos y transportes de impresora conservan su implementación.
- Clientes anteriores siguen aceptándose para ventas ordinarias sin el nuevo
  campo/tipo. Los E31/E32 explícitos son la entrada de checkout atómico. La
  preparación independiente existente sigue disponible para recuperación de
  operaciones anteriores; no se modifican retroactivamente esas ventas.
- Docker builder/runner y CI backend fijan Node22.23.4; el engine admite también
  Node24 LTS para desarrollo. Los overrides qs6.17.1/multer2.5.0 se alinearon con
  las versiones que ya contenía el lock auditado. No se actualizó Nest/Prisma.
- CI usa el destino PostgreSQL desechable de la allowlist existente y ejecuta
  expresamente las regresiones de admisión/rollback y HTTP con proveedor local,
  con emisión externa apagada.

## Evidencia ejecutada

Todos los datos nuevos son sintéticos y locales. No se usó el clon restaurado
de producción para pruebas de escritura. La imagen QA se ejecutó con entrypoint
Node/npm, sin arrancar el script productivo ni ejecutar migraciones.

| Comando o comprobación | Resultado |
| --- | --- |
| `npm run api:build` | PASS |
| `npm --workspace apps/api exec -- prisma validate` | PASS |
| `npm --workspace apps/api test`, suites opt-in locales habilitadas | 278 suites /3320 PASS;101 omitidos; exit0 |
| Mismo comando con opt-in deshabilitadas | 239 suites /2874 PASS;546 omitidos; exit0 |
| `npm --workspace apps/api test -- --runTestsByPath src/sales/sales-ecf-atomic-postgres.integration-spec.ts src/ecf/documents/ecf-pos-readiness-postgres.integration-spec.ts` | 13 PASS en PostgreSQL |
| Mismas dos suites con compatibilidad financiera antigua deshabilitada | 13 PASS; checkout con contexto completo |
| Cinco suites de admisión, tenant, readiness y transacciones dentro de la imagen Linux | 63 PASS; Node22.23.4/Nest11.2.7/Prisma5.22.0 |
| `npm --workspace apps/api run test:e2e -- --runTestsByPath src/ecf/provider/dosa/dosa-emission-dispatch-http.e2e-spec.ts src/ecf/ecf-documents-http.e2e-spec.ts --forceExit` | 30 PASS; proveedor localhost |
| `npm --workspace apps/api run test:e2e -- --runTestsByPath src/ecf/pos/legacy-pos-compatibility-http.e2e-spec.ts --forceExit` | 10 PASS; clientes anteriores, compatibilidad activada/desactivada |
| `flutter analyze` | Sin incidencias |
| Regresión Flutter fiscal/impresión/ventas/cotizaciones/onboarding/auth/routing | 1119 PASS |
| Dos suites de impresión afectadas, repetidas tras ajustar fixtures | 19 PASS |
| `flutter build web --release --no-pub` | PASS; asset de configuración localhost, solo validación |
| `node scripts/release/sync_api_docker_lock.mjs --check` | 756 paquetes; versiones raíz preservadas |
| `docker build -f apps/api/Dockerfile -t fullpos-ecf-api-node22-review:20261113 apps/api` | PASS Linux, npm ci, Prisma generate y TypeScript |
| `npm audit --omit=dev --json` dentro de esa imagen | 0 avisos runtime |
| `git diff --check` | PASS |

Regresiones nuevas: flags apagados, activación por empresa ausente, cajero sin
permiso, credencial TEST insuficiente en producción, emisor inválido, fallo del
mapeador posterior a asignación, E31/E32 y sus replays, competencia por el último
número, ventas ordinarias antiguas/Normal con ITBIS, ticket sin ninguna consulta
e-CF y PDF ordinario con impuestos. También se verifica el vínculo histórico
electrónico y su aislamiento por empresa.

La regresión existente cubre conexión perdida, respuesta de salud cacheada
insuficiente, intentos interrumpidos, cola ordinaria offline, devolución E34 y
recuperación sin duplicados. La suite general sigue informando handles abiertos
antes de terminar con exit0; es una limitación previa del harness, documentada
en el checkpoint anterior. No se afirma ausencia de avisos de herramientas dev.
La primera pasada HTTP detectó la expectativa anterior de venta electrónica sin
borrador. Se corrigió el fixture para aportar su credencial propia y se cambió
la expectativa al commit atómico y al replay del mismo documento;30/30 pasaron
al repetir. Las suites HTTP conservan el `--forceExit` previo del harness.
La compatibilidad antigua se declara solo en el proceso de pruebas HTTP que
ejercita esos contratos; los13 casos de checkout pasan también sin ese permiso.

## Límites y seguridad de publicación

No merge, deploy, reinicio productivo, migración compartida, acceso productivo,
modificación de datos productivos, activación de flags globales ni emisión
externa en esta corrección. Las suites HTTP crean/migran/eliminan únicamente
sus propias bases locales desechables, sin modificar el esquema compartido.
El Dockerfile nuevo se aplicará al runtime real solo cuando el propietario
despliegue. La imagen QA conserva revisión `unknown` y no es artefacto de release.

No se modifica el transporte de impresoras ni se afirma una nueva prueba física.
La validación de conectividad es automatizada con proveedor localhost; no se
envió un comprobante a DOSA/DGII para esta revisión. La integración exige CI
verde sobre el nuevo HEAD. Producción mantiene sus gates operativos separados,
el orden API/PWA y la aceptación manual del propietario.

Evidencia local completa: directorio temporal
`fullpos-migration-audit-20261113`, archivos `fixes-*` (sin incluirlos en Git).
El inventario/checkpoint original permanece en
[auditoría previa](ECF_PREDEPLOY_AUDIT_2026-11-13.md).
Se verificaron nuevamente los218 archivos del checkout original contra su
manifiesto SHA256:0 diferencias. El parche revisado se respaldó fuera de Git.

El inventario de versiones de AGENTS.md todavía describe Node20 en CI; el
workflow/Dockerfile corregidos y esta evidencia registran Node22.23.4. No se
modificó la política de agentes para cambiar ese inventario histórico.

## Inventario de esta corrección

33 archivos sobre el HEAD anterior del PR (`6b716ce1`):

```text
.github/workflows/multi-tenant-security.yml
apps/api/Dockerfile
apps/api/package-lock.json
apps/api/package.json
apps/api/src/ecf/documents/ecf-checkout-access.spec.ts
apps/api/src/ecf/documents/ecf-checkout-access.ts
apps/api/src/ecf/documents/ecf-document-idempotency.service.ts
apps/api/src/ecf/documents/ecf-document-query.service.ts
apps/api/src/ecf/documents/ecf-emission.service.ts
apps/api/src/ecf/documents/ecf-pos-readiness-postgres.integration-spec.ts
apps/api/src/ecf/documents/ecf-pos-readiness.spec.ts
apps/api/src/ecf/documents/ecf-preparation.service.ts
apps/api/src/ecf/documents/ecf-sequence.service.ts
apps/api/src/ecf/pos/ecf-sale-fiscal.adapter.ts
apps/api/src/ecf/provider/dosa/dosa-emission-dispatch-http.e2e-spec.ts
apps/api/src/sales/sales-ecf-atomic-postgres.integration-spec.ts
apps/api/src/sales/sales.service.tenant.spec.ts
apps/api/src/sales/sales.service.ts
apps/fulltech_app/lib/core/printing/unified_ticket_printer.dart
apps/fulltech_app/lib/modules/cotizaciones/cotizaciones_screen.dart
apps/fulltech_app/lib/modules/ventas/sales_models.dart
apps/fulltech_app/lib/modules/ventas/tpv_sales_history_screen.dart
apps/fulltech_app/lib/modules/ventas/utils/sales_pdf_service.dart
apps/fulltech_app/test/core/printing/cash_drawer/cash_drawer_print_integration_test.dart
apps/fulltech_app/test/core/printing/ecf_print_representation_test.dart
docs/ARCHITECTURE.md
docs/ENVIRONMENTS.md
docs/EXECUTION_STATE.md
docs/PRODUCT_SPEC.md
docs/RELEASE.md
docs/ecf/ECF_PR41_CRITICAL_FIXES_2026-11-13.md
package-lock.json
package.json
```
