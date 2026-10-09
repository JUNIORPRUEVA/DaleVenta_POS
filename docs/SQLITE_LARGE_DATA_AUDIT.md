# SQLite large-data audit

Fecha: 2026-10-07

Alcance: `apps/fulltech_app/lib` con foco en `sqflite`, `db.query`, `rawQuery`, lecturas completas y caches locales.

## Matriz

| Table | Query | File | Consumer | Limit | Order | Index | Potential rows | Risk | Action | Status |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `offline_sales` | `db.query` por `company_id`, `user_id`, `status` | `lib/core/offline/offline_store.dart` | ventas offline pendientes/historial local | Si, default 100 | `sale_occurred_at DESC` | `idx_offline_sales_scope_status` | Alto por ventas offline si se acumulan | Bajo/medio | Mantener paginado; revisar Web SharedPreferences si crece mucho | SAFE_JUSTIFIED |
| `offline_sale_items` | `db.query` por `company_id`, `sale_local_id` | `lib/core/offline/offline_store.dart` | detalle de una venta offline | Acotado por venta | `created_at ASC` | `idx_offline_sale_items_sale` | Bajo por documento | Bajo | No cambio | SAFE_JUSTIFIED |
| `offline_sale_payments` | `db.query` por `company_id`, `sale_local_id` | `lib/core/offline/offline_store.dart` | detalle de pagos offline | Acotado por venta | `created_at ASC` | `idx_offline_sale_payments_sale` | Bajo por documento | Bajo | No cambio | SAFE_JUSTIFIED |
| `offline_inventory_intents` | `db.query` por `company_id`, `sale_local_id` | `lib/core/offline/offline_store.dart` | replay inventario offline | Acotado por venta | `created_at ASC` | unique idempotency; falta indice simple por venta | Bajo/medio | Bajo | Indice por `sale_local_id` recomendable si crece replay por documento | PENDIENTE_BAJO |
| `pending_actions` | `db.query` por scope/due | `lib/core/offline/offline_store.dart` | sync queue | Si, default 50 | `created_at ASC` | `idx_pending_actions_scope_status_next` | Alto si fallan syncs por dias | Bajo/medio | Mantener limit; resume depende de reintentos | SAFE_JUSTIFIED |
| `cache_entries` | `db.query` por `cache_key` | `lib/core/offline/offline_store.dart` | cache API offline | Si por key | n/a | PK + `idx_cache_entries_updated` | Medio | Bajo | No cambio | SAFE_JUSTIFIED |
| `cotizaciones` | `db.query` por `company_id`, `legacy_quarantined`, `is_draft` | `lib/modules/cotizaciones/data/cotizaciones_local_repository.dart` | cache lista cotizaciones | Si, max 200 | `created_at DESC` | `idx_cotizaciones_company_draft` | Alto si se cachea historial | Medio | Agregado `limit/offset`; `getCachedList` pasa `take` | CORREGIDO |
| `cotizacion_items` | `rawQuery IN (...)` para quotes visibles | `lib/modules/cotizaciones/data/cotizaciones_local_repository.dart` | items de cotizaciones cacheadas | Acotado por pagina de cotizaciones | `id ASC` | `idx_cotizacion_items_company_quote` | Page-sized | Bajo | No cambio | SAFE_JUSTIFIED |
| `operations_orders` | `db.query` paginado | `lib/modules/service_orders/data/service_orders_local_repository.dart` | snapshot local de ordenes de servicio | Si, max 200 | `created_at DESC, id DESC` | `idx_operations_orders_created_at` | Alto si operaciones crece | Bajo/medio | Primera lectura local acotada; requiere UAT con 10K/50K | CORREGIDO_PENDIENTE_UAT |
| `operations_clients` | `db.query id IN (...)` | `lib/modules/service_orders/data/service_orders_local_repository.dart` | lookup clientes snapshot | Acotado por pagina visible | n/a | PK | Page-sized | Bajo | Carga solo clientes referenciados por la pagina local | CORREGIDO |
| `operations_users` | `db.query id IN (...)` | `lib/modules/service_orders/data/service_orders_local_repository.dart` | lookup usuarios snapshot | Acotado por pagina visible | n/a | PK | Page-sized | Bajo | Carga solo usuarios referenciados por la pagina local | CORREGIDO |
| `cliente_detail_cache` | `db.query` por id/company | `lib/modules/clientes/data/cliente_detail_local_repository.dart` | detalle cliente | Si, `limit: 1` | n/a | PK esperada | Bajo | Bajo | No cambio | SAFE_JUSTIFIED |
| payroll local tables | `db.query` con owner/period/employee | `lib/modules/nomina/data/nomina_database_helper.dart` | nomina local | Mixto | varios | indices owner/period/employee | Medio | Bajo/medio | Rutas principales usan filtros; revisar listados admin si nomina local crece | PENDIENTE_MEDIO |
| printer/settings/manual cache | `db.query` config/reference | settings/manual repos | configuracion local | Mixto | n/a | PK/indices simples | Bajo | Bajo | No cambio | SAFE_JUSTIFIED |

## Conclusiones

- HECHO: la cola offline (`pending_actions`) y ventas offline ya tienen limites operativos.
- HECHO: cotizaciones locales tenian una lectura completa para cache; ahora usa `limit/offset` con max 200.
- HECHO: `ServiceOrdersLocalRepository.readSnapshot` ahora lee paginas locales con max 200, indice `created_at DESC, id DESC`, y relaciones solo por IDs visibles.
- HECHO: `ServiceOrdersApi.listOrders` envia `page`/`limit` y materializa como maximo 200 filas aun si un servidor legacy responde lista plana.
- HIPOTESIS: el cache de service orders ya no deberia congelar la primera pantalla local, pero falta UAT 10K/50K y un contrato backend confirmado para paginacion/delta de `/service-orders`.

## Pendientes

- Ejecutar UAT SQLite real con 10K/50K filas de service orders.
- Confirmar/implementar contrato backend paginado para `/service-orders` en el servicio que atiende ese endpoint.
- Agregar indice SQLite para `offline_inventory_intents(sale_local_id)` si se observa volumen alto de intents por venta.
- Crear pruebas de performance local con 10K/50K filas en SQLite real/ffi.
