# Auditoria de datasets grandes - ventas, facturas, backups

Fecha: 2026-10-07

## Evidencia forense incorporada

- HECHO: en cache local real de Cafeteria La Bomba, `GET /sales` tenia 7179 registros y un payload aproximado de 22.8 MB.
- HECHO: en cache local real de Cafeteria La Bomba, `GET /sales/invoices` tenia 7179 registros y un payload aproximado de 23.0 MB.
- HECHO: empresa control local con el mismo cliente/build tenia `GET /sales` en 109 registros y `GET /sales/invoices` en 99 registros.
- HECHO: el log local del cliente registro timeouts `DioExceptionType.receiveTimeout` en `GET /sales` y `GET /sales/invoices` antes del `FormatException: El backup no contiene el modulo requerido ventas`.
- HECHO: `CloudBackupService.createCloudBackup` no agregaba `ventas.json` cuando fallaba la captura del modulo; luego `inspectBackupZipForCompany` rechazaba el ZIP porque `ventas` es requerido.

Cadena causal demostrada para el incidente observado:

`createCloudBackup` intentaba capturar `ventas` con un `GET /sales` historico completo. En Cafeteria La Bomba ese endpoint devolvia un volumen real de miles de ventas y decenas de MB, suficiente para provocar timeout en el cliente. Al fallar esa captura, `ventas` quedaba en `failedModules` y no se agregaba a `modules`. El ZIP parcial se generaba, pero el inspector estricto detectaba que faltaba el modulo requerido `ventas` y lanzaba el `FormatException`.

## Endpoints auditados

| Area | Endpoint / flujo | Riesgo encontrado | Estado |
| --- | --- | --- | --- |
| Ventas | `GET /sales` | Historico completo sin limite por defecto; payload grande por includes de cliente, usuario, items y refunds. | Corregido: paginacion `page/limit`, default 50, max 200, metadata `hasMore/nextPage`. |
| Facturas | `GET /sales/invoices` | Mismo riesgo que ventas; pantalla de historial cargaba todo el rango inicial. | Corregido: paginacion backend y carga incremental en UI. |
| Backup local legacy | `CloudBackupService` modulos grandes | Usaba una sola llamada completa por modulo. | Corregido en modulos migrados: captura por paginas de 200 y consolidacion JSON por modulo. |
| Creditos ventas | `GET /sales/credits` | Puede crecer con cartera historica, pero suele ser subconjunto operativo. | Pendiente: paginar si el volumen real supera presupuesto. |
| Caja/turnos | endpoints de movimientos e historiales de caja | Historiales sin contrato comun; resumen de turno carga ventas completas del turno. | Historial de movimientos/sesiones cerrado paginado; resumen de turno pendiente de agregados DB. |
| Compras/facturas compra | `GET /purchases`, `GET /purchases/invoices` | Listados potencialmente grandes. | Pendiente para fase siguiente. |
| Productos/clientes | catalogos | Pueden crecer, aunque menor payload por registro que ventas con items. | Pendiente: paginacion o delta sync por modulo. |
| Backup canonico backend | `apps/api/src/backups` | Extrae tablas tenant completas para archivo canonico. | Aceptable como proceso backend controlado; requiere batching si se observa presion de memoria. |

## Matriz de seguimiento extendida

| Modulo | Endpoint | Current limit | Default limit | Max limit | Orden | Relations | Riesgo payload | UI consumer | Backup consumer | Estado |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Sales | `GET /sales` | `page/limit` | 50 | 200 | `saleDate desc, id desc` | cliente, usuario, items, refunds | Alto | ventas/reportes | `ventas` | Corregido |
| Invoices | `GET /sales/invoices` | `page/limit` | 50 | 200 | `saleDate desc, id desc` | cliente, usuario, items, refunds | Alto | facturas | `facturas_ventas` | Corregido |
| Clientes | `GET /clients` | `page/limit/pageSize` | 50 | 200 | `lastActivityAt desc, createdAt desc, id desc` | lista liviana | Medio/alto | clientes, ventas, servicios | `clientes` | Corregido backend; UI aun carga primera pagina/lista legacy |
| Productos | `GET /products` | `page/limit` | 50 | 200 | `nombre asc, id asc` | lista liviana | Alto en catalogos grandes | catalogo, ventas | `productos` | Corregido backend; UI aun usa lista acumulada |
| Suplidores | `GET /purchases/suppliers` | `page/limit` | 50 | 200 | `commercialName asc, id asc` | stats | Medio | compras | `suplidores` | Corregido backend |
| Compras | `GET /purchases/orders` | `page/limit` | 50 | 200 | `orderDate desc, createdAt desc, id desc` | items incluidos | Alto | compras | `compras` | Paginado; LIST DTO liviano pendiente |
| Facturas compra | `GET /purchases/invoices` | `page/limit` | 50 | 200 | `invoiceDate desc, createdAt desc, id desc` | supplier, order summary, user | Medio | compras | `facturas_compras` | Corregido backend |
| Inventory movements | `GET /inventory/movements` | `take/skip` | 25 | 100 | `createdAt desc, id desc` | producto, almacenes, usuario | Alto | inventario | no legacy | Ya acotado; contrato comun pendiente |
| Inventory stock report | `GET /inventory/stock-report` | ninguno | n/a | n/a | `nombre asc` | warehouseStocks | Alto si 50k productos | inventario | no legacy | Riesgo: requiere paginacion/export separado |
| Cash movements history | `GET /cash/movements/history` | `page/limit/take` | 50 | 200 | `createdAt desc, id desc` | sesion liviana | Alto | caja | `movimientos_caja` | Corregido backend; Flutter compatible con `items` |
| Cash closed sessions | `GET /cash/sessions/closed` | `page/limit/take` | 50 | 200 | `closedAt desc, id desc` | ninguna | Medio | caja | no legacy | Corregido backend; Flutter compatible con `items` |
| Cash current session summary | `GET /cash/summary` y cierre de turno | ninguno | n/a | n/a | n/a | ventas completas con items, movimientos, abonos | Alto si un turno acumula muchas ventas | turno actual/cierre | no legacy | Pendiente: migrar a agregados DB o resumen incremental |
| Reports overview | `GET /reports/sales-overview` | agregacion parcial | n/a | n/a | n/a | multiples findMany | Alto por reportes | reportes | no | Pendiente migrar a agregados DB |
| Cotizaciones | `GET /cotizaciones` | `page/limit/take` | 50 | 200 | `createdAt desc, id desc` | items | Medio/alto | cotizaciones | `cotizaciones` | Corregido backend; backup agregado como modulo requerido/paginado |
| Contabilidad closes | `GET /contabilidad/closes` | ninguno/rango | n/a | n/a | `date desc, createdAt desc` | transfers/vouchers | Alto | cierres | no legacy | Pendiente |
| Payables | `GET /contabilidad/payables/*` | ninguno | n/a | n/a | fecha desc | payments/service | Medio/alto | pagos | backup legacy | Pendiente |
| Payroll periods | payroll admin | `take` | 120 | 120 | `startDate desc` | ninguna | Medio | nomina | no legacy | Cerrado con bound fijo |
| Payroll employees | payroll admin | `take` | 500 | 500 | `nombre asc` | ninguna | Medio | nomina | no legacy | Cerrado con bound fijo |
| Payroll entries/status | payroll admin | `take` | 500 | 500 | fecha desc | ninguna | Medio | nomina | no legacy | Cerrado con bound fijo |
| Warranty configs | warranty admin/resolve | `take` | 200/100 | 200/100 | prioridad/fecha | categoria | Bajo/medio | garantias | no legacy | Cerrado con bound fijo |
| Work scheduling employees | work scheduling | `take` | 500 | 500 | role/createdAt | config por pagina | Medio | turnos laborales | no legacy | Cerrado con bound fijo |
| Work scheduling profiles/exceptions | work scheduling | `take` | 100/500 | 100/500 | nombre/fecha | days | Medio | turnos laborales | no legacy | Cerrado con bound fijo |

## Cambios de hardening realizados despues del incidente

- Se creo contrato comun backend en `apps/api/src/common/pagination/page-pagination.ts`.
- `GET /clients` ahora usa limite maximo 200 y respuesta `items/page/limit/hasMore/nextPage`.
- `GET /products` ahora pagina y acepta `search`, `category`, `warehouseId`, `includeArchived`.
- `GET /purchases/suppliers`, `GET /purchases/orders`, `GET /purchases/invoices` ahora paginan.
- `GET /cotizaciones` ahora usa limite maximo 200 y respuesta `items/page/limit/hasMore/nextPage`.
- `GET /cash/movements/history` y `GET /cash/sessions/closed` ahora usan limite maximo 200 y orden estable.
- Backup local legacy ahora captura por paginas: `clientes`, `cotizaciones`, `productos`, `ventas`, `facturas_ventas`, `movimientos_caja`, `suplidores`, `compras`, `facturas_compras`.

## Comparacion control vs Cafeteria La Bomba

- Empresa control: payloads pequenos, lista de ventas/facturas carga, backup incluye `ventas`.
- Cafeteria La Bomba: payloads de ventas/facturas sobre 22 MB, timeouts en lista y backup, backup no incluye `ventas`.

Conclusion: la diferencia observada no requiere asumir "internet malo" ni "dato viejo"; el factor diferencial verificado es volumen real del tenant combinado con endpoints historicos completos.

## Pendientes explicitos

- Identificar si existe un registro individual corrupto: no demostrado todavia. La evidencia actual apunta primero a volumen/timeout.
- Ejecutar comparacion READ-ONLY contra base productiva cuando el acceso DB este disponible; el intento local con Prisma no alcanzo el host PostgreSQL.
- Migrar por completo `ReportsService.salesOverview` a agregados DB por rangos/categorias. En este corte tiene tope defensivo de 5000 filas por fuente para evitar OOM/timeout, pero no es aun la arquitectura final.
- Completar `ReportsService.salesOverview` con agregados DB finales; el tope actual de 5000 filas es defensivo, no arquitectura definitiva.

## Clasificacion real de hallazgos large-data

Comando fuente:

```powershell
node scripts/audit-large-dataset-queries.mjs --markdown
```

Resultado actual verificado el 2026-10-07:

| Total | CRITICAL | HIGH | MEDIUM | LOW | SAFE_JUSTIFIED | UNCLASSIFIED |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 21 | 0 | 0 | 0 | 0 | 21 | 0 |

Interpretacion:

- `CRITICAL=0`: no queda un hallazgo sin mitigacion minima que bloquee por si solo el avance de esta etapa de clasificacion.
- `HIGH=0`: los 13 HIGH anteriores fueron cerrados con batching, paginacion, bounds o agregados DB.
- `MEDIUM=0`: los hallazgos administrativos pendientes fueron cerrados con bounds reales o reclasificados con evidencia de pagina/ID/semana.
- `LOW=0`: las rutas LOW restantes quedaron acotadas o salieron del reporte por bounds/fail-closed.
- `SAFE_JUSTIFIED=21`: hallazgos acotados por ID, pagina, semana, tabla de configuracion pequena, o fallback legacy no usado por Prisma real.
- `UNCLASSIFIED=0`: el auditor ya no emite `REVIEW`; todo hallazgo queda clasificado.

Hallazgos HIGH cerrados en este corte:

| ID | Modulo | Archivo:linea | Consumidor | Accion requerida |
| --- | --- | --- | --- | --- |
| LD-001 | backups | `apps/api/src/backups/backups.service.ts` | `runAutomaticBackups` | Cerrado: empresas paginadas por cursor en lotes de 25; cada tenant falla aislado y el job reporta processed/succeeded/failed. |
| LD-003 | cash | `apps/api/src/cash/cash.service.ts` | detalle de turno | Cerrado: movimientos del detalle de turno paginados con `movementsPage/movementsLimit` y metadata `movementsPage`. |
| LD-009 | contabilidad | `apps/api/src/contabilidad/contabilidad.service.ts` | cierres/finanzas | Cerrado: `getCloses` paginado con contrato comun. |
| LD-010 | contabilidad | `apps/api/src/contabilidad/contabilidad.service.ts` | resumen financiero | Cerrado: totales de cierres y bancos por agregados DB. |
| LD-011 | contabilidad | `apps/api/src/contabilidad/contabilidad.service.ts` | depositos ejecutados | Cerrado: depositos agregados por Prisma aggregate / SQL para `depositByType`; latest deposit usa `findFirst`. |
| LD-014 | contabilidad | `apps/api/src/contabilidad/contabilidad.service.ts` | pagos/servicios | Cerrado: `getPayablePayments` paginado con contrato comun. |
| LD-030 | purchases | `apps/api/src/purchases/purchases.service.ts` | recomendaciones | Cerrado: recomendaciones acotadas a productos accionables de bajo stock y pendientes solo para IDs de esa pagina. |
| LD-032 | sales | `apps/api/src/sales/sales.service.ts` | contador fiscal auxiliar | Cerrado: usa `count` cuando Prisma real lo soporta; fallback legacy queda acotado. |
| LD-034 | sales | `apps/api/src/sales/sales.service.ts` | ventas por usuario | Cerrado: salida acotada y orden estable. |
| LD-035 | sales | `apps/api/src/sales/sales.service.ts` | offsets de cancelaciones/devoluciones | Cerrado: IDs de canceladas acotados y offsets por `groupBy`. |
| LD-036 | sales | `apps/api/src/sales/sales.service.ts` | resumen ventas usuario | Cerrado: `summaryByUser` usa `groupBy` para activos. |
| LD-037 | sales | `apps/api/src/sales/sales.service.ts` | resumen refunds usuario | Cerrado: `summaryByUser` usa `groupBy` para refunds. |
| LD-038 | sales | `apps/api/src/sales/sales.service.ts` | resumen cancelaciones usuario | Cerrado: `summaryByUser` usa `groupBy` para cancelaciones. |

Hallazgos MEDIUM cerrados en este corte final:

| Modulo | Archivo | Cierre |
| --- | --- | --- |
| Payroll | `apps/api/src/payroll/payroll.service.ts` | Periodos, empleados, entradas, comisiones pendientes, estados de pago e identidad de historial personal tienen `take` explicito. |
| Warranty configs | `apps/api/src/warranty-configs/warranty-configs.service.ts` | Listado admin y resolucion por producto/categoria tienen bounds fijos. |
| Work scheduling | `apps/api/src/work-scheduling/work-scheduling.service.ts` | Empleados, perfiles y excepciones tienen bounds fijos; hydration de configs queda acotada a la pagina de empleados. |

Hallazgos ya tratados en este corte:

- `CashService.buildSummaryForSession`: la ruta de produccion ahora usa `groupBy`, `aggregate` y SQL agrupado para totales de ventas, abonos, movimientos y categorias; el `findMany` historico queda como fallback legacy para mocks/clientes Prisma incompletos.
- `inventory/zero-config-inventory`: el backfill global ahora pagina empresas y productos por cursor; la consulta de `warehouseStock` queda acotada al lote de productos actual.
- `ReportsService.salesOverview`: se agrego un presupuesto defensivo de 5000 filas por fuente; si el rango excede ese presupuesto, falla explicitamente en vez de congelar por memoria/tiempo.
- Auditor final de esta etapa: `findings=21 CRITICAL=0 HIGH=0 MEDIUM=0 LOW=0 SAFE_JUSTIFIED=21 UNCLASSIFIED=0`.
