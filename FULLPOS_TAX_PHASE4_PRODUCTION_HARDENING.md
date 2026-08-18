# FullPOS Tax Phase 4 - Production Hardening

Fecha: 2026-08-18

## Regla Arquitectonica

`NCF_SOURCE_OF_TRUTH = DATABASE_BACKEND`

Flutter no genera, incrementa, reserva ni confirma NCF. El flujo autorizado es:

`Flutter -> Backend API -> Validacion fiscal -> PostgreSQL transaction -> NCF -> Sale -> Response`

## Cambios Realizados

- Se elimino la generacion local de NCF en `factura_fiscal_screen.dart`.
- La pantalla legacy de factura fiscal ahora consume `GET /ncf/sequences` y muestra secuencias como informacion administrativa.
- El proximo NCF visible en UI queda marcado como referencia, no como garantia.
- Se removio el boton local de "generar proximo NCF" y cualquier incremento `next + 1` asociado.
- La configuracion local de factura fiscal ya no serializa secuencias NCF.
- Cotizaciones ya no capturan ni muestran NCF, tipo B01/B02/B14/B15 ni vencimiento de comprobante como si fueran factura.
- Los borradores de cotizacion nuevos fuerzan NCF/tipo fiscal legacy a vacio/null.
- Ventas fiscales offline quedan bloqueadas: si hay `fiscalVoucherType`, la app exige conexion para que backend asigne NCF.
- Backend bloquea secuencias activas ambiguas por empresa/tipo.
- Backend bloquea rangos NCF solapados por empresa/tipo.
- La migracion agrega un indice unico parcial para una sola secuencia activa por `company_id + voucher_type`.

## Inventario Legacy Fiscal

| Area | Hallazgo | Accion |
| --- | --- | --- |
| `factura_fiscal_screen.dart` | Guardaba `next`, `end`, `dueDate` en SharedPreferences y generaba NCF local. | Eliminado. Ahora solo lee backend. |
| `cotizaciones_screen.dart` | Permitía tipo/NCF/vencimiento en cotizacion. | UI/validacion/documento visibles retirados. |
| `cotizaciones_historial_screen.dart` | Reconstruia cotizaciones con default `B01`. | Default cambiado a vacio. |
| Offline sales queue | Encolaba payload fiscal para reintento. | B01/B02 offline ahora se bloquea antes de cola. |
| PDF/tickets de ventas | Leen `sale.ncf` desde snapshot backend. | Se mantiene. |
| Tests backend | Usan `B0100000014` como fixture. | Permitido: no es generacion productiva. |

## Postgres Real

Entorno detectado:

- `.env` y `apps/api/.env` tienen `DATABASE_URL` hacia host remoto EasyPanel.
- `apps/api/.env.docker` define un Postgres local por Docker Compose.
- Docker no esta disponible en esta maquina (`docker` no reconocido).
- `npx prisma migrate status` conecto al host remoto y reporto migraciones pendientes.

Decision:

- No se ejecuto `migrate dev` ni `migrate deploy`.
- No se hizo backup ni pruebas destructivas porque no hay entorno dev/staging inequívoco.
- No se imprimieron credenciales.

Resultado de `migrate status`:

- Base remota accesible.
- Migraciones pendientes, incluyendo `20260818120000_add_tax_and_ncf_foundation`.
- Aplicacion de migracion: BLOCKED por seguridad operativa.

## Validacion Ejecutada

- `npx prisma validate`: OK
- `npx prisma generate`: OK
- `npx prisma migrate status`: OK como inspeccion, con migraciones pendientes
- `npm run build`: OK
- `npm test`: OK, 29 tests
- `flutter analyze`: OK
- `flutter test`: OK, 103 tests
- `flutter build web`: OK

Nota: `flutter build web` mantiene advertencias de dry-run Wasm por dependencias existentes (`flutter_secure_storage_web`, `geolocator_web`, `image`, `socket_io_common`).

## Pruebas Postgres Pendientes

No ejecutadas por falta de DB dev/staging segura:

- Verificacion fisica de tablas `taxes`, `ncf_sequences`, `ncf_audit_logs`.
- Verificacion fisica de columnas fiscales en `companies`, `Product`, `Client`, `Sale`, `SaleItem`.
- Constraint real `UNIQUE(company_id, ncf)`.
- Insercion duplicada directa con mismo `companyId + ncf`.
- 20 emisiones concurrentes B01.
- 100 emisiones concurrentes B01.
- Secuencia agotada `14-15`.
- Idempotencia concurrente con mismo `clientRequestId`.
- Reporte multiempresa con empresas A/B.

## Matriz Final

| Component | Status | Nota |
| --- | --- | --- |
| Postgres migration | BLOCKED | Validada por Prisma, no aplicada a remoto sin confirmacion dev/staging. |
| Tax Engine | READY | Unit tests pasan y motor backend es autoridad. |
| Product Tax UI | PARTIAL | Campos integrados; faltan tests widget fiscales especificos. |
| POS Tax Preview | PARTIAL | Backend recalcula; preview local aun necesita cobertura fiscal especifica. |
| Quotes | PARTIAL | NCF retirado; falta snapshot fiscal completo backend por linea. |
| Quote PDF | PARTIAL | Debe validarse visualmente con caso FullTECH/CANATECH. |
| B01 | PARTIAL | Backend valida/consume; falta test Postgres real y UX POS completa. |
| B02 | PARTIAL | Backend consume; falta test Postgres real. |
| NCF DB Transaction | PARTIAL | Implementada con `FOR UPDATE`; falta prueba real. |
| NCF Concurrency | BLOCKED | Requiere Postgres dev/staging. |
| NCF Idempotency | PARTIAL | `companyId + clientRequestId` existe; falta race real. |
| Legacy NCF Removal | READY | No queda generacion local NCF en Flutter. |
| Offline Fiscal Handling | READY | Emision fiscal offline bloqueada. |
| Fiscal Customer | PARTIAL | Datos conectados; faltan tests B01/B02 UI/API. |
| Refunds | BLOCKED | No hay nota credito/reversa fiscal completa. |
| Fiscal PDF | PARTIAL | Lee snapshot backend; falta render QA legal/visual. |
| 80mm Ticket | PARTIAL | Lee snapshot backend; falta QA fisico/visual fiscal. |
| Reports | PARTIAL | Agregados existen; faltan pruebas multiempresa fiscales. |
| Multi-company Isolation | PARTIAL | Guards y scopes existen; faltan pruebas fiscales E2E. |
| Audit Logging | PARTIAL | `RESERVED/ISSUED` implementado; falta verificacion DB real. |
| e-CF | NOT IMPLEMENTED | Sin XML, firma, envio DGII, estados ni acuses. |

## Recomendacion De Siguiente Paso

Levantar Postgres local con Docker o confirmar una base staging sin datos reales. Luego ejecutar `migrate deploy`, backup previo si aplica, y pruebas de concurrencia/idempotencia contra esa base antes de habilitar B01/B02 a usuarios reales.

## Actualizacion fase 5

Se creo `fullpos_staging` en PostgreSQL remoto y se ejecuto validacion real de constraints/concurrencia/idempotencia. Ver `FULLPOS_TAX_PHASE5_STAGING_VALIDATION.md`.

Nota: `migrate deploy` sigue bloqueado por migraciones historicas no aplicables desde DB vacia; la validacion fiscal se hizo con esquema actual via `db push` sobre staging aislado.
