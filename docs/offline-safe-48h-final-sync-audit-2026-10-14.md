# FullPOS Cloud Offline Safe 48h - Auditoria final de sincronizacion

Fecha: 2026-10-14
Rama: `feature/offline-safe-48h`
Repositorio: `C:\src\fullpos-offline-safe-48h`

## 1. Arquitectura real de sincronizacion

La sincronizacion offline verificada usa estos componentes:

- Flutter Windows escribe en SQLite local: `.uat\windows-app-root\databases\fulltech_offline.db`.
- Las ventas offline se guardan atomicamente en `offline_sales`, `offline_sale_items`, `offline_sale_payments`, `offline_inventory_intents` y `pending_actions`.
- `SyncQueueService` procesa `pending_actions` por empresa/usuario, recupera acciones `syncing` estancadas, aplica backoff, clasifica errores permanentes/transitorios y no elimina una accion hasta que el handler termina sin error.
- La API UAT responde en `http://127.0.0.1:46548`.
- PostgreSQL UAT corre en `127.0.0.1:56548`, contenedor `fullpos_offline_safe_48h_postgres`, base `daleventa_offline_safe_48h_uat`.

## 2. Tipos de operaciones locales encontradas

Fotografia SQLite inicial y posterior al smoke backend:

| Tabla | Conteo |
| --- | ---: |
| `pending_actions` | 1 |
| `offline_sales` | 8 |
| `offline_sale_items` | 20 |
| `offline_sale_payments` | 8 |
| `offline_inventory_intents` | 20 |
| `cache_entries` | 344 |

Estados encontrados:

| Tipo | Estado | Permanente | Conteo | Intentos maximos |
| --- | --- | ---: | ---: | ---: |
| `quotes.create` | `failed` | 1 | 1 | 41 |

Ventas locales:

| Estado | Conteo | Total |
| --- | ---: | ---: |
| `synced` | 8 | RD$3010.00 |

Intentos de inventario:

| Estado | Conteo |
| --- | ---: |
| `synced` | 20 |

## 3. Operaciones permitidas por politica

Evidencia de UAT valida ventas offline, pagos efectivo/transferencia/mixto en cliente Flutter, catalogo cacheado, historial de ventas offline, turnos/caja en modo local, clientes cacheados y cotizaciones locales.

Productos offline y ajustes de stock offline existen en UAT y tienen pruebas Flutter, pero quedan como capacidad a aprobar explicitamente antes de produccion porque su idempotencia de base de datos no esta blindada al mismo nivel que ventas/caja.

## 4. Desviaciones detectadas

Se encontro una cotizacion offline ya existente con `customerId` local temporal:

- Accion: `quotes.create:local_quote_1791944878261619`
- Estado: `failed`
- Permanente: `1`
- Error: `customerId must be a UUID`

No se modifico ni elimino esa operacion pendiente para preservar evidencia manual.

## 5. Identificadores y dependencias

Las 8 ventas manuales conciliadas conservan:

- `client_request_id` estable.
- `cashSessionId` original `b58f3473-2933-49ab-8ba8-299f9544eb5d`.
- Totales de venta iguales a la suma de lineas.
- Movimientos de inventario vinculados por `source_id = Sale.id`.

El smoke HTTP/PostgreSQL adicional creo 3 ventas ficticias con `clientRequestId` unico, reenvio cada venta antes y despues de cerrar el turno original y abrir uno nuevo, y verifico que el backend devolvio el mismo `saleId`.

## 6. Protecciones de idempotencia

Protecciones verificadas en PostgreSQL:

- `"Sale_company_id_client_request_id_key"` unico en `(company_id, client_request_id)`.
- `cash_movements_company_operation_key` unico en `(company_id, operation_id)`.
- `idx_pending_actions_scope_idempotency` unico local en SQLite por `(company_id, idempotency_key)`.
- `idx_offline_sales_scope_request` unico local en SQLite por `(company_id, client_request_id)`.
- `idx_offline_inventory_intents_once` unico local en SQLite por `(company_id, idempotency_key)`.

Riesgo observado: `Product`, `Cotizacion` e `inventory_movements` no muestran una restriccion unica PostgreSQL equivalente por `operationId`/`clientRequestId`.

## 7. Riesgos de duplicacion

No se encontraron duplicados para las 8 ventas manuales: la consulta de duplicados por `client_request_id` devolvio 0 filas.

Riesgo pendiente: productos, cotizaciones e inventario dependen mas de logica de servicio que de una restriccion unica de base de datos. Para produccion conviene agregar una identidad idempotente persistida por operacion.

## 8. Riesgos de perdida

No se detecto perdida de ventas: SQLite tiene 8 ventas `synced` y PostgreSQL contiene exactamente una venta por cada `client_request_id` conciliado.

La operacion `quotes.create` fallida permanece visible y no fue marcada como sincronizada falsamente.

## 9. Riesgos de inventario

Las 8 ventas manuales conciliadas generaron 20 movimientos de inventario, uno por linea rastreada. Los conteos por venta coinciden con sus lineas:

| `client_request_id` | Total | Lineas | Movimientos inventario |
| --- | ---: | ---: | ---: |
| `sale_req_1791926291940078` | 270.00 | 2 | 2 |
| `sale_req_1791932798620637` | 240.00 | 2 | 2 |
| `sale_req_1791933387374579` | 300.00 | 2 | 2 |
| `sale_req_1791939610170918` | 250.00 | 2 | 2 |
| `sale_req_1791944809139862` | 670.00 | 3 | 3 |
| `sale_req_1791975855363341` | 490.00 | 4 | 4 |
| `sale_req_1791975864746829` | 320.00 | 2 | 2 |
| `sale_req_1791976494630042` | 470.00 | 3 | 3 |

Riesgo pendiente: ajuste de stock offline aun necesita idempotencia PostgreSQL explicita antes de GO produccion.

## 10. Riesgos de caja

Las 8 ventas manuales quedaron en un solo turno original:

- `cashSessionId`: `b58f3473-2933-49ab-8ba8-299f9544eb5d`
- Ventas: 8
- Total: RD$3010.00

El smoke HTTP/PostgreSQL verifico reintento de venta despues de cerrar el turno original y abrir uno nuevo: las ventas siguieron ligadas al turno original.

## 11. Pruebas ejecutadas

- Health API: `GET http://127.0.0.1:46548/health` -> `status: ok`.
- Health DB: `GET http://127.0.0.1:46548/health/db` -> `db: ok`.
- Backup SQLite consistente por API `sqlite3.Connection.backup`.
- Auditoria SQLite de tablas, estados y pendientes.
- Auditoria PostgreSQL de tablas, indices y conciliacion de ventas.
- `flutter analyze`.
- `flutter test` completo.
- `flutter test` enfocado en cotizaciones, ventas recientes, catalogo offline y turnos.
- `npx prisma validate` con `DATABASE_URL` local ficticia.
- `npm --workspace apps/api test -- sales.service.tenant.spec.ts sales.service.inventory-optional.spec.ts cash.close-hardening.spec.ts`.
- `npx tsc -p tsconfig.build.json`.
- `powershell -NoProfile -ExecutionPolicy Bypass -File scripts/uat/run-sync-integrity-smoke.ps1`.
- `git diff --check`.

## 12. Estado SQLite antes/despues

Antes y despues del smoke backend la SQLite manual quedo igual:

- `pending_actions`: 1
- `offline_sales`: 8
- `offline_sale_items`: 20
- `offline_sale_payments`: 8
- `offline_inventory_intents`: 20
- `cache_entries`: 344

Backup creado:

`C:\src\fullpos-offline-safe-48h\.uat\evidence\fulltech_offline_backup_2026-10-14_phase10.db`

## 13. Estado PostgreSQL antes/despues

Las 8 ventas manuales ya estaban sincronizadas al auditar. El smoke backend agrego 3 ventas ficticias UAT adicionales bajo `runId=fase8-1791980784658`.

Resultado smoke PostgreSQL:

- Ventas: 3
- `clientRequestId` distintos: 3
- Turnos distintos: 1
- Total: RD$360.00
- Items: 3
- Movimientos inventario: 3

## 14. Operaciones conciliadas

Conciliadas:

- 8 ventas manuales Flutter/SQLite/PostgreSQL.
- 20 lineas de venta locales contra 20 lineas PostgreSQL.
- 20 movimientos de inventario locales contra movimientos PostgreSQL por venta.
- 8 pagos locales.
- 1 turno de caja preservado para las 8 ventas manuales.
- 3 ventas ficticias backend con reintentos antes/despues de cambio de turno.

## 15. Operaciones sin conciliar

- `quotes.create:local_quote_1791944878261619`: permanece `failed`/`permanent` por `customerId must be a UUID`.

No fue borrada ni reintentada manualmente para no alterar evidencia existente. La correccion evita que nuevas cotizaciones con cliente local vuelvan a generar ese payload invalido.

## 16. Correcciones realizadas

- `CotizacionModel.toCreateDto()` ahora solo envia `customerId` si es UUID remoto valido.
- Si el cliente es local/no conciliado, se conserva `customerName` y `customerPhone` pero no se envia el id temporal al backend.

## 17. Pruebas de regresion

Agregadas:

- `create DTO omite customerId local no conciliado`.
- `create DTO conserva customerId UUID remoto`.
- `historial offline devuelve cotizaciones locales sin tocar red`.

Validadas dentro del archivo `test/modules/cotizaciones/cotizaciones_local_repository_tenant_test.dart`.

## 18. Riesgos pendientes

- La cotizacion permanente existente necesita decision operativa: reencolar con payload corregido o mantener para revision, sin borrar evidencia.
- Producto offline y ajuste de stock offline requieren una identidad idempotente persistida en PostgreSQL antes de GO produccion.
- `npm run api:build` no pudo completar `prisma generate` por `EPERM` al renombrar `query_engine-windows.dll.node`, probablemente por cliente Prisma en uso durante UAT; `tsc` si compilo.
- No se hizo UAT grafico nuevo durante esta fase; se usaron las ventas manuales ya generadas y pruebas tecnicas.

## 19. GO/NO-GO de sincronizacion

GO para sincronizacion de ventas offline autorizadas en UAT:

- No se perdieron ventas.
- No se duplicaron ventas.
- No cambiaron de turno.
- Totales y lineas conciliaron.
- Inventario por venta concilio.
- Reintentos backend no duplicaron.

GO con pendiente controlado para cotizaciones:

- Nuevas cotizaciones ya no enviaran `customerId` temporal.
- La cotizacion historica fallida sigue pendiente de decision humana.

## 20. GO/NO-GO de produccion

NO-GO para produccion todavia.

Motivos:

- Hay una operacion `quotes.create` historica sin conciliar.
- Productos/stock offline aun no tienen blindaje de idempotencia PostgreSQL equivalente a ventas/caja.
- El build backend completo quedo bloqueado en `prisma generate` por archivo DLL en uso, aunque la compilacion TypeScript paso.

GO para continuar UAT manual controlado con los datos actuales.
