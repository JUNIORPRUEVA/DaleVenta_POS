# FullPOS Fiscal Multi-Tenant Security Audit

Fecha: 2026-08-18

## Alcance

Revision de aislamiento multiempresa y seguridad fiscal para impuestos, ventas, clientes, productos, NCF, cotizaciones, facturas, tickets, devoluciones y reportes en `apps/api` y `apps/fulltech_app`.

## Principio Aplicado

Toda entidad fiscal operativa debe pertenecer a una empresa (`companyId`) y toda lectura/escritura backend debe derivar ese `companyId` del token, no del cliente Flutter. El frontend puede sugerir datos fiscales, pero el backend recalcula y decide.

## Matriz De Seguridad

| Area | Lectura aislada | Escritura aislada | Restriccion DB | Guard backend | Cobertura | Estado |
| --- | --- | --- | --- | --- | --- | --- |
| Company fiscal settings | Si | Si | Columnas en `Company` | `requireTenant` | Build/test unitario indirecto | PARTIAL |
| Taxes | Si | Si | `unique(company_id, name)` | Admin-like + `companyId` | Parcial | PARTIAL |
| Products tax fields | Si | Si | Campos por producto | Filtro `companyId` existente | Parcial | PARTIAL |
| Clients fiscal data | Si | Si | Campos en `Client` | Filtro `companyId` existente | Parcial | PARTIAL |
| Sales | Si | Si | `Sale.company_id` | `requireTenant`, caja por empresa | Parcial | PARTIAL |
| SaleItems fiscal snapshot | Via venta | Via venta | Relacion con venta | Creacion transaccional | Unitario motor fiscal | PARTIAL |
| NCF sequences | Si | Si | `unique(company_id, voucher_type, prefix)` | Admin-like + `companyId` | Build | PARTIAL |
| NCF issued values | Si | Via venta | `unique(company_id, ncf)` | Transaccion + `FOR UPDATE` | Falta concurrencia DB real | PARTIAL |
| NCF audit logs | Si | Via transaccion | Indices por empresa | Servicio backend | Build | PARTIAL |
| Quotes | Parcial | Parcial | No verificado completo | Logica mixta | Falta unificacion | PARTIAL |
| Fiscal invoices module | Parcial | Parcial | Modelo anterior | No fuente fiscal unica | Falta rediseño | BLOCKED |
| Refunds/returns | Si para venta | Parcial | No hay nota fiscal | Reversa stock actual | Sin fiscal completo | BLOCKED |
| Reports | Si | N/A | Agregados por venta | Filtros existentes | Parcial | PARTIAL |
| Offline sales | N/A local | Cola local | `clientRequestId` unico | Reintento idempotente | Flutter tests generales | PARTIAL |

## Controles Implementados

- Secuencias NCF se consultan y administran por empresa.
- Emision NCF sucede en la misma transaccion que crea la venta.
- `FOR UPDATE` bloquea filas candidatas de secuencia durante la reserva.
- `Sale(companyId, ncf)` evita duplicados dentro de la empresa.
- `NcfAuditLog` registra reserva y emision.
- Flutter no calcula ni asigna NCF; solo envia tipo y datos fiscales de cliente.
- Ventas offline mantienen `clientRequestId` y payload fiscal para reintento.

## Riesgos Restantes

- Falta prueba automatizada de dos ventas simultaneas tomando la misma secuencia.
- La pantalla actual de factura fiscal todavia conserva configuracion local de secuencias para B01/B02/B14/B15; debe migrarse a los endpoints NCF.
- Cotizaciones tienen campos fiscales, pero no estan completamente subordinadas al motor fiscal backend.
- Devoluciones no emiten nota de credito ni reversa fiscal auditable.
- El modulo `FiscalInvoice` de contabilidad sigue siendo mas archivo/registro que factura fiscal emitida desde venta.
- No hay e-CF: falta XML, firma, envio/recepcion DGII, estados y acuses.

## Recomendacion

No marcar la fiscalidad como produccion final todavia. El nucleo backend B01/B02 ya tiene una base correcta para crecer, pero antes de despliegue fiscal real deben cerrarse pruebas de concurrencia, UI de administracion NCF, devoluciones fiscales, reconciliacion de cotizaciones y revision legal de formatos impresos/PDF.
