# Delta sync and tombstone audit

Fecha: 2026-10-07

## Clasificacion observada

| Module | Current mode | Evidence | Tombstone handling | Clock safety | Resume | Status |
| --- | --- | --- | --- | --- | --- | --- |
| Offline sales upload | UPLOAD_ONLY | `OfflineStore.pending_actions`, idempotency key, status/attempts/next retry | No aplica para descarga; venta local se marca synced/error | Reintento usa cola local, no reloj de dispositivo para cursor remoto | Si, por `pending_actions` persistente | PARTIAL_GO |
| API cache entries | FULL_RESPONSE_CACHE | `cache_entries` guarda payload por cache key | No tombstones; reemplazo por key | `updated_at` local para eviction, no cursor servidor | Cache fallback, no sync incremental | PARTIAL |
| Cotizaciones local cache | FULL_PAGE_CACHE | `CotizacionesRepository.listAndCache` cachea filas recibidas | Delete local por ID existe; no tombstone server-side incremental | Depende del fetch server y pagina | Parcial por cache local | PARTIAL |
| Service orders local cache | BOUNDED_FIRST_PAGE_CACHE + DELTA_ENDPOINT + LOCAL_TRANSACTIONAL_APPLY + BACKGROUND_LOOP + SOFT_DELETE_TOMBSTONES | `ServiceOrdersApi.listOrders` pide `page/limit`; `ServiceOrdersLocalRepository.readSnapshot` lee max 200 y relaciones visibles; backend expone `GET /service-orders/sync`; SQLite aplica `items/tombstones` y persiste cursor en transaccion; controlador dispara delta en background; borrado operativo pasa a soft-delete `deletedAt` | Tombstone incremental para cancelaciones (`status=CANCELADO`) y eliminaciones (`deletedAt`) | Cursor servidor opaco basado en `(updatedAt, id)`, no reloj del dispositivo | Reanuda por `nextCursor` persistido solo despues de aplicar la pagina local; conserva carga inicial acotada | GO_CODE_PENDING_HTTP_UAT |
| Catalog/product UI cache | FULL_LIST_OR_PAGE_DEPENDING_REPOSITORY | Repositorios API ahora paginan en backend; cache offline no es delta canonico | Archivado/borrado depende de respuesta API/realtime | No hay sync token global | Parcial | PARTIAL |
| Sales/invoices history | PAGED_REMOTE + CACHE_FALLBACK | repos de ventas aceptan paginas backend | Cancelaciones/refunds via response paginada; no tombstone stream local | Page/date based, no server cursor global | Load-more conserva paginas previas | PARTIAL_GO |

## Hallazgos

- HECHO: existe cola persistente para acciones pendientes, con idempotency, intentos, `next_attempt_at`, errores y estado permanente.
- HECHO: no hay arquitectura global de delta sync por `updatedAt`/server cursor para todos los modulos de alto crecimiento.
- HECHO: service orders dejo de depender de lectura local completa para abrir la lista.
- HECHO: service orders tiene contrato backend incremental: `GET /service-orders/sync?cursor=<token>&limit=200`, respuesta `{ items, tombstones, nextCursor, hasMore, serverTime }`, cursor servidor opaco por `(updatedAt, id)`.
- HECHO: service orders emite tombstones de cancelacion con `{ id, deletedAt, reason: "cancelled", version }`.
- HECHO: service orders local aplica paginas delta en SQLite dentro de una transaccion: upsert de `items`, delete local por tombstones y persistencia de `nextCursor` al final.
- HECHO: service orders list controller ejecuta el loop incremental en background despues de mostrar la carga inicial/cache, y actualiza desde `readSnapshot(limit: 200)` por pagina aplicada.
- HECHO: service orders ya no hard-deletea en el flujo operativo; `DELETE /service-orders/:id` marca `deletedAt`, y el delta emite tombstone `reason: "deleted"`.
- HECHO: tombstones no estan estandarizados como contrato cross-module; algunos flujos usan soft-delete/cancelacion en payload, otros reemplazan snapshot completo.
- HECHO: Web usa SharedPreferences/local storage para algunos fallback paths; eso no es apto para datasets 50K.

## Contrato implementado para service orders

Endpoint:

```text
GET /service-orders/sync?cursor=<opaque>&limit=200
```

Respuesta:

```json
{
  "items": [],
  "tombstones": [],
  "nextCursor": null,
  "hasMore": false,
  "serverTime": "2026-10-08T00:00:00.000Z"
}
```

Reglas verificadas:

- `limit` queda acotado a 200 y la consulta pide `limit + 1` para detectar `hasMore`.
- El cursor no depende del reloj del dispositivo; se decodifica como `(updatedAt, id)` emitido por el servidor.
- La consulta queda aislada por tenant mediante `client.companyId`.
- Usuarios no admin conservan el filtro de visibilidad `createdById` o `assignedToId`.
- Filas con `status=CANCELADO` salen como tombstones, no como items activos.
- Cursor invalido falla antes de consultar.
- El cliente local persiste `nextCursor` despues de aplicar los cambios en SQLite.
- La pantalla no bloquea la primera carga esperando a que termine todo el delta.

Pendiente real:

- Replicar el contrato en ventas, cotizaciones, productos, clientes, caja e inventario donde aplique.
- Validar por HTTP/UAT interrupcion/reanudacion real y comportamiento 10K/50K.

## Recomendacion de arquitectura

| Requirement | Proposed contract |
| --- | --- |
| Cursor | Server-issued cursor or server timestamp, not device clock only. |
| Delta endpoint | `GET /module/sync?cursor=<token>&limit=200`. |
| Response | `{ items, tombstones, nextCursor, hasMore, serverTime }`. |
| Tombstone | `{ id, deletedAt, reason, version }` for deletes/archives/cancellations. |
| Resume | Persist cursor only after page applied transactionally. |
| Idempotency | Upserts by stable ID; upload queue keeps idempotency key. |

## Estado

DELTA_SYNC: PARTIAL_GO_SERVICE_ORDERS_BACKEND_AND_LOCAL_APPLY

TOMBSTONES: PARTIAL_GO_SERVICE_ORDERS_CANCELLED_AND_DELETED

Motivo: hay piezas robustas para upload/offline queue, paginas remotas, primera lectura local acotada y un endpoint delta real para service orders. No existe todavia un contrato delta/tombstone uniforme para todos los modulos grandes, y los hard-deletes de service orders no son recuperables sin cambiar contrato/schema.
