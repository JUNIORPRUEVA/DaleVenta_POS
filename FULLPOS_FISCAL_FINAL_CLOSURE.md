# FullPOS Fiscal Final Closure

Fecha: 2026-08-18

## Estado

- ITBIS incluido, agregado, exento y mixto: READY.
- Productos fiscales PC/móvil/POS: READY.
- Cotizaciones fiscales con snapshot: READY.
- Conversión cotización -> factura: READY. La factura usa `sourceQuotationId` y snapshots persistidos de `Cotizacion`/`CotizacionItem`; no recalcula desde producto/configuración vigente.
- NCF B01/B02: READY para emisión transaccional existente. La cotización no consume NCF; la conversión fiscal consume un NCF.
- Devoluciones fiscales operativas: READY. La venta original queda intacta y se crea un documento `kind = refund` negativo, enlazado a `refundedSaleId`, con cantidades máximas protegidas por ítem.
- Reportes: READY. Distinguen ventas brutas, devoluciones, ventas netas, utilidad comercial y utilidad neta fiscal.
- Multiempresa: READY en las rutas tocadas; `companyId` sale del JWT/tenant, no del body.
- e-CF/XML/firma/DGII/E31/E32: OUT OF SCOPE.

## Casos Dorados Protegidos

- Incluido: 1180 -> base 1000, ITBIS 180, total 1180.
- Agregado: 1000 -> base 1000, ITBIS 180, total 1180.
- Exento: 500 -> exento 500, ITBIS 0, total 500.
- Mixto: 1180 incluido + 500 exento -> base 1000, ITBIS 180, exento 500, total 1680.
- Cotización Fulltech/CANATECH: total 25700, base 21779.66, ITBIS 3920.34.

## Cambios Clave

- `Sale.sourceQuotationId` preserva origen de cotización.
- `Sale.refundedSaleId` y `SaleItem.refundedSaleItemId` preservan origen de devolución.
- `commercialProfit`, `netTaxProfit`, `commercialMargin`, `netTaxMargin` quedan disponibles sin alterar comisiones actuales.
- `POST /sales/:id/return` acepta devolución total o parcial y mantiene compatibilidad con el flujo anterior.
- Flutter envía `sourceQuotationId` al cobrar cotizaciones guardadas.

## Quality Gates Ejecutados

- `npx prisma validate --schema prisma/schema.prisma`: PASS.
- `npm run build` en `apps/api`: PASS.
- `npm test` en `apps/api`: PASS, 44 tests.
- `flutter analyze` en `apps/fulltech_app`: PASS.
- `flutter test` en `apps/fulltech_app`: PASS, 116 tests.
- `flutter build web` en `apps/fulltech_app`: PASS.

## Nota De Migraciones/Staging

`npx prisma migrate status` apuntó a la DB remota configurada en `.env` y reportó divergencia entre el historial legacy remoto y el baseline local nuevo. Por seguridad no se ejecutó `migrate deploy` ni despliegue de producción.

Para staging real se debe preparar una base limpia/baselineada con el historial `20260818190000_phase6_baseline`, luego aplicar:

- `20260818193000_quote_tax_snapshots`
- `20260818203000_sales_quote_refund_snapshots`

Después correr `npm run test:staging:fiscal` con variables reales de staging.
