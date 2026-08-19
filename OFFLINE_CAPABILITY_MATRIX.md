# FullPOS Cloud - Offline Capability Matrix

Estado: foundation + ventas no fiscales offline endurecidas. La app puede leer datos cacheados, conservar un outbox seguro por tenant y persistir ventas no fiscales offline en SQLite nativo con header/items/payment/inventory intents/outbox atomicos.

## Politica

- Toda lectura cacheada debe estar aislada por `companyId` y `userId`.
- Toda accion diferida debe persistirse en `pending_actions` con `company_id`, `user_id`, tipo, entidad, idempotency key, intentos, ultimo intento y proximo intento.
- El logout normal limpia cache visible e imagenes, pero conserva el outbox. La cola solo se procesa cuando vuelve a iniciar sesion el mismo alcance empresa/usuario.
- La eliminacion de cuenta y cambios de scope de instalacion pueden destruir el outbox local.
- Fallos 400, 401, 403, 404, 409 y 422 no se reintentan en bucle; quedan como `failed` o `conflict`.
- Facturas fiscales/NCF, permisos criticos, cierre de caja, autorizaciones admin y cambios globales sensibles requieren backend online salvo implementacion posterior con protocolo especifico.
- En Web/PWA, el almacenamiento de venta offline usa fallback de preferencias y no ofrece la misma atomicidad SQLite nativa; se mantiene como soporte parcial hasta implementar IndexedDB/Service Worker dedicado.

## Capacidades Actuales

| Area | Estado local | Outbox | Seguro offline | Riesgo restante |
| --- | --- | --- | --- | --- |
| Catalogo/productos | OFFLINE READ | Crear/editar/eliminar ya encola en fallos de red | IMPLEMENTED_NOT_E2E_VERIFIED | Resolver conflictos de stock/precio con version por entidad |
| Imagenes de producto | OFFLINE READ nativo via cache manager, clave versionada | No aplica | IMPLEMENTED_NOT_E2E_VERIFIED | Web depende del cache del navegador; falta test filesystem real de imagen |
| Ventas no fiscales | OFFLINE WRITE nativo: `offline_sales`, `offline_sale_items`, `offline_sale_payments`, `offline_inventory_intents` | Si | VERIFIED en local/restart/idempotencia backend | Falta E2E integrado Flutter app + API real |
| Ventas fiscales/NCF | ONLINE_ONLY | No | VERIFIED online-only | Correcto por cumplimiento fiscal |
| Clientes | OFFLINE WRITE parcial upsert/delete | Si | IMPLEMENTED_NOT_E2E_VERIFIED | Falta dependency graph para cliente nuevo + venta offline |
| Caja | OFFLINE WRITE parcial | Si | IMPLEMENTED_NOT_E2E_VERIFIED | Cierres y conciliacion siguen online hasta protocolo dedicado |
| Cotizaciones | OFFLINE WRITE parcial con repositorio local propio | Si | IMPLEMENTED_NOT_E2E_VERIFIED | Revisar consistencia con permisos y expiraciones |
| Manual interno | OFFLINE WRITE parcial | Si | IMPLEMENTED_NOT_E2E_VERIFIED | Adjuntos/media requieren politica propia |
| Permisos/roles | READ_ONLY snapshot de sesion | No | READ_ONLY | Backend revalida al sincronizar |

## Cambios Implementados

- `pending_actions` migra a version 2 con columnas de tenant, usuario, terminal, entidad, idempotencia, backoff y permanencia.
- `OfflineStore` migra a version 3 con tablas locales atomicas para venta no fiscal offline.
- `SyncQueueService` resuelve empresa/usuario activo desde la sesion guardada antes de encolar, contar o procesar.
- `SyncQueueService.processPending()` filtra por `companyId`/`userId` y solo toma acciones vencidas.
- Reintentos usan backoff explicito con jitter pequeno; errores permanentes se marcan sin replay infinito.
- `ApiOfflineCacheInterceptor` genera claves `http-cache:v2:<scope>:<method>:<uri>`.
- Logout normal preserva `pending_actions`; borra cache visible e imagenes para no exponer datos a otra sesion.
- `ProductNetworkImage` usa clave de imagen normalizada/versionada para invalidacion estable.
- Backend `Sale` ya tiene `@@unique([companyId, clientRequestId])` y el servicio devuelve la venta existente ante reintentos idempotentes.
- E2E backend verificado: repetir el mismo `clientRequestId` mantiene 1 venta, 1 item, pago embebido unico, stock descontado una sola vez y precio snapshot original.
- Reinicio local verificado: venta offline mantiene header, items, payment, inventory intents y pending action tras cerrar/reabrir `OfflineStore`.
- Recuperacion verificada: acciones `syncing` obsoletas vuelven a `pending` sin cambiar idempotency key.

## Fases Recomendadas

1. Productos read-only y outbox basico: completado como foundation.
2. UI de cola: mostrar pendientes, fallidos, conflicto, reintentar, descartar y soporte tecnico sin payload sensible.
3. Ventas offline completas no fiscales: UI de pendientes, comprobante pendiente visible y reconciliacion guiada de stock/caja.
4. Conflictos por entidad: version/updatedAt por producto, cliente, caja y cotizacion con resolucion guiada.
5. Service worker/PWA: cache de imagenes y assets para Web con cuotas y limpieza por tenant.
6. Auditoria backend: endpoints idempotentes con `clientRequestId`/`operationId` obligatorio y pruebas multi-tenant.
