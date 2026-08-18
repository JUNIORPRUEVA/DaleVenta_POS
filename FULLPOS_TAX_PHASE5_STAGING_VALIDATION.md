# FullPOS Tax Phase 5 - Staging Validation

Fecha: 2026-08-18

## Entorno Staging

- Host PostgreSQL: `gcdndd.easypanel.host`
- Base original detectada: `daleventa_pos`
- Base staging creada: `fullpos_staging`
- Credenciales: no documentadas ni impresas
- Produccion: no se migro, no se reseteo, no se modificaron secuencias reales

## Migraciones

Resultado:

- `npx prisma migrate deploy` contra `fullpos_staging`: BLOCKED
- Causa: migracion historica `20260210000001_add_punch` falla en una DB vacia porque espera relacion `"User"` luego de que una migracion previa de cloud sync borra/reestructura esa tabla.
- Accion tomada: como `fullpos_staging` fue creada exclusivamente para esta validacion, se recreo y se aplico el esquema actual con `npx prisma db push --accept-data-loss`.

Decision:

- No declarar `Database Migration READY`.
- Antes de produccion hay que reparar/baselinear el historial Prisma.
- La validacion fiscal de Postgres se ejecuto sobre esquema actual real, no sobre mocks.

## Esquema Fisico Verificado

Tablas verificadas en PostgreSQL:

- `taxes`
- `ncf_sequences`
- `ncf_audit_logs`

Indices/constraints verificados:

- `Sale_company_id_ncf_key`
- `Sale_company_id_client_request_id_key`
- `ncf_sequences_company_id_voucher_type_active_key`
- `ncf_sequences_no_overlap`

## Evidencia Real

Resultado de `node scripts/fiscal-staging-validation.cjs` contra `fullpos_staging`:

| Prueba | Resultado |
| --- | --- |
| NCF duplicado misma empresa | blocked |
| Mismo NCF en empresas distintas | allowed |
| 20 ventas fiscales concurrentes | 20 sales / 20 unique NCF / nextNumber 21 |
| 100 ventas fiscales concurrentes | 100 sales / 100 unique NCF / nextNumber 101 |
| 20 requests mismo `clientRequestId` | 1 sale / 1 NCF / nextNumber 2 |
| Secuencia 14-15 agotada | B0100000014 OK, B0100000015 OK, tercera blocked |
| Dos secuencias activas B01 | blocked |
| Rangos solapados B01 | blocked |
| 100 cotizaciones | 0 NCF consumed |
| FULLTECH quote test | Base 21,779.66 / ITBIS 3,920.34 / Total 25,700.00 |
| `taxEnabled=false` | no fiscal behavior |

Nota operativa:

- Intentar `connection_limit=120` fallo por limite del servidor: `too many clients already`.
- La prueba final uso `connection_limit=13` y `pool_timeout=120`, representando 100 solicitudes concurrentes desde la aplicacion con cola de pool realista.

## UX Fiscal Cerrada En Esta Fase

- Pantalla legacy de factura fiscal: ya no genera NCF local.
- Secuencias NCF: se leen del backend y se muestran solo como referencia administrativa.
- Cotizaciones: no muestran NCF, B01/B02/B14/B15 ni vencimiento de comprobante.
- Offline fiscal: venta con comprobante fiscal requiere conexion; no se encola con NCF falso.
- `.env.staging.example`: agregado sin secretos.
- Script reproducible: `npm run test:staging:fiscal`.

## Quality Gate

- `npx prisma validate`: OK
- `npx prisma generate`: OK
- `npx prisma migrate status`: BLOCKED por historial no aplicado en staging con `db push`
- `npm run build`: OK
- `npm test`: OK, 29 tests
- `flutter analyze`: OK
- `flutter test`: OK, 103 tests
- `flutter build web`: OK
- PostgreSQL integration test: OK para constraints/concurrencia/idempotencia/cotizaciones

Advertencia Flutter:

- `flutter build web` mantiene advertencias Wasm de dependencias existentes (`flutter_secure_storage_web`, `geolocator_web`, `image`, `socket_io_common`).

## Pendientes No Cerrados

- Baseline de migraciones historicas creado en Fase 6 y probado contra DB vacia (`fullpos_migration_test`).
- Ejecutar despliegue controlado de produccion con backup + `migrate resolve --applied 20260818190000_phase6_baseline`; no aplicar baseline SQL sobre tablas productivas existentes.
- Probar los mismos flujos por HTTP/API autenticada, no solo via Prisma/SQL sobre staging.
- Completar devoluciones fiscales total/parcial con snapshot negativo.
- Terminar snapshot fiscal completo de cotizaciones por linea en backend.
- Render QA visual de PDF factura B01/B02 y ticket 80mm.
- Snapshot historico del emisor en ventas fiscales.
- Tests Flutter especificos de producto/POS fiscal y cambio de empresa.
- Checklist oficial DGII para factura tradicional.
- e-CF sigue fuera de alcance.

## Matriz Final

| Component | Status | Nota |
| --- | --- | --- |
| Database Migration | PARTIAL | Fase 6 baseline probado en DB vacia; produccion pendiente de plan controlado. |
| Postgres Constraints | READY | Verificados fisicamente en `fullpos_staging`. |
| NCF Concurrency | READY | 20 y 100 solicitudes: NCF unicos. |
| Idempotency | READY | 20 concurrentes con mismo key: 1 sale / 1 NCF. |
| Multi-company Isolation | PARTIAL | Constraint NCF multiempresa probado; falta API auth cross-tenant. |
| Tax Settings | PARTIAL | Defaults OFF probados; falta E2E settings. |
| Product Tax UX | PARTIAL | Campos existen; falta UX final tipo Alegra y tests widget. |
| POS Tax UX | PARTIAL | Backend calcula; falta selector comprobante completo en POS. |
| Quotes | PARTIAL | 100 quotes no consumen NCF y total FullTECH probado; falta snapshot fiscal por linea backend. |
| B01 | PARTIAL | NCF/transaccion OK; falta E2E HTTP/PDF final. |
| B02 | PARTIAL | Infra lista; falta E2E B02. |
| Refunds | BLOCKED | No implementadas fiscalmente. |
| PDF | PARTIAL | Usa snapshots; falta QA visual/legal final. |
| 80mm | PARTIAL | Usa snapshots; falta prueba fisica/visual. |
| Reports | PARTIAL | Falta prueba fiscal multiempresa real por endpoint. |
| Offline Fiscal | READY | Fiscal con NCF bloqueado sin conexion. |
| Traditional NCF Production Readiness | PARTIAL | Algoritmo/constraints OK; baseline listo, E2E y despliegue controlado faltan. |
| e-CF | NOT IMPLEMENTED | Sin XML, firma, envio DGII ni acuses. |

## Decision De Readiness

No iniciar e-CF todavia. Primero cerrar:

- despliegue controlado del baseline/migraciones;
- E2E API autenticado B01/B02;
- devoluciones fiscales;
- QA PDF/ticket;
- snapshot historico del emisor.
