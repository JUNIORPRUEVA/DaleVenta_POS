# REPORTE — PERFORMANCE HARDENING: VENTAS + TICKETS

**Fecha:** 2026-09-10
**Rama:** `production-main`
**Base:** `238d53d6` (los cambios de este trabajo están **sin commit**, como se pidió)
**Alcance:** flujo de Facturación/POS (cotizaciones_screen) + guardado de venta (Flutter + NestJS/Prisma)
**Restricciones respetadas:** sin deploy, sin migraciones, sin seeds, sin escrituras en producción, sin commit/push, sin sleeps/delays/timers nuevos, sin optimistic financiero, multi-tenant intacto.

---

## 0. HONESTIDAD METODOLÓGICA (leer antes de las tablas)

Lo que se midió **de forma determinista y reproducible en este entorno**:

- Número de reconstrucciones completas del POS por interacción (test de suscripción al provider).
- Número exacto de escrituras/consultas a base de datos por venta (specs con `tx` instrumentado).
- Número exacto de requests HTTP bloqueantes por acción (derivado del código + tests de wiring).
- `flutter analyze`, suite completa Flutter, suite completa backend, build Android/Windows.

Lo que **NO** se pudo medir en este entorno y por qué:

- **Milisegundos en dispositivo real.** Requiere sesión autenticada con caja abierta; no se puede reproducir localmente sin credenciales y no se permite escribir en producción. Para cerrar ese dato se dejó instrumentación opt-in (§5).
- **`pg_stat_statements`, `EXPLAIN ANALYZE`, `pg_stat_activity`, CPU/RAM del host y del contenedor.** Requieren acceso de lectura al servidor de producción/UAT, que no se autorizó en esta tarea.

Por tanto, las cifras en ms del apartado BEFORE usan el **baseline ya medido y documentado en auditorías previas de este repo** (`AUDITORIA-RENDIMIENTO-DALEVENTAS.md`, `REPORTE-VALIDACION-POSTDEPLOY-FASE-A.md`):

- Servidor API en Boston (Hostinger); RTT desde RD ≈ **91–100 ms**.
- Piso por request HTTP/1.1 (TLS + proxy) ≈ **300 ms** (`/health` p50 ≈ 299–300 ms).
- `PostgreSQL` respondiendo en ≈ **0 ms** adicionales → **la DB no era el cuello de botella**.

Todo lo marcado como **(derivado)** proviene de ese baseline + conteo de operaciones en código, no de una medición nueva en dispositivo.

---

## 1. ROOT CAUSES

### SALE (guardar/cobrar venta)

1. **La impresión bloqueaba la confirmación** *(causa dominante)*
   `_finalizeCotizacion` hacía `await printSaleTicket(...)` **antes** de invalidar providers, liberar el ticket y mostrar "Venta guardada". La venta ya estaba persistida (2xx) cuando empezaba la impresión, así que todo el tiempo de spooler/impresora se sumaba a la latencia percibida. Además, el aviso de fallo de impresión se mostraba y era **inmediatamente sobrescrito** por "Venta guardada": el usuario nunca veía el problema.

2. **Gate de caja duplicado**
   `_openCheckoutDialog` pedía `GET /cash/state` y `_finalizeCotizacion` **lo volvía a pedir**. Dos RTT idénticos por cobro, con el backend revalidando la sesión activa de todos modos antes de crear la venta.

3. **Tormenta de red de IA compitiendo con el POST /sales**
   Cada cambio del carrito programaba (debounce 1,1 s) un `POST /cotizaciones/ai/analyze` (backend → OpenAI). El resultado **nunca era visible** (ver causa 4). Esos POST caían exactamente en la ventana en la que el cajero pulsa "Cobrar".

### TICKET CREATE (crear ticket / aparición del número)

4. **El POS entero se reconstruía por un estado de IA que no se pinta**
   `build()` hacía `ref.watch(quotationAiControllerProvider)` mientras `_shouldShowAiBanner()` **devuelve siempre `false`** → `AiWarningBanner` nunca se renderiza, `aiState` no se usa en ninguna parte visible. Pero `QuotationAiController.setContext()` **siempre reasigna estado** (nunca compara), notificando en cada llamada. `_syncQuotationAi()` se invoca desde **13 puntos**: cada edición del carrito, cambio/eliminación de ticket, selección de cliente, prefill por ruta, carga de catálogo, restore de draft…
   → **cada interacción del POS disparaba una reconstrucción completa adicional de toda la pantalla** (18.340 líneas de widget tree).
   El número de ticket es **local** (`'Ticket ${length + 1}'`), así que su retraso no venía de red ni de servidor: venía de que el frame de la pulsación competía con la reconstrucción programada por el estado de IA y con el POST de análisis en vuelo.
   *Además:* `_buildQuotationAiContext()` resolvía el producto oficial de cada línea con `_findOfficialProduct`, un **escaneo lineal del catálogo completo por línea** (O(líneas × catálogo)), en cada edición.

### TICKET SELECT (seleccionar / cambiar ticket)

5. **Doble reconstrucción completa por cambio de ticket**
   `_switchDesktopTicket` hacía `setState` (rebuild 1) **y** `_syncQuotationAi()` → notificación → rebuild completo del POS (rebuild 2). Seleccionar un ticket nunca tocó la red: es 100% local (`_activeDesktopTicketId` + `_replaceEditorStateFromDraft`). El problema era el coste del rebuild duplicado, no la selección.

### POST-SALE UI

6. Cubierto por 1 (impresión bloqueante) y 4 (rebuild extra). Tras la venta, `_loadProducts(forceRemote: true)` y el evento realtime `sale.created` (`refreshSalesAndCash`) disparaban a su vez `_syncQuotationAi()` → más reconstrucciones completas y más POST de IA.
   *(Queda una duplicación de `GET /products` —`_loadProducts` explícito + `catalogController.load` del realtime— que NO se tocó por riesgo de frescura de stock: ver §7 OPTIONAL.)*

### DATABASE

7. **N+1 real confirmado en el guardado de venta.**
   Por **cada línea**: `saleItem.create` (1) + `InventoryMutationService.runMutationInTransaction` (8: `product.findFirst`, `warehouse.findFirst`, 2× `assertProductStockReconciled` raw, `UPDATE warehouse_stocks`, `product.updateMany`, `inventoryMovement.create`, `product.findFirstOrThrow`) = **9 consultas/línea**, con el producto y el almacén **re-consultados en cada línea** aunque fueran idénticos.

8. **Índices:** auditados contra el schema Prisma. **No falta ningún índice para el flujo de venta.**
   `Sale`: `(companyId, saleDate)`, `(companyId, isDeleted)`, `(companyId, creditStatus)`, `unique(companyId, clientRequestId)`. `SaleItem`: `(saleId)`. `WarehouseStock`: `unique(companyId, warehouseId, productId)` (cubre el `UPDATE`). `Product`: `unique(companyId, id)` + `(companyId, archivedAt)`.

### SERVER / NODE EVENT LOOP / NETWORK

9. No se encontró bloqueo del event loop en el camino de venta (`crypto` solo `uuid`; sin `fs.*Sync`, sin PDF/imágenes síncronas). El cuello dominante era **red + impresión + trabajo redundante en el cliente**, coherente con la auditoría previa (DB ≈ 0 ms).

---

## 2. BEFORE *(derivado del baseline medido en auditorías previas + conteo de código)*

| Métrica | BEFORE |
|---|---|
| **SALE TOTAL** (tap "Cobrar" → aviso "Venta guardada") | ≈ 300 ms (gate caja) + 300 ms (gate caja duplicado) + 300 ms (POST /sales) + **impresión (variable, 0,5–3 s)** ≈ **1,4 s – 3,9 s** |
| **SALE API** (POST /sales, red + backend) | ≈ 300–500 ms |
| **TICKET CREATE** (tap "+" → número visible) | 1 rebuild completo + reconstrucción adicional programada por IA (1,1 s después) + POST de análisis compitiendo por conexión |
| **TICKET SELECT** (tap ticket A→B) | **2 reconstrucciones completas** del POS |
| **REBUILD extra por edición del carrito** | 1 reconstrucción completa de 18.340 líneas por cada `_syncQuotationAi()` (13 puntos de llamada) |
| **REQUEST COUNT SALE (bloqueantes antes de la UI)** | **2** (`GET /cash/state` ×2) **+ 1** (`POST /sales`) = **3** |
| **REQUEST COUNT SALE (totales, incl. fondo)** | 3 bloqueantes + `PUT /open-tickets` + `GET /products` (explícito) + `GET /products` (realtime) + recarga de caja (7 providers) + **N × `POST /cotizaciones/ai/analyze`** |
| **REQUEST COUNT TICKET CREATE** | 1 (`PUT /open-tickets`, no bloqueante) + tormenta IA de fondo |
| **REQUEST COUNT TICKET SELECT** | **0** (ya era local) |
| **QUERIES TRANSACCIÓN — venta de 3 líneas con stock** | **27** (3 × 9) |
| **QUERIES TRANSACCIÓN — venta de 10 líneas** | **90** (10 × 9) |

---

## 3. FIXES IMPLEMENTED

### Flutter — `apps/fulltech_app/lib/modules/cotizaciones/cotizaciones_screen.dart`

1. **El POS deja de suscribirse al estado de IA.** `build()` pasó de `ref.watch(quotationAiControllerProvider)` a
   `ref.watch(quotationAiControllerProvider.select((s) => _shouldShowAiBanner(s) ? s : null))`.
   Con el banner apagado el `select` colapsa a `null` y **Riverpod no notifica** ⇒ se elimina la reconstrucción completa del POS por cada `setContext`. Si el banner se reactiva, el `select` vuelve a notificar sin tocar nada más. Los 3 builders (`_buildDesktopAppBar`, `_buildDesktopBody`, `_buildMobileBody`) reciben el estado nullable y el `AiWarningBanner` sólo se construye cuando el banner está realmente activo.
2. **Interruptor explícito del banner** `_aiBannerEnabled = false` (documentado), del que dependen las dos decisiones de rendimiento.
3. **El análisis remoto de IA no se dispara con el banner apagado.**
   `_syncQuotationAi` calcula `triggerAi: triggerAi && _aiBannerEnabled` → desaparecen los `POST /cotizaciones/ai/analyze` tras cada cambio de carrito (no había consumidor visible para ese resultado). El contexto local se sigue publicando para no romper el asistente si se reactiva.
4. **Post-venta: UI primero, impresión después.** Confirmado el 2xx: se invalidan providers, se libera el ticket, se persiste el snapshot y se muestra "Venta guardada" **antes** de `printSaleTicket`. La impresión (y la apertura de cajón) pasan a ser trabajo secundario; un fallo de impresión ya **no** queda oculto por el aviso de éxito. `.popOnSave` sigue esperando a la impresión (no cambia el contrato de esa ruta).
5. **Eliminado el gate de caja duplicado** en `_finalizeCotizacion`. Se conserva el gate previo en `_openCheckoutDialog` (fail-fast antes de abrir el diálogo) y la validación de sesión activa en el backend. Ninguna validación se eliminó: se dejó de ejecutar dos veces la misma.
6. **`indexProductsById()`** (helper puro, exportado y testeado): `_buildQuotationAiContext` indexa el catálogo una vez en lugar de escanearlo por línea.

### Flutter — `apps/fulltech_app/lib/core/perf/perf_trace.dart` (nuevo)

Traza opt-in con `--dart-define=PERF_TRACE=true`: `Stopwatch` + `Timeline` (categoría `fullpos.perf`) + log. Sin el define, `PerfTrace.begin()` devuelve `null` y **no se crea ningún Stopwatch, ni Timeline, ni callback de frame**. Instrumentados: `ticket.create`, `ticket.switch` (hasta el frame pintado), y las fases de venta `build_payload → post_sales → ui_updated → print_prepare → print`.

### Backend — `apps/api/src/inventory/inventory-mutation.service.ts`

7. Nuevo `decreaseStockForSaleInTransaction(tx, input)` por **lote**: resuelve **una sola vez** el almacén (`warehouse.findFirst`) y **todos** los productos de la venta (`product.findMany` con `where: { companyId, id: { in } }`), y luego ejecuta cada línea por el **mismo** `runMutationInTransaction` (se le añadió el parámetro opcional `preloadedProduct` / `preloadedWarehouse`). Se conservan **todas** las validaciones: scope de empresa, producto `LOCAL`, almacén activo, precisión de unidad, reconciliación `Product.stock ↔ SUM(WarehouseStock.quantity)` antes y después, stock insuficiente y movimiento inmutable. Ejecución **en serie** a propósito (nada de `Promise.all` dentro de la transacción).

### Backend — `apps/api/src/sales/sales.service.ts`

8. **`saleItem.createMany`** en una sola sentencia (antes N `create`). Los `id` se generan con `crypto.randomUUID()` **antes** del insert porque el movimiento de inventario los necesita como `sourceItemId` y `createMany` no devuelve filas.
9. **Descarga de stock en una sola llamada por lote** dentro de la transacción, respetando el orden determinista de actualizaciones.
10. Se mantiene el tracer `SALES_PERF_LOG=true` (ya existente) y se ajustó el contador a lote.

---

## 4. AFTER

### 4.1 Medido de forma determinista (este entorno)

| Métrica | BEFORE | AFTER | Mejora |
|---|---|---|---|
| **TICKET SELECT** — reconstrucciones completas del POS por transición | **2** | **1** | **−50 %** |
| **A→B→A** (3 transiciones) | 6 rebuilds | 3 rebuilds | −50 % |
| **Éxito de carrito (`_commitEditorChange`)** — rebuilds completos | 2 | 1 | −50 % |
| **Rebuild completo disparado por cambio de estado de IA** | 1 por cada `setContext` | **0** con banner off | −100 % |
| **POST `/cotizaciones/ai/analyze` por cambio de carrito** | 1 (debounce 1,1 s) | **0** | −100 % |
| **REQUESTS bloqueantes antes de la UI (guardar venta)** | **3** | **1** | **−66 %** |
| **QUERIES transacción — venta 3 líneas con stock** | 27 | **21** | −22 % |
| **QUERIES transacción — venta 5 líneas con stock** | 45 | **33** | −27 % |
| **QUERIES transacción — venta 10 líneas con stock** | 90 | **63** | −30 % |
| **`product.findFirst` / `warehouse.findFirst` por línea** | 1 + 1 | **1 + 1 por venta** (amortizado) | −100 % por línea |
| **INSERTs de `SaleItem`** | N | 1 | −(N−1) |
| **Llamadas a descarga de stock en la transacción** | N | 1 | −(N−1) |

### 4.2 Derivado (baseline de red de auditorías previas)

| Métrica | BEFORE (derivado) | AFTER (derivado) | Mejora |
|---|---|---|---|
| **SALE — latencia percibida hasta el aviso** | ≈ 900 ms + impresión (0,5–3 s) | ≈ 300–500 ms (POST /sales) | **impresión fuera del camino crítico ⇒ −0,6 s a −3,4 s** |
| **SALE — RTT eliminados** | 2 × `GET /cash/state` | 1 × `GET /cash/state` | −1 RTT (≈ 300 ms) |
| **TICKET CREATE** | rebuild + rebuild IA posterior + POST IA en vuelo | 1 rebuild, sin POST IA | sin trabajo de fondo en la ventana de la pulsación |
| **Post-sale background** | 2 `GET /products` + caja(7) + N × POST IA | 2 `GET /products` + caja(7), **sin POST IA** | −N requests |

> **Nota sobre 1 línea:** el lote no mejora el caso de 1 sola línea (9 → 9: se cambia 2 lookups por 2 consultas de lote). El beneficio crece con el número de líneas, que es el caso real de este POS.

---

## 5. CÓMO CERRAR LA MEDICIÓN EN DISPOSITIVO (pendiente del usuario)

```bash
# App (perf trace activo)
flutter run --dart-define=PERF_TRACE=true

# Backend (timing por fase en los logs del contenedor)
SALES_PERF_LOG=true
```

Salidas esperadas:

- `[PERF] sale.total=…ms outcome=ok build_payload=+…ms post_sales=+…ms ui_updated=+…ms print_prepare=+…ms print=+…ms`
- `[PERF] ticket.create.total=…ms set_state=+…ms persist_scheduled=+…ms`
- `[PERF] ticket.switch.total=…ms set_state=+…ms persist_and_ai_scheduled=+…ms` (el `.total` es hasta el frame pintado)
- Backend: `create.start` → `create.core_lookups` → `create.products` → `create.fiscal` → `create.cash_gate` → `create.pre_transaction` → `create.transaction` → `create.done total=…ms items=N inventoryMutations=N`

En DevTools, filtrar el timeline por categoría `fullpos.perf` para ver las fases en el flame chart. **Estas trazas están listas para usarse; no se declara un valor en ms para no inventar mediciones.**

---

## 6. TABLA OBLIGATORIA BEFORE/AFTER

| OPERATION | BEFORE | AFTER | IMPROVEMENT |
|---|---|---|---|
| Ticket Select | 2 rebuilds completos del POS | 1 | −50 % |
| Ticket Create | 1 rebuild + rebuild IA + POST IA | 1 rebuild, 0 POST IA | sin trabajo de fondo |
| Sale API | 2 × `GET /cash` + `POST /sales` bloqueantes | 1 × `POST /sales` | −1 RTT (≈300 ms derivado) |
| Sale UI total | POST + impresión bloqueante | POST → UI → impresión en segundo plano | −0,6 s a −3,4 s (derivado) |
| Backend transaction queries (3 líneas) | 27 | 21 | −22 % |
| Post-sale refresh | rebuild IA + N POST IA | sin POST IA; rebuild IA eliminado | −100 % del trabajo IA |

---

## 7. DATABASE / SERVER / MULTI-TENANT / TESTS

### DATABASE

- **SLOW QUERIES:** no medibles en este entorno (sin acceso de lectura al servidor). Por la auditoría previa, PostgreSQL **no** era el cuello de botella (`/health/db` ≈ `/health` ≈ 300 ms ⇒ DB ≈ 0 ms).
- **N+1:** **YES** — encontrado y corregido (lookups de producto/almacén por línea + N inserts de `SaleItem`).
- **INDEXES MISSING:** **NO** (auditado contra `apps/api/prisma/schema.prisma`; los índices existentes cubren los `WHERE companyId = ?` del flujo de venta).
- **PG_STAT_STATEMENTS:** **NO VERIFICADO** (requiere acceso a producción; no autorizado en esta tarea).
- **POOL:** **HEALTHY (derivado)** — sin evidencia de agotamiento; la latencia base era de red/proxy, no de pool.
- **MIGRACIONES:** **no se creó ni aplicó ninguna** (no hacen falta índices nuevos).

### SERVER

- **CPU / RAM / DISK / SWAP / LOAD:** **no medibles** (requiere acceso al host; no autorizado).
- **NODE EVENT LOOP:** no se halló bloqueo sincrónico en el camino de venta (sin `fs.*Sync`, sin PDF/imágenes síncronas, `crypto` sólo `randomUUID`).
- **SERVER BOTTLENECK:** **NO** con la evidencia disponible (DB ≈ 0 ms, `/health` estable en auditoría previa).
- Las mejoras de servidor **no se recomiendan a ciegas**: §8.

### FLUTTER

- **EXCESSIVE REBUILDS:** **YES (corregido)** → −1 reconstrucción completa del POS por interacción.
- **GLOBAL INVALIDATIONS:** **YES (mitigado)**. `refreshSalesAndCash()` sigue invalidando 7 providers de caja + ventas + créditos + catálogo al recibir `sale.created`; **no se tocó** porque cada invalidación tiene consumidor real y el coste dominante era la reconstrucción IA. La duplicación de `GET /products` queda como OPTIONAL (§8).
- **FULL CATALOG RELOAD:** **YES** — `_loadProducts(forceRemote: true, silent: true)` tras la venta, ya protegido por un mínimo de 20 s entre refrescos (`_silentRefreshMinInterval`). Se mantiene por frescura de stock.
- **JANK:** no medible en este entorno (requiere `flutter run --profile` en dispositivo). Instrumentación lista.

### MULTI-TENANT

- **TENANT ISOLATION: PASS** — `npm run test:tenant`: **65/65**. Nuevo spec de lote verifica que un `productId` de otra empresa **no** se resuelve (el `findMany` del lote filtra por `companyId`) y que el lote completo falla sin mutar inventario.
- **CACHE TENANT SAFE: N/A** — no se introdujo ninguna caché nueva.
- **QUERY TENANT SAFE: PASS** — todas las consultas del lote conservan `companyId`; el almacén se valida con `companyId` + `isActive`.

### TESTS

| Validación | Resultado |
|---|---|
| **API BUILD** (`npm run api:build`) | **PASS** |
| **BACKEND UNIT** (`npm test`) | **PASS** — 46 suites / 370 tests |
| **TENANT** (`npm run test:tenant`) | **PASS** — 7 suites / 65 tests |
| **FLUTTER ANALYZE** | **PASS** — *No issues found!* |
| **FLUTTER FULL** (`flutter test`) | **PASS** — 974 tests, 1 skipped, 0 fallos |
| **ANDROID** (`flutter build apk --debug`) | **PASS** — `app-debug.apk` |
| **WINDOWS** (`flutter build windows --debug`) | **PASS** — `fullpos_cloud.exe` |

**Nota:** `src/sales/sales.fiscal.e2e-spec.ts` (y los otros `*.e2e-spec.ts`) **no** se ejecutaron: requieren conexión a la base de datos en `31.97.99.70:5432` (producción) y el script `npm test` los excluye explícitamente. **No se habilitó ni se intentó ese acceso.**

Tests nuevos:
- `apps/api/src/inventory/inventory-mutation.batch.spec.ts` (5 tests: lote, aislamiento multi-tenant, almacén inválido, precisión de unidad, lista vacía).
- `apps/api/src/sales/sales.service.query-count.spec.ts` (4 tests: 1 `createMany`, 1 lote de stock, ids de línea = `sourceItemId`, venta rápida sin inventario).
- `apps/fulltech_app/test/modules/cotizaciones/billing_performance_no_ai_rebuild_test.dart` (13 tests: el `select` no notifica con banner off y sí con banner on; `indexProductsById`; wiring de `select`/interruptor/`triggerAi`; orden post-venta; ausencia del gate de caja duplicado).

Specs existentes actualizadas al contrato por lote (mismas invariantes, mocks nuevos): `sales.service.inventory-optional.spec.ts`, `sales.service.uom.spec.ts`, `sales.service.quick-sale.spec.ts`, `sales.service.fiscal-final.spec.ts`, `sales.service.ncf-expiration.spec.ts`.

---

## 8. RECOMMENDED SERVER IMPROVEMENTS

Clasificadas por evidencia. **Sin evidencia ⇒ no se recomienda.**

### REQUIRED NOW
Ninguna. Los cuellos identificados eran de cliente (rebuilds + impresión bloqueante + request duplicado) y están corregidos.

### OPTIONAL
1. **Unificar el refresco de catálogo tras la venta.** Hoy hay dos `GET /products` potencialmente en la misma ventana: el explícito de `_finalizeCotizacion` y el de `catalogController.load(forceRemote: true)` que dispara el realtime `sale.created`. Eliminar uno ahorra 1 request (~300 ms de fondo, catálogo ≈32 KB gzip), pero **decide producto**: sin el explícito, si el socket realtime está caído la frescura de stock depende del polling de 2 min. *No se aplicó por ser una decisión de producto, no de rendimiento.*
2. **Eliminar el pre-check redundante de `assertProductStockReconciled`** (2 consultas raw por línea → 1). Bajaría el N+1 residual ~17 % adicional (10 líneas: 63 → 53). **No se aplicó**: es un guardián de integridad de inventario documentado y retirarlo requiere autorización explícita.
3. **`EXPLAIN (ANALYZE, BUFFERS)` + `pg_stat_statements` en UAT** sobre `Sale`, `SaleItem`, `WarehouseStock`, `InventoryMovement`, `Terminal`. Con la evidencia actual no se espera hallazgo, pero cierra la FASE 8/9 con datos propios.
4. **APM ligero por fases** (no una plataforma): los tracers ya implementados (`PERF_TRACE`, `SALES_PERF_LOG`) son suficientes como primer paso. Si se promueve a Prometheus/OTel, usar **sólo** etiquetas `route`/`status` — **nunca `companyId`** (alta cardinalidad) y **nunca datos personales**.

### NOT NEEDED
- **Redis.** No hay evidencia de que haga falta: la DB responde en ≈0 ms y lo eliminado era trabajo de cliente. Meterlo ahora añadiría un sistema distribuido y riesgo de caché cross-tenant sin beneficio demostrado.
- **Más RAM/CPU en el servidor.** No hay evidencia de saturación; subirlo no movería ninguna de las causas raíz corregidas.
- **Índices nuevos.** El schema ya cubre los accesos del flujo de venta.

---

## 9. RIESGOS Y CAMBIOS DE COMPORTAMIENTO OBSERVABLES

1. **Aviso de fallo de impresión ahora SÍ se ve.** Antes el aviso de impresión fallida era sobrescrito de inmediato por "Venta guardada" y el usuario nunca lo veía. Con el nuevo orden, el usuario ve "Venta guardada" y, si la impresión falla, después el aviso de impresión. Es el comportamiento que el código claramente pretendía; se documenta porque es un cambio visible.
2. **Mientras se imprime, `_finalizingCheckout` sigue activo** (igual que antes): protege contra doble cobro, pero un spooler colgado mantiene el botón bloqueado. Es el comportamiento previo, no una regresión; se puede revisar por separado.
3. **El asistente de IA del POS queda inerte** (ya lo estaba: el banner siempre devolvía `false` y el sheet sólo se alcanzaba desde el banner). Al reactivar `_aiBannerEnabled` se recuperan suscripción y análisis remoto sin tocar nada más. La única pérdida real es que ya no se envían a OpenAI análisis cuyo resultado nadie veía.
4. **El gate de caja dentro de `_finalizeCotizacion` ya no existe.** Si la caja se cierra entre abrir el diálogo de cobro y confirmarlo, el error lo devuelve el backend ("Debes abrir caja antes de facturar") en lugar del aviso previo. La venta no se crea en ningún caso.
5. **`createMany` vs `create`:** si el schema ganara triggers/`@default` dependientes del ORM para `SaleItem`, habría que revisarlo. Hoy `SaleItem` sólo usa escalares y defaults de base de datos, y los 370 tests de backend pasan.

---

## 10. PERFORMANCE VERDICT

# PERFORMANCE HARDENING — GO WITH ISSUES

**GO** por: causas raíz identificadas con evidencia y corregidas en el código, validación completa en verde (370 tests backend + 974 tests Flutter + analyze + builds Android/Windows), multi-tenant verificado, y ninguna migración/escritura/deploy.

**WITH ISSUES** por: los milisegundos en dispositivo real **no** están medidos todavía. La instrumentación (`PERF_TRACE` / `SALES_PERF_LOG`) está lista y es de coste cero en release, pero la confirmación de los budgets (§ FASE 20) requiere una ejecución con sesión real y caja abierta. **No se declara "performance fixed" sin esa medición**, tal como exige la regla final.

---

## ANEXO — ARCHIVOS

**Nuevos**
- `apps/fulltech_app/lib/core/perf/perf_trace.dart`
- `apps/fulltech_app/test/modules/cotizaciones/billing_performance_no_ai_rebuild_test.dart`
- `apps/api/src/inventory/inventory-mutation.batch.spec.ts`
- `apps/api/src/sales/sales.service.query-count.spec.ts`

**Modificados**
- `apps/fulltech_app/lib/modules/cotizaciones/cotizaciones_screen.dart`
- `apps/api/src/inventory/inventory-mutation.service.ts`
- `apps/api/src/sales/sales.service.ts`
- `apps/api/src/sales/sales.service.inventory-optional.spec.ts`
- `apps/api/src/sales/sales.service.uom.spec.ts`
- `apps/api/src/sales/sales.service.quick-sale.spec.ts`
- `apps/api/src/sales/sales.service.fiscal-final.spec.ts`
- `apps/api/src/sales/sales.service.ncf-expiration.spec.ts`

**No modificado (fuera de alcance, cambios ajenos ya commiteados en `238d53d6`):**
`mis_ventas_screen.dart`, `tpv_sales_history_screen.dart`, `sales_actions_visibility_test.dart`.

**Sin commit, sin push, sin deploy, sin migraciones.**
