# FullPOS PDF Fiscal Template Final

Fecha: 2026-08-18

## Plantillas Encontradas

- Cotización A4: `buildCotizacionPdf`.
- Factura A4: `buildSaleInvoicePdf`.
- Ticket térmico 80mm/58mm: `TicketBuilder.buildPdf`.

## Fuente De Verdad

Las plantillas no recalculan ITBIS. Usan snapshots ya presentes en:

- `CotizacionModel` / `CotizacionItem`: `taxableBase`, `taxAmount`, `exemptAmount`, `lineTotal`, `discountAmount`.
- `SaleModel` / `SaleItemModel`: `taxableBase`, `taxAmount`, `exemptAmount`, `subtotalSold`, `discountAmount`, `ncf`, `fiscalVoucherType`.
- `TicketData.fromSale`: mapea cada `SaleItemModel` hacia `TicketItemData` con base, ITBIS, exento y total.

## Columnas Finales

Para documentos fiscales o con impuestos activos:

```text
Descripción | Cant. | Base | ITBIS | Total
```

`Base` es base total de línea, no precio unitario. `Total` es total de línea. Esto evita ambigüedad en ITBIS incluido, agregado, exento y mixto.

Para documentos tax-off/legacy sin snapshots fiscales se conserva:

```text
Descripción | Cant. | Unitario | Importe
```

## Included / Added / Exempt

- Included: muestra `Precios con ITBIS incluido` y por línea separa `Base`, `ITBIS`, `Total` desde snapshot.
- Added: muestra `ITBIS se agrega al precio` y por línea separa `Base`, `ITBIS`, `Total`.
- Exento: la línea marca `Exento`, usa base/exento de línea e ITBIS `RD$0.00`.
- Mixed: la misma tabla permite gravado y exento sin cambiar columnas.

## Descuentos

- Descuento por línea: aparece como sublínea `Descuento aplicado` sin alterar la fila fiscal.
- Descuento general: aparece en totales antes de base/ITBIS cuando está almacenado.

## Totales

- Cotización fiscal: `Descuento`, `Base imponible`, `Exento`, `ITBIS`, `TOTAL COTIZADO`.
- Factura fiscal: `Base imponible`, `Precios con ITBIS incluido` si aplica, `ITBIS`, `Exento`, `Descuento`, `TOTAL GENERAL`.
- Tax-off/legacy: no muestra `Base imponible RD$0`, `ITBIS RD$0` ni `Exento RD$0`.

## B01 / B02

- B01: encabezado `FACTURA FISCAL`, subtítulo `B01 - CRÉDITO FISCAL`, NCF visible desde snapshot.
- B02: encabezado `FACTURA FISCAL`, subtítulo `B02 - CONSUMIDOR FINAL`, NCF visible desde snapshot, datos fiscales del cliente opcionales.
- Cotización: nunca muestra NCF ni `Factura Fiscal`.

## 80mm

El ticket conserva su diseño existente. No cambia encabezado general, detalle de productos, columnas, tamaños ni flujo de impresión. Solo cuando existe `fiscalVoucherType` B01/B02 y un `ncf` emitido por backend se agrega un bloque compacto antes del detalle:

```text
B01 - CREDITO FISCAL
NCF: ...
CLIENTE: ...
RNC: ...
```

El detalle de productos se mantiene como estaba. El desglose fiscal se muestra en totales con `BASE IMP.`, `EXENTO`, `ITBIS 18%` y el `TOTAL` actual en su posición habitual. Una venta normal sin comprobante fiscal no muestra NCF, B01/B02, RNC cliente, base imponible ni ITBIS agregado por esta fase.

## Histórico Y Multiempresa

Los documentos históricos dependen del modelo recibido. Backend bloquea acceso cross-tenant al cargar ventas/cotizaciones. En reimpresión, los números fiscales salen del snapshot histórico. Si una venta legacy no tiene snapshot, no se inventa desglose fiscal.

## Golden FULLTECH/CANATECH

Fixture validado en tests:

- Total: `RD$25,700.00`.
- Base imponible: `RD$21,779.66`.
- ITBIS: `RD$3,920.34`.
- B01 NCF fixture: `B0100000014`.
- No existe línea `Ajuste RD$300`.

## Tests

- `test/modules/documentos/pdf_fiscal_templates_test.dart`
- `test/core/printing/ticket_builder_pdf_test.dart`

Cubren generación de cotización fiscal golden, B01, B02, tax-off legacy, mapeo de snapshots a ticket y tickets con nombres largos/muchas líneas/montos grandes.

## Matriz Final

| Caso | Estado |
| --- | --- |
| Quote PDF Tax OFF | READY |
| Quote PDF Tax ON | READY |
| Quote PDF Included | READY |
| Quote PDF Added | READY |
| Quote PDF Mixed | READY |
| Invoice PDF Normal | READY |
| B01 PDF | READY |
| B02 PDF | READY |
| Historical PDF | READY |
| Multi-company PDF | READY |
| 80mm Normal | READY |
| 80mm B01 | READY |
| 80mm B02 | READY |
| Long Description | READY |
| Multi-page | READY |
| Large Totals | READY |
| Snapshot Usage | READY |
| No PDF Recalculation | READY |
| PDF Tests | READY |
| Manual visual inspection | MANUAL VISUAL QA PENDING |
