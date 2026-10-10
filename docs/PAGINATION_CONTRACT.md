# Contrato de paginación y compatibilidad legacy

Estado: **vigente** (hotfix paginación / large dataset).

## 1. Envelope estándar

Toda lista paginada del backend responde:

```json
{
  "items": [ ... ],
  "page": 1,
  "limit": 50,
  "total": 103,
  "hasMore": true,
  "nextPage": 2
}
```

Semántica (definida en `apps/api/src/common/pagination/page-pagination.ts`):

| Campo | Significado |
| --- | --- |
| `items` | **Solo** los registros de la página actual. Nunca el dataset completo. |
| `page` | Página solicitada (>= 1). |
| `limit` | Tamaño de página aplicado. |
| `total` | Total **después de filtros/search y antes de paginar**. Puede ser `null` si el endpoint no lo calcula: nunca se inventa un número. |
| `hasMore` | `true` si existen más registros alcanzables. |
| `nextPage` | Página siguiente, o `null` si no hay más. |

Límites:

- `DEFAULT_PAGE_LIMIT = 50`
- `MAX_PAGE_LIMIT = 200`
- `take = limit + 1` (se pide un registro extra para saber si hay más sin contar).

## 2. Regla de oro para consumidores

1. `items` **no** es el dataset completo. No se debe buscar, contar ni sumar
   sobre `items` asumiendo totalidad.
2. Para operar sobre todo el conjunto: recorrer `nextPage` hasta `hasMore == false`.
3. Un total financiero se calcula en el servidor (agregación) o acumulando
   **todas** las páginas: nunca sobre una página.
4. Una página parcial **no** se guarda como snapshot completo de caché.

## 3. LEGACY_CLIENT_COMPAT_MODE

```
LEGACY_CLIENT_COMPAT_MODE = ACTIVO (temporal)
```

Motivo: los clientes ya instalados (Windows/PWA anteriores al contrato paginado)
llamaban a estos endpoints **sin** `page`/`limit` y consumían la respuesta como
dataset completo. Al paginar por defecto (50) empezaron a recibir datos
truncados en silencio: incidente **"faltan productos"**
(PRODUCTS: 103 reales, 50 visibles).

Comportamiento:

- Si la petición **no** incluye `page`, `limit` ni `pageSize` → se devuelve el
  conjunto completo, con `hasMore=false` y `total = número de filas`.
- Si la petición incluye cualquiera de esos parámetros → paginación normal.

Tope de seguridad del modo legacy: `LEGACY_UNPAGINATED_LIMIT = 5000`.
No es un límite funcional: evita una respuesta ilimitada. Es configurable por
endpoint con `legacyLimit`.

### Endpoints afectados

| Endpoint | Servicio | Notas |
| --- | --- | --- |
| `GET /products` | `products.service.ts` | + `total` con `count()` en modo paginado |
| `GET /sales` | `sales.service.ts` | devuelve array plano en modo legacy (compat. de forma) |
| `GET /sales/invoices` | `sales.service.ts` | idem |
| `GET /clients` | `clients.service.ts` | ya devolvía `total`/`totalPages` |
| `GET /cash/movements/history` | `cash.service.ts` | histórico completo |
| `GET /cash/sessions/closed` | `cash.service.ts` | turnos cerrados completos |
| `GET /cash/sessions/:id` | `cash.service.ts` | movimientos completos del turno |
| `GET /purchases/{orders,invoices,suppliers}` | `purchases.service.ts` | listados completos |
| `GET /cotizaciones` | `cotizaciones.service.ts` | respeta `take` explícito del cliente |
| `GET /contabilidad/closes` | `contabilidad.service.ts` | listado completo |
| `GET /contabilidad/payables/payments` | `contabilidad.service.ts` | listado completo |

### REMOVAL_PLAN

```
REMOVAL_PLAN =
  1. Todos los clientes en campo deben enviar `page`/`limit` (loadMore real o
     snapshot completo paginado).
  2. Sustituir el modo legacy por paginación obligatoria
     (`normalizePagePagination` deja de aceptar la ausencia de parámetros).
  3. Eliminar `LEGACY_UNPAGINATED_LIMIT`.
Condición de retiro: cuando el parque instalado (Windows + PWA) esté por encima
de la versión que introduce el loadMore. No hay fecha fija todavía.
```

## 4. Deuda pendiente (no cubierta por este hotfix)

- **UI con loadMore real** (scroll/infinite) en: catálogo, ventas, clientes,
  caja, compras, cotizaciones, contabilidad. Mitigado en su mayoría por el modo
  legacy, pero es la solución objetivo (evita payloads grandes).
- **Clientes**: la lista pide `page=1&pageSize=100` explícitos, por lo que el
  modo legacy no aplica: con 225 clientes siguen viéndose 100.
- **Cotizaciones**: el cliente envía `take=80` explícito → sigue acotado a 80.
- **Búsqueda remota en UI**: el catálogo y el buscador de venta filtran en local
  sobre el dataset ya completo (LOCAL_FULL_DATASET: correcto, no es bug, pero no
  escala a catálogos muy grandes).
- **Topes duros sin paginación**: payroll (120/500/500/200), users (500),
  warranty (200), work-scheduling (500/100/500), warehouses/transfers (100).
- **Totales en UI**: "Ventas netas"/"Resumen" del TPV y gráficas de "Mis Ventas"
  siguen sumando lo cargado.
