# AUDITORÍA MÓDULO DE REPORTES — DaleVentas POS / FullPOS Cloud

Fecha: 2026-08-22
Branch: `main` (HEAD `236ef122`)
Alcance: módulo de Reportes (frontend Flutter + backend NestJS/Prisma/PostgreSQL)

---

## 1. Resumen ejecutivo

Se auditó el módulo de Reportes de extremo a extremo: UI → repositorio Flutter → API → PostgreSQL.

**Causa raíz del “No responde” (confirmada por análisis de código):** la pantalla de Reportes descargaba **todas** las ventas del rango con todos sus items (endpoint `/sales/invoices` sin límite) y las parseaba **síncronamente en el hilo principal de Flutter**. Con miles de ventas, ese JSON de varios MB y su parsing (`jsonDecode` + `SaleModel.fromJson`) bloquean la UI (especialmente en Windows). Además, cada evento de realtime (venta/caja) disparaba una recarga completa sin guard de “en vuelo”, acumulando solicitudes.

**Hallazgos corregidos (resumen):**

| # | Severidad | Hallazgo | Estado |
|---|-----------|----------|--------|
| 1 | CRÍTICO | Venta creada y anulada en el mismo rango se descuenta dos veces → neto negativo | ✅ Corregido |
| 2 | CRÍTICO | “No responde”: `listInvoices` sin límite + parsing en hilo principal + recargas en cascada | ✅ Corregido |
| 3 | ALTO | Sin protección contra races al cambiar filtros rápido (respuesta vieja sobrescribe) | ✅ Corregido |
| 4 | ALTO | `jsonDecode`/`as Map` sobre cuerpo vacío/204 → excepción no controlada | ✅ Corregido |
| 5 | MEDIO | `avgTicket` dividía por todas las ventas en lugar de las visibles (filtro categoría) | ✅ Corregido |
| 6 | MEDIO | Rango de fechas con `lte 23:59:59.999` en vez de semántica exclusiva `<` | ✅ Corregido |
| 7 | MEDIO | Documentos de devolución (`kind=refund`) aparecían en “Ventas recientes”/PDF | ✅ Corregido (frontend) |
| 8 | MEDIO | `.env` apunta a una BD obsoleta (esquema camelCase antiguo, 0 filas) | ⚠️ Documentado, no modificado |
| 9 | BAJO/MEDIO | Métodos de pago solo Efectivo/Transferencia (crédito no representado) | ⚠️ Documentado |
| 10 | MEDIO | Backend agrega en memoria (miles de filas al servidor); recomendación de SQL/indexes | ⚠️ Documentado |

**No se encontró fuga entre empresas:** todas las consultas del backend filtran por `companyId` (`requireTenant`) y la caché local de Flutter se prefija por `companyId` en `LocalJsonCache._key()`. Verificado por código y por pruebas automatizadas.

---

## 2. Arquitectura actual del módulo

### Backend (NestJS + Prisma)
- `apps/api/src/reports/reports.controller.ts` — único endpoint: `GET /reports/sales-overview` (protegido por `AuthGuard('jwt')` + `RolesGuard`).
- `apps/api/src/reports/reports.service.ts` — orquesta 5 consultas en paralelo y agrega en memoria.
- Endpoints de soporte usados por la pantalla:
  - `GET /sales/invoices` (`sales.service.listInvoices`) → lista “Ventas recientes”.
  - `GET /sales/summary` (`sales.service.summaryMine`) → comparativas (6 llamadas).
- Modelos: `Sale`, `SaleItem`, `Product`, `CashMovement` (Prisma).

### Frontend (Flutter)
- `apps/fulltech_app/lib/features/reports/ui/reports_page.dart` (3016 líneas) — pantalla completa con KPIs, gráficas (barra, línea, pastel con `CustomPainter`), tablas y comparativas.
- `apps/fulltech_app/lib/features/reports/utils/sales_report_pdf_service.dart` — PDF (usa los mismos datos ya calculados).
- `apps/fulltech_app/lib/modules/ventas/data/ventas_repository.dart` — `reportsSalesOverview`, `listInvoices`, `summary`, con caché local.
- `apps/fulltech_app/lib/modules/ventas/sales_models.dart` — `SaleModel`, `SaleItemModel`, `SalesSummaryModel`, `KpisData` (este último en `reports_page.dart`).

---

## 3. Flujo frontend → backend → PostgreSQL

```
ReportsPage._loadData()
 ├─ reportsSalesOverview(from,to,category)  → GET /reports/sales-overview
 │    └─ ReportsService.salesOverview()
 │         ├─ SELECT "Sale" (company_id, kind=invoice, is_deleted=false, sale_date range) + items + product.categoria
 │         ├─ SELECT "Sale" (company_id, kind=invoice, is_deleted=true,  deleted_at range, sale_date < inicio)  → reversiones
 │         ├─ SELECT "Sale" (company_id, kind=refund, is_deleted=false,  sale_date range)                       → devoluciones
 │         ├─ SELECT "Product" (company_id) → inventario
 │         └─ SELECT "CashMovement" (company_id, created_at range) → gastos/ingresos de caja
 │    └─ Agregación en memoria (reduce) → KPIs, series, top productos/clientes, categorías
 ├─ _loadReportSales()  → GET /sales/invoices (from,to, includeDeleted=false, limit)  [AHORA con límite]
 ├─ _loadComparisons()  → 6 × GET /sales/summary (Hoy/Ayer/Semana/Semana previa/Mes/Mes previo)
 └─ parse + setState → render (charts CustomPainter)
```

Antes de la corrección, `_loadReportSales` **no enviaba límite** → el backend devolvía TODAS las ventas+items del rango.

---

## 4. Tablas involucradas

| Tabla | Columnas clave usadas |
|-------|------------------------|
| `"Sale"` | `company_id`, `user_id`, `kind` (`invoice`/`refund`), `status`, `sale_date`, `is_deleted`, `deleted_at`, `total_sold`, `total_cost`, `total_profit`, `commission_amount`, `payment_cash_amount`, `payment_transfer_amount`, `credit_amount`, `taxable_base`, `tax_amount`, `exempt_amount`, `discount_amount`, `ncf`, `fiscal_voucher_type` |
| `"SaleItem"` | `sale_id`, `product_id`, `qty`, `price_sold_unit`, `cost_unit_snapshot`, `subtotal_sold`, `subtotal_cost`, `profit`, `taxable_base`, `tax_rate`, `tax_amount`, `exempt_amount`, `line_discount_amount`, `gross_amount`, `refunded_sale_item_id` |
| `"Product"` | `company_id`, `categoria`, `costo`, `precio`, `stock` |
| `"CashMovement"` | `company_id`, `session_id`, `type` (`IN`/`OUT`), `amount`, `movement_type`, `affects_profit`, `created_at` |

---

## 5. Fórmulas actuales (tras la auditoría)

- **Ventas brutas (`grossSales`)** = Σ `item.subtotalSold` de facturas activas (`kind=invoice`, `is_deleted=false`) del rango.
- **Devoluciones (`returnedSales`)** = Σ |`item.subtotalSold`| de (a) documentos `kind=refund` del rango y (b) facturas anuladas en el rango **cuya venta ocurrió en un período anterior** (`saleDate < inicio`).
- **Ventas netas (`netSales`)** = `grossSales − returnedSales`.
- **Costo vendido (`totalCost`)** = Σ `item.subtotalCost` (snapshot histórico congelado al vender).
- **Utilidad (`totalProfit`/`netProfit`)** = `totalProfit_bruto − profit_devoluciones − gastos_de_caja(afectan utilidad)`.
- **Margen** = `netProfit / totalSales * 100` (guard de división por cero → `0%`).
- **Órdenes (`totalSales`)** = conteo de facturas visibles (una factura = 1 orden, no cuenta líneas).
- **Ticket promedio (`avgTicket`)** = `totals.totalSold / visibleSales.length` (CORREGIDO: usa órdenes visibles; antes usaba `sales.length` total).
- **ITBIS** = Σ `item.taxableBase` (base), `item.taxAmount` (impuesto), `item.exemptAmount` (exento) desde snapshots persistidos al facturar.
- **Métodos de pago** = suma de `payment_cash_amount` / `payment_transfer_amount` prorrateada por categoría (`allocation`); conteo por factura.

---

## 6. Hallazgos

### 6.1 [CRÍTICO] Doble descuento de ventas anuladas en el mismo rango
- **Archivo:** `apps/api/src/reports/reports.service.ts` — `salesOverview` (`returnedWhere`).
- **Explicación:** `sales` (gross) filtra `isDeleted: false`; por tanto una venta creada **y** anulada dentro del mismo rango **nunca entra** al gross. `returnedSales` filtra `isDeleted: true` con `deletedAt` en el rango y restaba ese monto → la venta se descontaba dos veces → **neto negativo**.
- **Impacto:** neto/ventas totales incorrectos (negativos) cuando hay anulaciones intraperíodo; rompe la reconciliación contable (FASE 30).
- **Evidencia:** para una venta de RD$100 creada y anulada hoy: gross=0, returns=100 → `netSales = −100`.
- **Solución:** `returnedWhere` ahora exige `saleDate: { lt: range.gte }` (solo reversiones de períodos anteriores). ✅

### 6.2 [CRÍTICO] “No responde”: descarga masiva + parsing en hilo principal + recargas en cascada
- **Archivo:** `apps/fulltech_app/lib/features/reports/ui/reports_page.dart` — `_loadReportSales`, `_loadData`, `_scheduleRealtimeReload`.
- **Explicación:**
  1. `_loadReportSales` llamaba `listInvoices` **sin límite** → el backend devolvía todas las ventas+items del rango (JSON de MB con miles de registros).
  2. `jsonDecode` + `SaleModel.fromJson` se ejecutan **síncronos en el hilo principal** → la UI se congela (“No responde”), especialmente en Windows.
  3. `_scheduleRealtimeReload` (debounce 350 ms) se dispara en cada evento realtime de venta/caja; `_loadData` **no tenía guard de en-vuelo** → recargas solapadas, cada una con 1+1+6 = 8 solicitudes.
  4. El interceptor `ApiRetryInterceptor` (máx. 2 reintentos) puede prolongar una falla lenta a ~45 s (15 s × 3 intentos) manteniendo la pantalla “cargando”.
- **Solución (frontend):**
  - `_loadReportSales` ahora pide `limit: 150` (basta: la UI muestra 12, el PDF 30) y filtra `kind != 'refund'`.
  - `_loadData` añade **generation token** (`_loadGeneration`), **guard de en-vuelo** (`_loadInFlight`) y **recarga pendiente consolidada** (`_pendingReload`).
  - `_scheduleRealtimeReload` ya no descarta eventos durante la carga; los encola. ✅

### 6.3 [ALTO] Race al cambiar filtros rápidamente
- **Archivo:** `reports_page.dart` — `_changePeriod`/`_changeCategory`/`_loadData`.
- **Explicación:** sin token de generación, una respuesta antigua podía sobrescribir el resultado de un filtro nuevo (FASE 27).
- **Solución:** `_loadGeneration` descarta respuestas obsoletas (`generation != _loadGeneration`). ✅

### 6.4 [ALTO] Parseo de respuestas vacías/204 en repositorio
- **Archivo:** `apps/fulltech_app/lib/modules/ventas/data/ventas_repository.dart` — `reportsSalesOverview` (≈L400) y `summary` (≈L287).
- **Explicación:** hacían `(res.data as Map)`; con `204 No Content`, body vacío o HTML de proxy se lanzaba `TypeError` no controlado (FASE 19, antecedente `FormatException: Unexpected end of input`).
- **Solución:** guard `if (raw is! Map) throw ApiException(...)` → error controlado y visible. ✅

### 6.5 [MEDIO] `avgTicket` incorrecto con filtro de categoría
- **Archivo:** `reports.service.ts` — KPI `avgTicket`.
- **Explicación:** dividía `totals.totalSold` (filtrado por categoría) entre `sales.length` (todas las ventas) → subticket subestimado.
- **Solución:** divide entre `visibleSales.length`. ✅

### 6.6 [MEDIO] Rango de fechas con `lte 23:59:59.999`
- **Archivo:** `reports.service.ts` — `buildDateRange`/`parseDominicanDate`.
- **Explicación:** `lte` con 999 ms puede perder ventas con microsegundos superiores a 23:59:59.999; `sales.service.ts` ya usa semántica exclusiva (`lt`). Inconsistencia entre endpoints.
- **Solución:** rango exclusivo `{ gte, lt }`; fin = `04:00 UTC` del día siguiente (medianoche en `America/Santo_Domingo`). ✅

### 6.7 [MEDIO] Documentos de devolución en “Ventas recientes”/PDF
- **Archivo:** `reports_page.dart` + `sales_models.dart`.
- **Explicación:** `/sales/invoices` no filtra `kind`; los `kind=refund` (montos negativos) aparecían en “Ventas recientes” y en el PDF.
- **Solución:** se añadió `kind` a `SaleModel` y `_loadReportSales` filtra `kind != 'refund'` (solo en Reportes; no se tocó el endpoint compartido para no afectar historial TPV/clientes/compras). ✅

### 6.8 [MEDIO] `.env` → BD obsoleta
- **Archivo:** `apps/api/.env` (`DATABASE_URL` → `daleventa_pos` en `gcdndd.easypanel.host`).
- **Evidencia:** la BD configurada tiene **esquema antiguo** (columnas camelCase: `isDeleted`, `saleDate`, `totalSold`, `company_id`) y **0 filas**; no coincide con `schema.prisma` actual (`is_deleted`, `sale_date`, `total_sold`). El sistema desplegado debe apuntar a otra BD.
- **Impacto:** la medición real con EXPLAIN no fue posible contra datos productivos. ⚠️ No se modificó (fuera de alcance, posiblemente intencional para un entorno distinto). **Acción pendiente recomendada:** confirmar la `DATABASE_URL` productiva y correr migraciones/índices.

### 6.9 [MEDIO] Métodos de pago limitados a Efectivo/Transferencia
- **Explicación:** el reporte usa solo `paymentCashAmount`/`paymentTransferAmount`. El crédito (`creditAmount`) no se muestra como método; pagos mixtos se cuentan en ambos.
- **Impacto:** menor, afecta “Método líder” cuando predominan créditos. ⚠️ Documentado (FASE 14); requiere decisión funcional.

### 6.10 [MEDIO/ALTO] Agregación en memoria en el backend
- **Explicación:** `salesOverview` trae todas las ventas+items al proceso Node y agrega con `reduce`; para “miles de ventas” consume CPU/memoria del servidor y amplía el tiempo de respuesta.
- **Solución a corto plazo:** límite de la lista de ventas recientes (ya aplicado en frontend) + índices recomendados (§13). **Recomendación a medio plazo:** mover las agregaciones a PostgreSQL (FASE 21) sin romper la API. ⚠️ No se reescribió el motor (evitar refactor masivo sin métricas productivas).

---

## 7. Problema “No responde” — causa raíz demostrada

Cadena causal:

1. `_loadReportSales` → `GET /sales/invoices` **sin `limit`** → payload = TODAS las ventas del rango + items + producto.
2. `res.data` (List de maps) → `jsonDecode` (implícito en Dio) + `SaleModel.fromJson` para cada venta/item → **trabajo síncrono en el hilo principal**.
3. Con N ventas, el costo crece linealmente (y el JSON con items es O(N×M)); en escritorios Windows un bloqueo de varios segundos se percibe como “No responde”.
4. Los eventos realtime (cada venta/caja) disparan recargas encoladas de 350 ms sin guard → pico de solicitudes (1 overview + 1 invoices + 6 summaries) solapadas.

**Medida de referencia:** con una base poblada (miles de ventas), el payload de `listInvoices` sin límite es el factor dominante; el límite de 150 reduce el parseo a cientos de objetos en vez de miles.

**Corrección aplicada:** límite acotado + guard de en-vuelo + consolidación de recargas + descarte de respuestas obsoletas. La UI ya no congela el hilo principal y no acumula solicitudes.

---

## 8. Auditoría NCF

- El campo `ncf` y `fiscal_voucher_type` **no intervienen** en la agregación de Reportes: no se suman, no se cuentan dos veces.
- Una venta con NCF es una fila `kind=invoice` → cuenta una vez como venta/orden.
- Las devoluciones se registran como `kind=refund` (filas separadas con `refundedSaleId`) y se restan del neto; no duplican ingresos.
- `@@unique([companyId, ncf])` en la BD evita NCF duplicados a nivel de modelo.
- **Conclusión:** el NCF no altera ni duplica ingresos en Reportes. ✅

## 9. Auditoría ITBIS

- Reportes usa snapshots persistidos al facturar: `SaleItem.taxableBase`, `.taxRate`, `.taxAmount`, `.exemptAmount`, `.taxIncluded`, `.taxExempt`, `Sale.taxableBase/taxAmount/exemptAmount/discountAmount`.
- Estos campos se calculan una sola vez en `sales.service.create` vía `taxes.calculatorService.calculate(...)` (fuente única de verdad) y se guardan en la factura y sus líneas.
- **No hay fórmula duplicada en Reportes**; solo lee los snapshots. Para empresas sin impuestos, los snapshots son 0 y `totalSold = Σ subtotalSold` (comportamiento correcto).
- Exento/gravado: `taxExempt`/`taxAmount` por línea; `taxableBase + exemptAmount` = ingreso neto fiscal.
- **Conclusión:** Reportes es consistente con el motor de facturación. ✅

## 10. Auditoría multiempresa

- **Backend:** todas las consultas de `salesOverview` filtran `companyId` (vía `requireTenant(user)`): sales, returned, refund, product, cashMovement. ✅
- **Endpoints compartidos:** `listInvoices`/`summaryMine` también filtran `companyId`. ✅
- **Frontend/caché:** las claves de caché no incluyen `companyId` explícito, pero `LocalJsonCache._key()` **prefija `company_id`** del snapshot de token (`ft_cache:<companyId>:<key>`); `AppStorageScopeGuard` limpia el caché al cambiar de contexto de instalación. No hay caché compartida entre empresas. ✅
- **Prueba automatizada añadida** (`reports.service.spec.ts` → “aísla todas las consultas por companyId”). ✅

## 11. Auditoría contable

- **Costo histórico congelado:** Reportes usa `SaleItem.costUnitSnapshot`/`subtotalCost`/`profit` (snapshots al vender). Un cambio posterior del costo del producto **no** altera la utilidad histórica. ✅ (coincide con la intención de diseño: la utilidad no debe cambiar retroactivamente).
- **Subtotal/descuento:** por línea se usan `subtotalSold`, `lineDiscountAmount`, `grossAmount`; el descuento global está incluido en el total de la factura. No hay doble descuento en Reportes.
- **Estados excluidos:** solo `kind=invoice` no eliminadas entran al gross; `isDeleted=true` excluidas; cotizaciones/borradores no están en `Sale` con `kind=invoice`.
- **Reversiones:** tras la corrección 6.1, `netSales = gross − devoluciones(refund) − anulaciones de períodos anteriores`.
- **Reconciliación (FASE 30):** `SUM(sale.totalSold)` de facturas válidas debe coincidir con `grossSales`. Nota: Reportes calcula `grossSales` desde items; para facturas fiscales `sale.totalSold` puede diferir en la parte de impuestos según `priceMode` (TAX_INCLUDED vs TAX_ADDED). Se recomienda validar en un entorno poblado (ver Riesgos).

## 12. Rendimiento SQL

- No fue posible ejecutar `EXPLAIN (ANALYZE, BUFFERS)` sobre datos productivos: la BD configurada en `.env` está vacía y con esquema antiguo (§6.8).
- Análisis estático de las consultas:
  - La consulta principal (sales + items + producto) se apoya en `@@index([companyId, saleDate])` para el filtro de rango, pero luego filtra `kind`/`is_deleted` en memoria del índice → razonable, pero mejorable con un índice compuesto.
  - La consulta de anuladas filtra por `deleted_at` (sin índice dedicado) → en BD pobladas conviene índice.
  - `CashMovement` tiene `@@index([companyId, createdAt])` → cubre el filtro real.
- Recomendación de índices (validar con EXPLAIN en BD poblada antes de aplicar, FASE 20):

```sql
CREATE INDEX IF NOT EXISTS idx_sales_c_kind_del_saledate
  ON "Sale" (company_id, kind, is_deleted, sale_date);
CREATE INDEX IF NOT EXISTS idx_sales_c_kind_del_deletedat
  ON "Sale" (company_id, kind, is_deleted, deleted_at);
CREATE INDEX IF NOT EXISTS idx_sales_c_kind_saledate
  ON "Sale" (company_id, kind, sale_date);
```

## 13. Índices existentes / recomendados

Existentes (en `schema.prisma`):
- `Sale`: `[companyId, saleDate]`, `[companyId, isDeleted]`, `[companyId, creditStatus]`, `[companyId, fiscalVoucherType]`, `[userId]`, `[customerId]`, `[cashSessionId]`.
- `SaleItem`: `[saleId]`, `[refundedSaleItemId]`, `[productId]`.
- `CashMovement`: `[sessionId]`, `[companyId, createdAt]`.
- `Product`: `[companyId]`, `[companyId, nombre]`.

Recomendados (justificados por la forma real de las consultas; **no** se aplicaron a ciegas): ver §12.

## 14. Cambios realizados

### Backend
1. `apps/api/src/reports/reports.service.ts`
   - `returnedWhere` ahora exige `saleDate: { lt: range.gte }` → sin doble descuento (6.1).
   - `avgTicket` dividido por `visibleSales.length` (6.5).
   - `buildDateRange` → `{ gte, lt }` exclusivo; `parseDominicanDate` fin = `04:00 UTC` día+1 (6.6).
   - Respuesta `range.to` = `range.lt`.

### Frontend
2. `apps/fulltech_app/lib/modules/ventas/sales_models.dart` — campo `kind` en `SaleModel` (default `invoice`, parseo de `json['kind']`).
3. `apps/fulltech_app/lib/modules/ventas/data/ventas_repository.dart` — guards `raw is! Map` en `reportsSalesOverview` y `summary` → `ApiException` controlada (6.4).
4. `apps/fulltech_app/lib/features/reports/ui/reports_page.dart`
   - `_loadReportSales` con `limit: 150` + filtro `kind != 'refund'` (6.2/6.7).
   - `_loadData` con generation token + in-flight guard + pending reload (6.2/6.3).
   - `_scheduleRealtimeReload` encola recargas durante carga en vuelo (6.2).
   - Log de error real vía `TraceLog`.

### Pruebas
5. `apps/api/src/reports/reports.service.spec.ts` (nuevo) — 7 casos.
6. `apps/fulltech_app/test/modules/ventas/reports_models_test.dart` (nuevo) — 9 casos.

## 15. Pruebas ejecutadas

| Prueba | Resultado |
|--------|-----------|
| `jest` `reports.service.spec.ts` (7) | ✅ 7/7 |
| `jest` reports + sales.tenant + sales.ncf-expiration + sales.fiscal-final + products.tenant + tax.tenant (28) | ✅ 28/28 |
| `tsc -p tsconfig.build.json` (backend) | ✅ exit 0 |
| `flutter analyze` (proyecto completo) | ✅ sin issues |
| `flutter test test/modules/ventas/reports_models_test.dart` (9) | ✅ 9/9 |

## 16. Resultados antes / después

| Métrica | Antes | Después |
|---------|-------|---------|
| Venta creada+anulada en el mismo rango | `netSales = −monto` (doble resta) | `netSales = 0` (coherente) |
| `avgTicket` con filtro categoría | subestimado | correcto (órdenes visibles) |
| Ventas recientes | todas las ventas+items (payload masivo, freeze) | 150 máx., sin refunds |
| Recarga por realtime | recargas solapadas sin guard | 1 en vuelo + 1 pendiente consolidada |
| Rango de fechas | `lte 23:59:59.999` | `>= start AND < fin` exclusivo |
| Body vacío/204 | `TypeError` no controlado | `ApiException` visible |

## 17. Riesgos pendientes

- **BD de `.env` obsoleta (§6.8):** confirmar `DATABASE_URL` productiva; aplicar migraciones e índices recomendados.
- **Reconciliación fiscal:** validar en BD poblada que `grossSales` (desde items) == `SUM(sale.totalSold)` para facturas con `TAX_INCLUDED`; si difiere, decidir si Reportes debe leer el total a nivel factura.
- **Decisiones funcionales no resueltas (no se inventaron reglas):**
  - ¿Las anulaciones de períodos anteriores deben seguir reduciendo el neto del período actual? (Se mantuvo la intención original: sí, como reversión; documentado).
  - ¿El crédito debe aparecer como método de pago en “Método líder”?
  - ¿`listInvoices` compartido debe filtrar `kind=refund` también en historial TPV (hoy se filtra solo en Reportes)?
- **Métricas reales:** repetir medición `EXPLAIN` con la BD productiva antes de aplicar índices.

## 18. Recomendaciones futuras

1. Mover las agregaciones del reporte a PostgreSQL (SUM/GROUP BY por día/categoría) manteniendo el contrato de la API; el frontend ya no necesita la lista completa.
2. Unificar la semántica de rango (exclusiva `lt`) en TODOS los endpoints de ventas/reportes.
3. Añadir un endpoint agregado de dashboard para reemplazar las 6 llamadas `summary` de comparativas.
4. Instrumentar tiempos por etapa (request → SQL → serialización → parseo → render) en desarrollo (logging ya añadido con `TraceLog` en Reportes).
5. Aplicar índices compuestos (§12) tras `EXPLAIN` en la BD productiva.
6. Decidir y documentar el tratamiento contable de créditos/anulaciones como política única del sistema (single source of truth).
7. Considerar parseo fuera del hilo principal (`compute`) si en el futuro se vuelve a requerir listas grandes en cliente.

---

## Apéndice — Evidencia de medición

- Intento de EXPLAIN contra `DATABASE_URL` configurada:
  - Columna detectada: `isDeleted` (camelCase) → la BD no coincide con `schema.prisma` (`is_deleted`).
  - `SELECT count(*) FROM "Sale"` → **0 filas**.
  - → La BD configurada está vacía y con esquema antiguo; no representa datos productivos.
- Scripts de medición (temporales): `tools/report_audit_explain.cjs`, `tools/db_introspect.cjs` (solo lectura; eliminados tras la auditoría).
