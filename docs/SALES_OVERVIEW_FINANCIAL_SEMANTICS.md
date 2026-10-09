# Sales overview financial semantics

Fecha: 2026-10-07

Fuente: `apps/api/src/reports/reports.service.ts`, caracterizado por `apps/api/src/reports/reports.service.spec.ts` y `apps/api/src/reports/reports.credit-collection.spec.ts`.

## Alcance

`ReportsService.salesOverview` genera el reporte financiero de ventas para una empresa (`companyId`) y rango de fechas dominicano. La semantica actual queda congelada antes de migrar la implementacion a agregados DB.

## Rango y filtros base

| Campo | Semantica |
| --- | --- |
| Tenant | Todas las lecturas usan `companyId` del usuario autenticado. |
| Usuario | Roles admin ven toda la empresa; roles no admin filtran por `sale.userId = user.id`. |
| Fecha desde/hasta | `from` y `to` se interpretan como dias en America/Santo_Domingo. El rango real es `gte inicio 04:00 UTC` y `lt dia siguiente del to 04:00 UTC`. |
| Categoria | `category` filtra por categoria normalizada de `SaleItem.product.categoria`; items sin categoria son `Sin categoria`. |
| Ventas brutas | `Sale.kind = invoice`, `saleDate` dentro del rango. No filtra `isDeleted` en esta lectura; las cancelaciones se revierten por separado. |
| Cancelaciones/devueltas | `Sale.kind = invoice`, `isDeleted = true`, `deletedAt` dentro del rango. |
| Documentos refund | `Sale.kind = refund`, `isDeleted = false`, `saleDate` dentro del rango. Si el refund pertenece a una venta cancelada dentro del mismo rango, se excluye para evitar doble descuento. |

## Matriz de campos

| Field | Source tables | Filters | Date semantics | Cancellation effect | Refund effect | Credit effect | Formula |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `range.from/to` | input | n/a | rango dominicano convertido a UTC exclusivo | n/a | n/a | n/a | `gte/lt` calculado por `buildDateRange`. |
| `filters.category` | input + productos/items | normalizacion `es-DO` | n/a | n/a | n/a | prorratea pagos si hay categoria | Categoria real visible o valor solicitado. |
| `categories` | `Product` | productos inventariables de la empresa | n/a | n/a | n/a | n/a | Categorias unicas del catalogo; vacio/null => `Sin categoria`. En Prisma real se obtiene por SQL agregado/distinct; fallback legacy solo para mocks/clientes incompletos. |
| `kpis.totalSales` | `Sale` | ventas visibles tras filtro de categoria | `saleDate` | canceladas emitidas en rango cuentan como venta bruta y luego se revierten | refunds no incrementan ventas | credito no cambia conteo | `visibleSales.length`. |
| `kpis.grossSales` | `SaleItem` | items visibles de ventas invoice | `saleDate` | incluido en bruto si la venta fue emitida en rango | no incluye refunds | no depende de cobro | `sum(item.subtotalSold)`. |
| `kpis.returnedSales` | `SaleItem` | cancelaciones visibles + refunds visibles | `deletedAt` para cancelacion, `saleDate` para refund | resta monto absoluto de items cancelados | resta monto absoluto de items refund | n/a | `abs(sum(returned/refund item.subtotalSold))`. |
| `kpis.netSales` / `totalSold` | ventas + retornos | categoria aplicada | mixto segun arriba | bruto menos cancelaciones | bruto menos refunds | n/a | `grossSales - returnedSales`. |
| `kpis.totalCost` | `SaleItem` | solo ventas invoice visibles | `saleDate` | no se reduce aqui | no se reduce aqui | n/a | `sum(item.subtotalCost)`. |
| `kpis.totalProfit` / `commercialProfit` | `SaleItem` | solo ventas invoice visibles | `saleDate` | no se reduce aqui | no se reduce aqui | n/a | `sum(item.profit)`. |
| `kpis.netProfit` | ventas + retornos + caja | categoria aplicada | ventas por `saleDate`, retornos por fecha de retorno | resta utilidad de cancelacion | resta utilidad de refund | no depende de cobro | `totalProfit - returnedProfit - profitExpenses`. |
| `kpis.totalCommission` | `Sale` | ventas visibles | `saleDate` | no se reduce aqui | no se reduce aqui | n/a | `sum(sale.commissionAmount * categoryAllocation)`. |
| `kpis.taxableBase` | `SaleItem` | ventas visibles | `saleDate` | no se reduce aqui | no se reduce aqui | n/a | `sum(item.taxableBase)`. |
| `kpis.taxAmount` | `SaleItem` | ventas visibles | `saleDate` | no se reduce aqui | no se reduce aqui | n/a | `sum(item.taxAmount)`. |
| `kpis.exemptAmount` | `SaleItem` | ventas visibles | `saleDate` | no se reduce aqui | no se reduce aqui | n/a | `sum(item.exemptAmount)`. |
| `kpis.discountAmount` | `SaleItem` + `Sale` | ventas visibles | `saleDate` | no se reduce aqui | no se reduce aqui | n/a | `sum(lineDiscountAmount) + generalDiscount * categoryAllocation`, donde `generalDiscount = max(0, sale.discountAmount - saleLineDiscountTotal)`. |
| `kpis.avgTicket` | ventas visibles | categoria aplicada | `saleDate` | ventas canceladas emitidas en rango cuentan en denominador visible | refunds no cuentan | n/a | `grossSales / visibleSales.length`, o 0. |
| `kpis.totalReturns` | retornos visibles | categoria aplicada | `deletedAt`/`saleDate` | cada cancelacion visible suma 1 | cada refund visible suma 1 salvo doble descuento | n/a | `returns.count`. |
| `kpis.totalExpenses` | `CashMovement` agregado DB | `type=OUT`, `movementType=expense`, `affectsProfit=true`; no aplica con categoria | `createdAt` | n/a | n/a | n/a | `sum(amount)` solo sin filtro de categoria. |
| `kpis.cashIncome` | ventas + credit payments + cash movements agregado DB | categoria aplicada | pago inicial por `saleDate`; abonos por `paidAt`; caja por `createdAt` | n/a | n/a | credito se separa en pago inicial y abonos reales | Sin categoria: `initial cash + credit payments cash + cash IN`; con categoria: sin cash IN. |
| `kpis.cashExpense` | `CashMovement` agregado DB | `type=OUT`; no aplica con categoria | `createdAt` | n/a | n/a | n/a | Sin categoria: `sum(OUT)`; con categoria: 0. |
| `kpis.creditPaymentsCash` | `SaleCreditPayment` | empresa, rango, vendedor de la venta si no admin | `paidAt` real | n/a | n/a | solo abonos del periodo | `sum(cashAmount * categoryAllocation)`. |
| `kpis.creditPaymentsTransfer` | `SaleCreditPayment` | igual anterior | `paidAt` real | n/a | n/a | solo abonos del periodo | `sum(transferAmount * categoryAllocation)`. |
| `kpis.creditPaymentsCount` | `SaleCreditPayment` | igual anterior | `paidAt` real | n/a | n/a | cuenta filas de abono consultadas | `creditPaymentsInRange.length`. |
| `paymentMethods` | ventas + credit payments | categoria aplicada | venta por `saleDate`, abono por `paidAt` | n/a | n/a | `paymentCashAmount/paymentTransferAmount` son acumulados; se resta ledger lifetime para derivar pago inicial | Efectivo/Transferencia con monto total y conteo de operaciones. |
| `salesSeries` | ventas visibles | categoria aplicada | dia dominicano de `saleDate` | no descuenta retorno | no descuenta refund | n/a | `sum(subtotalSold)` agrupado por dia. Sin filtro de categoria se calcula por SQL agregado; con categoria conserva fallback materializado para respetar prorrateo/filtro por item. |
| `profitSeries` | ventas visibles | categoria aplicada | dia dominicano de `saleDate` | no descuenta retorno | no descuenta refund | n/a | `sum(profit)` agrupado por dia. Sin filtro de categoria se calcula por SQL agregado; con categoria conserva fallback materializado. |
| `topProducts` | `SaleItem` | ventas visibles | `saleDate` | no descuenta retorno | no descuenta refund | n/a | Agrupa por producto+unidad, ordena por `totalSales desc`, top 10. Sin filtro de categoria se calcula por SQL agregado. |
| `topClients` | `Sale` + `Client` snapshot | ventas visibles | `saleDate` | no descuenta retorno | no descuenta refund | credito cuenta igual que cualquier venta | Agrupa por cliente, `Consumidor final` si null, top 10 por gasto. Sin filtro de categoria se calcula por SQL agregado. |
| `categoryProfits` | `SaleItem` | ventas visibles | `saleDate` | no descuenta retorno | no descuenta refund | n/a | Agrupa ventas/costo/utilidad/cantidad por categoria. Sin filtro de categoria se calcula por SQL agregado con buckets de unidad y `COUNT(DISTINCT saleId)`. |
| `inventory` | `Product` | `itemType=PRODUCT`, `trackInventory=true`, empresa; categoria si aplica | estado actual del catalogo, no historico | n/a | n/a | n/a | Conteos, unidades, valor costo/venta, sin stock, bajo stock, sin costo. En Prisma real se calcula con SQL agregado agrupado por categoria/unidad; fallback legacy solo para mocks/clientes incompletos. |
| `audit.*Rows` | fuentes consultadas | mismas fuentes | segun cada fuente | informa filas usadas | informa filas refund | informa filas de abono | Conteos de filas consultadas/materializadas; `cashMovementRows` proviene de `_count` agregado cuando el cliente Prisma soporta `groupBy`. |

## Sutilezas congeladas

- `paymentCashAmount` y `paymentTransferAmount` se tratan como acumulados de la venta. Para ventas a credito, el pago inicial se deriva restando el ledger lifetime de `SaleCreditPayment`.
- Los abonos de credito se atribuyen por `paidAt`, no por `saleDate`.
- El filtro de usuario de abonos conserva semantica de vendedor de la venta, no cobrador del abono.
- Con filtro de categoria, pagos iniciales y abonos se prorratean por participacion de esa categoria en el total de la venta.
- Si un abono aparece en el ledger pero el acumulado de la venta no lo refleja, la implementacion actual puede compensar el pago inicial con signo opuesto y exponer una advertencia de invariante.
- Las series, top products, top clients y category profits se construyen desde ventas brutas visibles; las devoluciones/cancelaciones impactan KPIs netos, no esas listas.
- Sin filtro de categoria, el reporte usa ruta agregada DB para totales financieros brutos/netos, retornos, pago inicial de credito, movimientos de caja, inventario/categorias, abonos de credito, series, top products, top clients y category profits en clientes Prisma reales.
- Con filtro de categoria, los abonos y los desgloses por item conservan fallback materializado para respetar el prorrateo por items hasta migrar ese bloque con equivalencia dedicada.
