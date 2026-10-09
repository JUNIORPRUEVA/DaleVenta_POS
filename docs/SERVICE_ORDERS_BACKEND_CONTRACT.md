# Service orders backend contract

Fecha: 2026-10-08

## Hallazgo

- HECHO: Flutter usa `ApiRoutes.serviceOrders = /service-orders`.
- HECHO: Prisma contiene `ServiceOrder`, `ServiceOrderStatusHistory`, `ServiceEvidence` y `ServiceReport`.
- HECHO: existian scripts smoke (`apps/api/scripts/smoke-service-orders*.cjs`) que esperaban `apps/api/src/service-orders`, pero la carpeta no estaba presente en el arbol actual.
- HECHO: se agrego el modulo NestJS `apps/api/src/service-orders` y se registro en `AppModule`.

## Contrato implementado

| Endpoint | Estado | Contrato |
| --- | --- | --- |
| `GET /service-orders` | Implementado | `{ items, page, limit, hasMore, nextPage }`, `limit <= 200`, orden `lastStatusChangedAt DESC, createdAt DESC, id DESC`. |
| `GET /service-orders/sync` | Implementado backend | `{ items, tombstones, nextCursor, hasMore, serverTime }`, `limit <= 200`, cursor opaco por `(updatedAt, id)`. |
| `POST /service-orders` | Implementado | Crea orden tenant-scoped por cliente de la empresa autenticada. |
| `GET /service-orders/:id` | Implementado | Detalle con cliente, historial, evidencias y reportes. |
| `PATCH /service-orders/:id` | Implementado | Actualiza campos operativos manteniendo tenant scope. |
| `PATCH /service-orders/:id/status` | Implementado | Valida transiciones y registra historial. |
| `POST /service-orders/:id/clone` | Implementado | Clona solo desde orden finalizada. |
| `POST /service-orders/:id/evidences` | Implementado | Agrega evidencia. |
| `POST /service-orders/:id/report` | Implementado | Agrega reporte. |
| `DELETE /service-orders/:id` | Implementado | Borrado admin/asistente tenant-scoped. |
| `DELETE /service-orders/debug/purge` | Implementado | Debug admin tenant-scoped. |

## Paginacion

- `page` default: `1`.
- `limit` default: `50`.
- `limit` maximo: `200`.
- La consulta usa `take = limit + 1` para calcular `hasMore`.
- Roles no admin quedan acotados a ordenes creadas o asignadas al usuario.
- Filtro de fechas usa `lastStatusChangedAt`, no `createdAt`.

## Delta sync

- `GET /service-orders/sync?cursor=<opaque>&limit=200` devuelve cambios ordenados por `updatedAt ASC, id ASC`.
- El cursor lo emite el servidor y no depende del reloj del dispositivo.
- La consulta conserva aislamiento por `client.companyId` y visibilidad por rol.
- Las ordenes con `status=CANCELADO` se devuelven como tombstones de cancelacion.
- `DELETE /service-orders/:id` usa soft-delete (`deletedAt`) para que el delta publique tombstone `reason=deleted`; los listados activos filtran `deletedAt=null`.
- Flutter ya cuenta con `ServiceOrdersApi.syncOrders` y `ServiceOrdersLocalRepository.applySyncPage`, que aplica `items`, elimina tombstones locales y persiste `nextCursor` en la misma transaccion SQLite.
- `ServiceOrdersListController` dispara el delta incremental en background despues de la carga inicial acotada, lee checkpoint, pide pagina, aplica transaccion, persiste cursor y continua mientras `hasMore`.
- Hard-deletes no pueden emitirse despues de ocurridos con el schema actual porque `ServiceOrder` no tiene `deletedAt` ni existe una tabla de tombstones.

## Validacion actual

- `npm --workspace apps/api test -- --runTestsByPath src/service-orders/service-orders.service.spec.ts`: PASS, 4 tests.
- `npm run api:build`: PASS.
- `npm --workspace apps/api test -- --runTestsByPath src/service-orders/service-orders.service.spec.ts`: PASS, 6 tests despues de soft-delete tombstones.
- `flutter test test/modules/service_orders/service_orders_local_repository_test.dart`: PASS, 2 tests.
- `flutter analyze`: PASS.
- `node scripts/audit-large-dataset-queries.mjs`: PASS con zero-open findings.

## Pendiente

- Ejecutar UAT HTTP real contra API local/UAT con `?page=1&limit=50`.
- Validar payload, `hasMore`, `nextPage`, filtros y permisos con datos 10K/50K.
- Validar HTTP/UAT que la rutina incremental de pantalla no congela con 10K/50K y conserva paginas previas ante fallo de una pagina posterior.
- Ejecutar migracion solo en LOCAL/UAT antes de HTTP UAT; produccion no autorizada en este trabajo.
