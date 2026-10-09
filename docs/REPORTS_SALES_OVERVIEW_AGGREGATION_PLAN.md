# Sales overview aggregation plan

Fecha: 2026-10-08

## Estado agregado actual

`ReportsService.salesOverview` ya usa agregados DB en clientes Prisma reales para:

- Movimientos de caja.
- Inventario/categorias de catalogo.
- Abonos de credito del periodo sin filtro de categoria.
- Series de ventas/utilidad sin filtro de categoria.
- Top products sin filtro de categoria.
- Top clients sin filtro de categoria.
- Category profits sin filtro de categoria.

## Materializacion restante

El bloque principal sin filtro de categoria ya tiene ruta agregada DB y test que verifica que no use `Sale.findMany` / `Product.findMany` en clientes Prisma reales.

El bloque con filtro de categoria todavia materializa ventas con items:

- `sales`: `Sale.findMany` con `items.product` para ventas invoice por `saleDate`.
- `returnedSales`: `Sale.findMany` con `items.product` para cancelaciones por `deletedAt`.
- `refundSales`: `Sale.findMany` con `items.product` para documentos `refund` por `saleDate`.
- `cancelledInRangeSales`: `Sale.findMany` de ids cancelados para evitar doble descuento de refunds.

Esos arreglos alimentan todavia:

- `visibleSales`.
- `visibleReturnedSales`.
- Totales brutos/costo/utilidad/impuestos/descuentos/comision.
- Pago inicial de credito derivado de acumulados menos ledger lifetime.
- Conteo de operaciones iniciales cash/transfer.
- Retornos netos por cancelacion/refund.
- `zeroCostItems` y `zeroCostSoldAmount`.
- Auditoria `saleRows`, `saleItemRows`, `returnedRows`, `refundDocumentRows`, `paymentBreakdownViolations`.
- Filtro por categoria y prorrateo de abonos por categoria.

## Ruta segura de migracion restante

1. Mantener fallback materializado para `category != null` hasta migrar prorrateo por categoria.
2. Crear ruta agregada completa para `category != null` con CTEs por venta/categoria.
3. Reproducir exactamente:
   - `initialCash = paymentCashAmount - lifetimeCreditCash`.
   - `initialTransfer = paymentTransferAmount - lifetimeCreditTransfer`.
   - `paymentBreakdownViolations` con epsilon monetario `0.005`.
   - `discountAmount = lineDiscount + max(0, sale.discountAmount - lineDiscount)`.
   - `returnedSales/cost/profit = abs(sum(returned/refund item amounts))`.
   - Exclusión de refund si `refundedSaleId` pertenece a venta cancelada dentro del rango.
4. Comparar salida agregada vs salida legacy con fixtures:
   - cash, transfer, credit, credit payment later date.
   - refund parcial y total.
   - cancelacion en el mismo periodo.
   - descuentos, ITBIS, exento.
   - costo cero.
   - cliente null.

## Riesgo

La migracion restante concentra prorrateos por categoria, el punto mas sensible del reporte. No debe mezclarse con UAT/write/migraciones. Debe cubrirse con equivalencia dedicada antes de retirar el fallback materializado del path category-filtered.
