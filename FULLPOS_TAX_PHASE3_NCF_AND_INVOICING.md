# FullPOS Tax Phase 3 - NCF Transaccional e Invoicing Fiscal

Fecha: 2026-08-18

## Resumen

La fase 3 agrega una base backend transaccional para NCF B01/B02, endurece la emision de ventas fiscales por empresa y conecta el payload fiscal de Flutter al flujo de ventas online/offline. Esta fase mejora mucho la seguridad fiscal, pero no deja el sistema certificado como e-CF ni como cumplimiento DGII completo.

## Backend

Archivos principales:

- `apps/api/prisma/schema.prisma`
- `apps/api/prisma/migrations/20260818120000_add_tax_and_ncf_foundation/migration.sql`
- `apps/api/src/tax/ncf.service.ts`
- `apps/api/src/tax/tax.controller.ts`
- `apps/api/src/tax/tax.dto.ts`
- `apps/api/src/sales/sales.service.ts`
- `apps/api/src/sales/dto/create-sale.dto.ts`

### Modelos y migracion

Se agregaron/extendieron:

- `NcfSequence.startNumber`: inicio explicito de rango autorizado.
- `NcfAuditLog`: bitacora de acciones `RESERVED` e `ISSUED`.
- Indices por `companyId`, tipo y NCF para aislamiento y busqueda.
- Restriccion `Sale(companyId, ncf)` para evitar duplicados por empresa.

La migracion conserva defaults no fiscales para empresas existentes: impuestos y NCF quedan apagados hasta que una empresa los active.

### Endpoints NCF

- `GET /ncf/sequences`
- `POST /ncf/sequences`
- `PATCH /ncf/sequences/:id`

Reglas:

- Solo usuarios admin-like pueden crear o editar secuencias.
- Todas las consultas y escrituras estan filtradas por `companyId`.
- En esta fase solo se aceptan `B01` y `B02`.
- El prefijo debe coincidir con el tipo de comprobante.
- No se permite reducir `endNumber` por debajo de lo ya usado.

### Emision transaccional

`SalesService.create()` ahora:

- Normaliza y valida `fiscalVoucherType`.
- Obtiene datos fiscales desde el DTO o desde el cliente asociado.
- Rechaza comprobantes si `ncfEnabled` no esta activo para la empresa.
- Valida cliente fiscal para comprobantes que lo requieren.
- Reserva el NCF dentro de la misma transaccion que descuenta stock y crea la venta.
- Usa `FOR UPDATE` sobre `ncf_sequences` para evitar carreras concurrentes.
- Incrementa `nextNumber` solo dentro de la transaccion.
- Registra auditoria `RESERVED` y `ISSUED`.
- Persiste `fiscalVoucherType`, `ncf`, `fiscalCustomerTaxId` y `fiscalCustomerName` en la venta.
- Maneja `P2002` por `clientRequestId` para devolver la venta existente cuando aplica.

## Flutter

Archivos principales:

- `apps/fulltech_app/lib/core/api/api_routes.dart`
- `apps/fulltech_app/lib/modules/ventas/data/ventas_repository.dart`
- Modelos y renderers fiscales agregados en fases previas.

Cambios:

- Rutas API para `ncfSequences`.
- `createSale()` acepta `fiscalVoucherType`, `fiscalCustomerTaxId` y `fiscalCustomerName`.
- El payload fiscal viaja tanto en venta online como en cola offline.
- Tickets y PDF consumen los snapshots fiscales recibidos desde backend.

## Estado Por Modulo

| Modulo | Estado | Nota |
| --- | --- | --- |
| Settings fiscales | PARTIAL | Configuracion persistente y UI existen; falta cobertura E2E. |
| Productos con impuesto | PARTIAL | Campos backend/Flutter listos; falta flujo completo de auditoria masiva. |
| Calculo POS backend | READY | Motor central probado; backend recalcula antes de guardar. |
| NCF B01/B02 backend | PARTIAL | Reserva transaccional implementada; faltan pruebas de concurrencia con DB real. |
| Cliente fiscal | PARTIAL | Campos y validacion B01 conectados; falta UX final en todos los puntos de venta. |
| Factura PDF/ticket | PARTIAL | Muestra snapshots si existen; falta plantilla fiscal legal final. |
| Cotizaciones | PARTIAL | Hay campos fiscales, pero requiere reconciliacion completa con motor backend. |
| Devoluciones | BLOCKED | No existe nota de credito/reversa fiscal completa. |
| e-CF | NOT IMPLEMENTED | No hay firma, XML, recepcion, tracking ni integracion DGII. |

## Validacion Ejecutada

- `npm run build`: OK
- `npm test`: OK, 29 tests
- `flutter analyze`: OK
- `flutter test`: OK, 103 tests
- `flutter build web`: OK

Nota: `flutter build web` genero `build/web` y mantuvo advertencias de dry-run Wasm por dependencias existentes (`flutter_secure_storage_web`, `geolocator_web`, `image`, `socket_io_common`).

## Pendientes Criticos

- Agregar pruebas de concurrencia NCF contra Postgres real.
- La pantalla legacy de factura fiscal ya no genera NCF local y ahora lee secuencias desde backend como referencia administrativa. Falta una pantalla completa para crear/editar secuencias.
- Definir regla fiscal completa para devoluciones y notas de credito.
- Unificar cotizaciones al mismo contrato de calculo que ventas.
- Revisar legalmente formato de factura/ticket antes de usarlo como comprobante fiscal oficial.
- Implementar e-CF como modulo separado, no como extension menor de B01/B02.

## Actualizacion fase 4

Ver `FULLPOS_TAX_PHASE4_PRODUCTION_HARDENING.md` para el cierre de generacion local de NCF, bloqueo de emision fiscal offline, auditoria de migracion Postgres y matriz final.
