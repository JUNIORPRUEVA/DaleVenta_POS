# FullPOS Tax Phase 2 Implementation

Fecha: 2026-08-18

## Archivos modificados

- Backend Prisma: `apps/api/prisma/schema.prisma`
- Migracion: `apps/api/prisma/migrations/20260818120000_add_tax_and_ncf_foundation/migration.sql`
- Backend fiscal: `apps/api/src/tax/*`
- Settings backend: `apps/api/src/settings/settings.service.ts`
- Productos backend: `apps/api/src/products/*`
- Ventas backend: `apps/api/src/sales/*`
- Clientes backend: `apps/api/src/clients/*`
- Reportes backend: `apps/api/src/reports/reports.service.ts`
- Flutter settings/productos/ventas/tickets/PDF.

## Migraciones

La migracion agrega:

- `taxes`
- columnas fiscales en `companies`
- columnas fiscales en `Product`
- snapshots fiscales en `Sale` y `SaleItem`
- datos fiscales opcionales en `Client`
- `ncf_sequences`
- indices multiempresa y `unique(company_id, ncf)`

Todos los defaults preservan impuestos apagados.

## Endpoints

- `GET /taxes`
- `POST /taxes`
- `PATCH /taxes/:id`
- `GET /company/fiscal-settings`
- `PATCH /company/fiscal-settings`
- `POST /sales/calculate`
- `POST /sales` recalcula y guarda snapshots fiscales cuando aplica.

## Comportamiento

- `taxEnabled = false`: ventas actuales conservan total sin impuestos.
- `taxEnabled = true` + precio incluido: backend extrae base e ITBIS.
- `taxEnabled = true` + precio agregado: backend suma impuesto sobre base.
- Producto exento: no divide precio ni calcula impuesto.
- Ventas fiscales guardan base, impuesto, exento, descuento y modo de precio.

## UI

- Configuracion de empresa muestra “Impuestos y comprobantes”.
- Si impuestos estan apagados, las opciones fiscales se ocultan.
- Si estan activos, se puede elegir precio incluido/agregado y NCF on/off.
- Modelos Flutter ya reciben campos fiscales para productos y ventas.

## PDF y tickets

- Tickets muestran ITBIS, exento, NCF y RNC cliente si existen.
- PDF carta y PDF de venta muestran base imponible, ITBIS, exento, descuento y NCF si existen.
- Si no hay impuestos, mantienen presentacion simple.

## Reportes

Backend expone agregados fiscales:

- `taxableBase`
- `taxAmount`
- `exemptAmount`
- `discountAmount`

## Tests y builds

- `npm run build`: OK
- `npm test`: OK, 29 tests
- `flutter analyze`: OK
- `flutter test`: OK, 103 tests
- `flutter build web`: OK

Nota: `flutter build web` emitio advertencias de dry-run Wasm por dependencias existentes (`flutter_secure_storage_web`, `geolocator_web`, `image`, `socket_io_common`), pero produjo `build/web`.

## Actualizacion fase 3

La fase 3 agrego endpoints backend para secuencias NCF B01/B02, reserva transaccional con `FOR UPDATE`, bitacora `NcfAuditLog`, campos fiscales en el payload de ventas Flutter y documentos nuevos:

- `FULLPOS_TAX_PHASE3_NCF_AND_INVOICING.md`
- `FULLPOS_FISCAL_MULTI_TENANT_SECURITY_AUDIT.md`

Estado recomendado: base fiscal backend avanzada, pero aun no certificable como produccion DGII/e-CF.

## Estado

- Configuracion impuestos: PARTIALLY READY
- Productos: PARTIALLY READY
- POS: PARTIALLY READY
- Ventas: PARTIALLY READY
- Descuentos: PARTIALLY READY
- NCF: PARTIALLY READY
- PDF: PARTIALLY READY
- Tickets: PARTIALLY READY
- Reportes: PARTIALLY READY
- Devoluciones: PARTIALLY READY
- Cotizaciones: PARTIALLY READY

## Riesgos restantes

- No existe todavia reserva automatica/transaccional de NCF.
- La UI de producto no permite seleccionar tratamiento fiscal explicitamente desde todos los formularios.
- El POS no muestra aun desglose fiscal antes de guardar.
- Cotizaciones siguen necesitando refactor completo para semantica incluido/agregado.
- Devoluciones no generan documento fiscal reverso propio.
- Reglas legales DGII y tratamientos de productos requieren revision externa.
