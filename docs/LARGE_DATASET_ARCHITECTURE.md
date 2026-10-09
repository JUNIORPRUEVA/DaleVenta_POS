# Arquitectura para datasets grandes

Fecha: 2026-10-07

## Contrato de paginacion

Los listados operativos grandes deben usar paginacion explicita:

```json
{
  "items": [],
  "page": 1,
  "limit": 50,
  "hasMore": false,
  "nextPage": null
}
```

Reglas actuales para listados migrados:

- `limit` por defecto: 50.
- `limit` maximo: 200.
- `page` minimo: 1.
- Orden estable con `id` como desempate cuando aplica.
- Para detectar siguiente pagina se solicita `limit + 1`, se devuelve solo `limit` y se calcula `hasMore`.
- Todo query conserva `companyId` del tenant autenticado; no hay lectura cross-tenant.

## UI

Las pantallas de ventas/facturas no deben cargar historicos completos al abrir. El primer render carga la primera pagina y el scroll solicita paginas siguientes. Los filtros locales operan sobre las paginas cargadas; busqueda server-side queda como mejora cuando se necesite buscar fuera del conjunto ya cargado.

## Backup local legacy

Los modulos `clientes`, `cotizaciones`, `productos`, `ventas`, `facturas_ventas`, `movimientos_caja`, `suplidores`, `compras` y `facturas_compras` se capturan por paginas de 200 filas. El ZIP conserva modulos requeridos estrictos; `ventas` no se vuelve opcional. Si una pagina falla, el productor debe fallar la captura del modulo y el validador seguira impidiendo restaurar/aceptar backups incompletos.

La escritura local de modulos paginados es memory-bounded en Flutter: cada pagina se codifica y escribe al archivo JSON del modulo antes de pedir la siguiente. La metadata `pagination.memoryBounded=true` identifica esta ruta. No se debe reintroducir `allRows.addAll(page)` para modulos high-growth.

## Backup canonico backend

`BackupExtractor` extrae modulos directos y modulos indirectos high-growth por paginas de 1000 filas ordenadas por `id`. Esto evita consultas monoliticas `findMany` para productos, ventas, items, compras, cotizaciones, caja, inventario y demas modulos directos con `companyId`, preservando el mismo manifiesto canonico y el mismo contenido final del ZIP.

Pendiente estructural: `BackupArchiveBuilder`, `BackupValidator`, `BackupArchiveReader`, import/download y restore siguen operando sobre `Buffer` completos. La extraccion ya no depende de una sola consulta por modulo, pero la serializacion ZIP/validacion/restore aun requieren una fase posterior de streaming real antes de declarar GO 50K global para backup/restore backend.

## Cache local y delta sync

Estado actual:

- Cache local por endpoint, rango, limite y pagina.
- Fallback a cache cuando la pagina solicitada existe y la red falla.

Siguiente evolucion recomendada:

- Agregar `updatedAt`/cursor por modulo para delta sync.
- Separar DTO liviano de lista vs detalle completo.
- Invalidar paginas afectadas por ventas nuevas, cancelaciones, devoluciones y pagos de credito.
- Mantener backup como flujo paginado completo, no como lectura desde la cache de UI.

## Presupuestos operativos

- Listado inicial: maximo 50 ventas/facturas.
- Pagina maxima: 200 registros.
- Backup: paginas de 200 registros por modulo grande.
- Ningun endpoint de lista operativa debe depender de traer miles de registros para que la pantalla inicial sea usable.

## Contrato comun backend

`apps/api/src/common/pagination/page-pagination.ts` define:

- `DEFAULT_PAGE_LIMIT = 50`.
- `MAX_PAGE_LIMIT = 200`.
- `normalizePagePagination`.
- `toPageResult`.

Modulos alineados al contrato comun:

- Ventas/facturas.
- Clientes.
- Productos.
- Cotizaciones.
- Suplidores.
- Ordenes de compra.
- Facturas de compra.
- Historial de movimientos de caja.
- Historial de turnos cerrados.

## Resumen de turno/cierre

`CashService.buildSummaryForSession` no debe materializar todas las ventas/items del turno en memoria para calcular totales operativos. La ruta de produccion usa agregados DB:

- `sale.groupBy` para totales por estado, tipo y metodo de pago.
- `saleCreditPayment.aggregate` para abonos del turno y ledger de credito.
- `cashMovement.groupBy` para entradas, salidas, gastos y retiros.
- SQL agrupado para resumen por categoria e invariantes de desglose de pago.

La ruta legacy con `findMany` completo queda reservada como fallback tecnico para mocks/tests o clientes Prisma incompletos.

## Backfills y jobs globales

Los procesos que recorren empresas o catalogos no deben cargar todo el universo antes de trabajar. `zero-config-inventory` pagina empresas por lotes de 100 y productos por lotes de 500, y cada consulta de stock queda acotada al lote actual.

`BackupsService.runAutomaticBackups` pagina empresas activas por cursor en lotes de 25. La ejecucion por tenant queda aislada: un fallo de la empresa A incrementa `failed` y registra warning, pero no aborta la empresa B.

## Listados financieros y operativos

- `CashService.sessionDetail` devuelve los movimientos del turno paginados; `summary` sigue agregado por DB.
- `ContabilidadService.getCloses` devuelve cierres paginados.
- `ContabilidadService.getCloseFinancialSummary` calcula totales por agregados DB y evita cargar todos los cierres con transferencias.
- `ContabilidadService.getPayablePayments` devuelve pagos paginados.
- `PurchasesService.recommendations` limita el universo a productos accionables de bajo stock y calcula pendientes solo para esos productos.
- `SalesService.summaryByUser` usa agregados por usuario para ventas, devoluciones y cancelaciones.
- `PayrollService` limita rutas administrativas de periodos, empleados, entradas, comisiones pendientes y estados de pago con bounds explicitos.
- `WarrantyConfigsService` limita listados y resolucion de configuraciones con bounds explicitos.
- `WorkSchedulingService` limita empleados, perfiles y excepciones; las consultas de configuracion por empleado quedan acotadas a la pagina actual.

## Reportes de ventas

`ReportsService.salesOverview` conserva una mitigacion defensiva: cada fuente de datos legacy tiene presupuesto maximo de 5000 filas. Si el rango excede el presupuesto, el servicio falla explicitamente con error de solicitud en vez de construir un reporte en memoria sin limite.

Ya tienen ruta agregada DB en clientes Prisma reales:

- Totales financieros brutos/netos, retornos, pago inicial de credito, advertencias de desglose y auditoria base cuando no hay filtro de categoria.
- Movimientos de caja.
- Inventario/categorias de catalogo.
- Abonos de credito del periodo cuando no hay filtro de categoria.
- Series de ventas/utilidad cuando no hay filtro de categoria.
- Top products cuando no hay filtro de categoria.
- Top clients cuando no hay filtro de categoria.
- Category profits cuando no hay filtro de categoria.

Este tope no sustituye la arquitectura final. El siguiente paso estructural es reemplazar el calculo restante en memoria por agregados DB para prorrateos con filtro de categoria.
