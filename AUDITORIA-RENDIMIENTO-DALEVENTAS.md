# 🔍 AUDITORÍA INTEGRAL DE RENDIMIENTO — DALEVENTAS POS / FULLPOS CLOUD

**Fecha:** 2026-08-22
**Modo:** SOLO LECTURA (inspección, medición, diagnóstico, propuesta — sin implementar nada)
**Rama/commit auditado:** `main` @ `236ef122` (worktree con cambios sin commit previos existentes, intactos)

---

## 1. RESUMEN EJECUTIVO

| | |
|---|---|
| **Principal cuello de botella** | **Geografía de red + imágenes:** cada request HTTPS cuesta ~300 ms desde RD (Santo Domingo) al servidor en Boston, EE. UU. (RTT ~91 ms + TLS + proxy). Las imágenes del catálogo viven en un host FULLPOS **distinto** y tardan ~0.5–1.2 s cada una. |
| **Segundo cuello de botella** | **Payloads grandes sin compresión:** `/products` devuelve el catálogo completo (sin paginación ni `select`, con campos duplicados) y la API no tiene gzip/br. |
| **Tercer cuello de botella** | **Requests secuenciales en cadena** (`/settings` → `/taxes`, y múltiples fetches individuales) que multiplican el costo fijo de ~300 ms por request. |

**¿Redis necesario ahora?** → **NO AHORA** (MÁS ADELANTE, y solo si aplica).

**Razón:**
- Redis ya está integrado y **desactivado** (`REDIS_ENABLED=false`); su único uso actual es cotizaciones (poco crítico para el POS).
- El cuello de botella **no es PostgreSQL** (una query `SELECT 1` no añade nada medible: `/health` ≈ `/health/db` ≈ 300 ms), así que cachear en Redis no elimina el costo de red de ~300 ms por request.
- Las mayores ganancias vienen de: **mover/servir imágenes cerca del usuario + thumbnails + compresión HTTP + menos requests (paralelismo y caché)**. Redis solo sería un acelerador del backend para consultas repetitivas costosas (p. ej. reports), NO la solución al problema percibido.

---

## 2. ARQUITECTURA ACTUAL (REAL)

```
Usuario (Rep. Dominicana, RTT ~91 ms al servidor)
   │
   ▼
Flutter (Dio 5.4, Riverpod 2.5)  ── Android / Windows / Web(PWA)
   │  HTTP/1.1 en móvil/desktop · HTTP/2 en web (navegador)
   ▼
EasyPanel — Traefik (proxy, terminación TLS, ALPN h2)
   │  daleventapos-backend.gcdndd.easypanel.host  → 31.97.99.70 (Boston, Hostinger)
   ▼
NestJS 11 (Express) + Prisma 5.22
   │  SIN compresión HTTP · logging [req] con duración
   ▼
PostgreSQL 16 (source of truth)   ◄── DATABASE_URL
   │
   └── (catálogo lee de la DB local; PRODUCTS_SOURCE=FULLPOS es IGNORADO por código → LOCAL)
```

**Hosts implicados (medidos):**

| Host | IP | Ubicación (GeoIP) | RTT ping |
|---|---|---|---|
| `daleventapos-backend...easypanel.host` (API) | 31.97.99.70 | Boston, EE. UU. (Hostinger) | ~91 ms |
| `fullpos-backend-fullpos-backend.onqyr1.easypanel.host` (imágenes) | 187.77.196.196 | Boston, EE. UU. (Hostinger) | ~92–153 ms |

> ⚠️ **Hallazgo estructural:** el backend de la API y el host de imágenes FULLPOS están ambos en Boston, EE. UU.; los usuarios están en República Dominicana. La distancia domina la latencia.

**Stack de cache en Flutter (ya existente):**
- SQLite (`sqflite`, `OfflineStore.cache_entries`) para snapshots JSON del catálogo por empresa — cache-first + SWR.
- `flutter_cache_manager` (`FulltechImageCacheManager`, disco 30 días, 1200 objetos) para imágenes.
- `LocalJsonCache` para settings (TTL 14 días).
- Realtime socket.io (`catalog_realtime_service`) + timer de sync cada 2 min.
- Dedup in-flight de `/products` por empresa en `CatalogRepository`.

---

## 3. CARGA DE FACTURACIÓN (flujo real)

La pantalla real de cobro es **`RegistrarVentaScreen`** (`/ventas/nueva`); el grid visual es **`CatalogTab`** (`/catalogo`). `catalogo_screen.dart` es código muerto.

```
T+0 ms        Usuario entra a Facturación
T+~10 ms      initState: socket.io (sin HTTP) + Timer 2 min
T+~50 ms      postFrame → _loadProducts(silent:true)
                ├─ getCachedProducts()      → lee SQLite (cache-first) → UI inmediata
                └─ repo.fetchProducts()
                    ├─ getFreshCachedProducts()  → si ≤2 min → NO hace HTTP
                    └─ GET /products             (dedup in-flight por companyId)
build()       productTaxUiConfigProvider
                ├─ await companySettingsProvider → GET /settings   ─┐ SECUENCIAL
                └─ (si taxEnabled) GET /taxes                       ─┘
              (si tax && ncf) posNcfSequencesProvider → GET /ncf/sequences  (autoDispose)
Imágenes      GridView.builder (lazy) → CachedNetworkImage
                ├─ /media/object?...&w=320&h=320 (R2, con thumb) o
                └─ URL directa FULLPOS (SIN thumbnail)  ← el problema
Tras venta    POST /sales → luego /cash/state, /cash/summary, /cash/movements
```

**Time to First Useful UI:** en la práctica es rápido en frío (caché SQLite de 7 días), **salvo primera ejecución** (sin caché): entonces depende de `GET /products` + imágenes.

**Time to Fully Loaded:** dominado por **imágenes** (ver §9).

---

## 4. REQUESTS DETECTADOS (endpoints consumidos al abrir Facturación)

| Endpoint | Método | Cuándo | Frecuencia | Caché | Payload aprox. |
|---|---|---|---|---|---|
| `/products` | GET | al abrir (o caché 2 min) | 1 por sesión de 2 min / realtime | SQLite 7 días + fresh 2 min | TODO el catálogo (~28 campos/producto) |
| `/settings` | GET | al abrir | 1 (FutureProvider raíz) | SQLite 14 días | ~3–5 queries, incl. `appConfig.upsert` |
| `/taxes` | GET | al abrir **si** taxEnabled | 1 (secuencial tras settings) | ninguna | pocos registros |
| `/ncf/sequences` | GET | al abrir **si** tax && ncf | **cada vez** (autoDispose) | ❌ ninguna | secuencias NCF |
| `/media/object?key=...&w=320&h=320` | GET | por producto visible (lazy) + prefetch ≤24 | muchos | 1 año immutable | thumbs 320px |
| URL imagen FULLPOS | GET | por producto con imagen FULLPOS (lazy) | muchos | caché disco 30 d | **resolución completa** |
| `/clients?search=` | GET | al buscar cliente | bajo demanda | paginado (100/pág) | 1 página |
| `/cash/state` `/cash/summary` `/cash/movements` | GET | **tras** guardar venta | 1 vez/venta | — | 2 y 4 queries |
| `/sales` POST | POST | al guardar venta | 1 | cola offline | — |

**NO se disparan al abrir:** `/auth/me` (ya en splash), `/cash/state` (solo tras venta), backup (agendado).

**Duplicados reales:**
- `/products` NO se duplica (dedup in-flight + ventana 2 min) ✔
- `/ncf/sequences` SÍ se re-descarga en cada entrada al POS ❌
- Doble fuente de estado en memoria en `RegistrarVentaScreen` (`_products` propio + `listenManual(catalogControllerProvider)`) — mismo HTTP, doble lógica de reconciliación.

---

## 5. LATENCIA (mediciones reales, 2026-08-22, desde Santo Domingo, RD)

### 5.1 Desglose de red a `daleventapos-backend...` (curl, GET /health)

| Etapa | Cold | Warm |
|---|---|---|
| DNS | 8–16 ms | 8–16 ms |
| TCP connect | 124 ms | 110 ms |
| TLS (appconnect) | 428 ms | 198–209 ms |
| TTFB | 518 ms | 292–309 ms |
| Total | ~518 ms | ~300 ms |

### 5.2 Estadística TTFB `/health` (10 muestras, conexiones nuevas)

```
min=290ms  p50=298ms  avg=297ms  max=307ms
```

### 5.3 Aislamiento DB vs red

| Endpoint | TTFB | Observación |
|---|---|---|
| `GET /health` (sin DB) | ~297 ms | Referencia pura de red+proxy |
| `GET /health/db` (SELECT 1) | ~300 ms | **La DB añade ~0 ms** → PostgreSQL NO es el cuello de botella |
| `GET /products` (401 sin auth) | ~297 ms | Mismo piso de red |

### 5.4 HTTP/1.1 secuencial vs HTTP/2 multiplexado (6 requests /health)

```
HTTP/1.1 secuencial (como en móvil/desktop):  6 req → 1882 ms  (~314 ms c/u)
HTTP/2   concurrente (una conexión):          6 req →  383 ms  (~64 ms c/u)   → 5× más rápido
```

> El servidor soporta HTTP/2 (ALPN `h2`). **Flutter móvil/desktop usa HTTP/1.1** (Dart `HttpClient`), por lo que cada request secuencial paga ~300 ms de coste fijo. En web (navegador, HTTP/2) el costo por request baja, pero el catálogo sigue pagando el mismo RTT por cada imagen.

### 5.5 Cold vs Warm (detectado)

- **API:** cold ~518 ms vs warm ~300 ms (diferencia = handshake TLS inicial). No hay cold-start severo de contenedor.
- **Imágenes FULLPOS:** cold ~1.17 s vs warm ~0.5–0.7 s (DNS 312 ms + TCP 256 ms + TLS 788 ms en frío).

**Conclusión de red:** el piso de latencia de CUALQUIER request es ~300 ms por la geografía (RD→Boston) + TLS. Esto NO es culpa de PostgreSQL ni de Flutter.

---

## 6. PAYLOADS (estimación basada en código; requiere validación con token real)

| Endpoint | Consultas SQL | Filas | Payload estimado sin comprimir | Con gzip (estimado) |
|---|---|---|---|---|
| `GET /products` | 1 (`findMany`, sin `take`/`select`) | TODO el catálogo | ~800 B/producto → **~0.8 MB por 1.000 productos** | ~0.2 MB |
| `GET /sales` (sin `?limit`) | 1 + includes anidados | TODO el rango | ventas × items completo | — |
| `GET /reports/sales-overview` | 5 (3× `sale.findMany` con includes) | TODO el rango | el mayor payload | — |
| `GET /cash/summary` | 4 (filas completas) | turno completo | medio-alto | — |
| `GET /clients?search=` | 2 (paginado ✔) | 1 página | bajo | — |

**Detalle `/products` por objeto (~28 campos):** cada producto incluye `codigo` **y** `code` **y** `sku` **y** `barcode` (mismo valor), `stock` **y** `cantidadDisponible`, `categoria` **y** `categoriaNombre`, más URLs de imagen (~110+ caracteres en el host FULLPOS). El campo `imagen` apunta a un host externo. **No se comprime** en la API (no hay gzip/br en Express) y los headers fuerzan `Cache-Control: no-store`.

---

## 7. POSTGRESQL

- **Versión:** PostgreSQL 16 (imagen `postgres:16-alpine`), DB `daleventa_pos`.
- **Queries lentas:** no se detectaron en el path crítico; `/health/db` (SELECT 1) añade ~0 ms.
- **N+1:** NO hay N+1 en el path crítico (`/products` = 1 query, `/clients` = 2, `/cash/state` = 2 en paralelo). El N+1 potencial existe en **código muerto** (`CatalogProductsService`, modo FULLPOS/DIRECT).
- **Sequential scans:** el buscador de clientes usa `contains ... mode: insensitive` → `ILIKE '%...%'` **no indexable** (media). Sin índices faltantes críticos en el path POS.
- **Índices relevantes ya existentes:** `Product[companyId]`, `[companyId,nombre]` (cubre ORDER BY nombre); `Client[companyId]`, `[companyId,isDeleted]`, `[companyId,phoneNormalized]`; `Sale[companyId,saleDate]`, `[companyId,isDeleted]`; `CashboxDaily[companyId,businessDate]` unique; `CashSession[companyId,status]`, `[openedByUserId,status]`; `CashMovement[sessionId]`, `[companyId,createdAt]`; `AppConfig[companyId]` unique.
- **Índices faltantes (opcional):** `[companyId, userId, isDeleted, saleDate]` en `Sale` para resúmenes por vendedor; no hay tabla `Category` para productos (categoría es `String` desnormalizada).
- **Pool:** un solo `PrismaClient` (defaults de Prisma, pool ≈ nCPU×2+1). El pool secundario `max:3` a la DB FULLPOS es **código muerto**.
- **Sin telemetría:** no hay `pg_stat_statements`, `log_min_duration_statement`, `statement_timeout` ni `EXPLAIN` en producción.

---

## 8. FLUTTER / RIVERPOD

- **Requests duplicados:** `/products` NO (dedup por empresa + ventana 2 min) ✔. `/ncf/sequences` SÍ (autoDispose, sin caché) ❌.
- **Invalidaciones:** `catalogControllerProvider`/`companySettingsProvider`/`tax` son providers raíz (no autoDispose) → persisten ✔. Solo `posNcfSequencesProvider` se refetch por entrada.
- **autoDispose:** solo `posNcfSequencesProvider` (innecesario: NCF es casi estático).
- **Rebuilds:** `RegistrarVentaScreen` mantiene doble fuente (`_products` + `listenManual(catalogControllerProvider)`); el grid de `CatalogTab` se re-renderiza con cada cambio de estado (aunque no cambien items, `copyWith` igual genera rebuilds del watch).
- **Caché:** excelente para catálogo (cache-first + SWR en SQLite) y settings (14 días). Falta caché para NCF y `taxes`.
- **Parsing:** `ProductModel.fromJson` para todo el catálogo en cada refresco (map de ~800 B × N) — costo menor frente a la red, pero evitable con versionado.
- **Secuencialidades:** `/settings` → `/taxes` son **secuenciales** (await encadenado); el catálogo y NCF van concurrentes. Realtime `product.event` dispara `forceRemote` (throttle 20 s) que **bypasea** la ventana de 2 min.

---

## 9. IMÁGENES (el segundo cuello de botella real)

- **Almacenamiento:** dos fuentes — (a) R2/objetos vía `/media/object` (con thumbnails `?w=320&h=320`, `Cache-Control` 1 año immutable ✔) y (b) **URLs absolutas del host FULLPOS** (`fullpos-backend...easypanel.host/uploads/products/*.jpg`).
- **El problema:** las imágenes FULLPOS **no se redimensionan** (`buildProductThumbnailUrl` solo aplica `w/h` a endpoints `/media/*`; las URLs externas se mantienen tal cual) → se descargan a **resolución completa** y desde **otro host** (también en Boston).
- **Mediciones imagen FULLPOS (3 muestras):** TTFB ~330–360 ms, total ~**504–708 ms** (warm) y **~1.17 s** (cold: DNS 312 ms + TCP 256 ms + TLS 788 ms) para 31–176 KB.
- **Cache Flutter:** `flutter_cache_manager` (disco 30 días, 1200 objetos) ✔; prefetch de ≤24 thumbs solo en desktop (no web).
- **Lazy loading:** todos los grids usan `GridView.builder`/`ListView.builder` ✔.
- **Conclusión:** si el catálogo tiene muchas imágenes FULLPOS a resolución completa, la pantalla queda dominada por la descarga de imágenes (~0.5–1.2 s c/u). **Migrar a R2/thumbnails eliminaría casi todo este costo.**

---

## 10. SERVIDOR (EasyPanel)

- **API:** `daleventapos-backend...easypanel.host` → 31.97.99.70 (Boston, Hostinger). Sin señales de OOM/cold-start severo (latencia estable p50=298 ms).
- **Imágenes FULLPOS:** 187.77.196.196 (Boston). Backend separado.
- **Logs revisados** (`server.log`, `startdev.out.log`): **8568 peticiones** de `/products/image-proxy` (versión anterior del app), promedio 156–171 ms, máximos **2222–2659 ms**. Evidencia de que el proxy de imágenes era una fuente de latencia en despliegues previos.
- **Proxy:** Traefik (EasyPanel), terminación TLS, ALPN `h2` (soporta HTTP/2). **Sin CDN** para la API.
- **PWA:** nginx con `gzip` para estáticos (la API no hereda esa compresión).

---

## 11. REDIS

| Pregunta | Respuesta |
|---|---|
| ¿Instalar/activar Redis ahora? | **No ahora** (ya está integrado, `REDIS_ENABLED=false`) |
| ¿Por qué? | PostgreSQL no es el cuello de botella medido. Redis no reduce el costo de red de ~300 ms/request. Su valor real es cachear consultas **repetitivas y costosas** (reports agregados), no el POS. |
| Qué cachear (si se activa) | Cotizaciones (ya implementado), `reports/sales-overview`, `settings`/`fiscal-settings` (lecturas casi estáticas), catálogo versionado (ETag/last-modified). |
| Qué NO cachear | Ventas, pagos, movimientos, caja, gastos, stock/precios transaccionales. |
| TTL | 60 s (default actual) o TTL corto + invalidación por evento. |
| Invalidación | Ya existe `delByPattern` para cotizaciones; habría que añadir invalidación por `product.event`/`sale.event` para los nuevos caches. |
| Beneficio esperado | Bajo para el POS; medio-alto para reportes/dashboard. |

---

## 12. CACHE LOCAL (Flutter)

| Pregunta | Respuesta |
|---|---|
| ¿Implementar cache local? | **Ya existe y está bien diseñada.** Mejorar, no crear. |
| Tecnología actual | SQLite (`OfflineStore`/`LocalJsonCache`) + `flutter_cache_manager` + `SharedPreferences` (web). |
| Datos candidatos | Catálogo (ya), settings (ya, 14 días), **NCF sequences (falta)**, taxes (falta), clientes recientes (parcial). |
| Estrategia actual | **Cache-first + stale-while-revalidate** para catálogo (muestra SQLite y refresca en background). Correcta. |
| Mejora propuesta | **Versionado de catálogo** (ETag / `updated_after` / versión incremental) para evitar descargar el catálogo completo cuando no cambió. |

---

## 13. TOP 10 OPTIMIZACIONES (ordenadas por prioridad impacto/riesgo/esfuerzo)

| # | Optimización | Impacto | Riesgo | Esfuerzo |
|---|---|---|---|---|
| 1 | **Servir imágenes FULLPOS a través del propio backend o migrarlas a R2 con thumbnails** (redirigir URLs absolutas a `/media/...&w=320`) | **Alto** (elimina ~0.5–1.2 s/imagen) | Medio | Medio |
| 2 | **Compresión HTTP (gzip/br) en la API** para `/products`, `/sales`, `/reports` | **Alto** (payload -70–80%) | Bajo | Bajo |
| 3 | **HTTP/2/paralelismo:** reducir requests secuenciales (paralelizar `/settings` y `/taxes`; evitar `/ncf/sequences` repetido) | **Alto** (a ~64 ms/req con multiplexación) | Bajo | Bajo |
| 4 | **`select` explícito + recorte de campos duplicados en `/products`** (eliminar `code/sku/barcode/cantidadDisponible` duplicados) | Medio-Alto | Bajo | Bajo |
| 5 | **ETag / `updated_after` (versionado de catálogo)** para evitar re-descarga completa | **Alto** (en la práctica elimina la mayoría de GET /products) | Medio | Medio |
| 6 | **Caché de `/ncf/sequences` y `/taxes`** (quitar autoDispose o cachear) | Medio | Bajo | Bajo |
| 7 | **Paginación o caché en `/reports/sales-overview`** (agregar en SQL, no traer filas) | Medio | Medio | Medio |
| 8 | **Límite por defecto en `/sales`** (`take` 1–200 si no llega `?limit`) | Medio | Bajo | Bajo |
| 9 | **Índice `[companyId,userId,isDeleted,saleDate]`** en `Sale` | Medio | Bajo | Bajo |
| 10 | **Eliminar código muerto** (`CatalogProductsService` FULLPOS/DIRECT, `catalogo_screen.dart`) y unificar doble fuente del catálogo en el POS | Bajo (mantenimiento) | Bajo | Bajo |

> **Quick wins sin arquitectura:** #2 (gzip), #3 (paralelismo), #4 (select), #6 (caché NCF), #8 (límite sales). Todos de bajo riesgo y bajo esfuerzo.

---

## 14. PLAN POR FASES (propuesto — NO ejecutado)

```
FASE A  Quick wins (días): compresión HTTP · paralelizar /settings→/taxes · caché NCF/taxes ·
        select explícito en /products · límite default en /sales
FASE B  Backend/PostgreSQL: agregar agregación SQL en reports/cash · índice [companyId,userId,...] ·
        pg_stat_statements + statement_timeout · ETag/versionado de catálogo
FASE C  Flutter/cache local: versionado incremental del catálogo · unificar fuente del catálogo en POS ·
        cache de NCF/taxes · prefetch de imágenes web
FASE D  Imágenes (el gran ganador): servir imágenes FULLPOS vía backend/R2 con thumbnails ·
        redirigir URLs externas a /media con ?w=320 · migrar a CDN/Cloudflare si aplica
FASE E  Redis (SOLO si tras Fases A–D sigue habiendo consultas repetitivas costosas):
        activar REDIS_ENABLED para cotizaciones + reports con invalidación por evento
FASE F  Medición posterior (repetir §5) para validar baseline
```

---

## 15. RESULTADO ESPERADO (objetivos técnicamente defendibles)

| Operación | ACTUAL (medido) | OBJETIVO razonable |
|---|---|---|
| Latencia base por request (API) | ~300 ms | ~90–110 ms (RTT puro, vía HTTP/2 + keep-alive) |
| `GET /products` transferido | ~0.8 MB sin comprimir (1.000 prod.) | ~0.2 MB (gzip) + 304/ETag si no cambió |
| Imagen FULLPOS (por imagen) | ~0.5–1.2 s | ~100–200 ms (thumbnails R2/API, misma región) |
| Abrir Facturación usable (con caché) | ya rápido (cache-first) | mantener; eliminar refetch innecesario de NCF |
| Carga de reportes/dashboard | filas completas + JS | agregado SQL + caché 60 s |

---

## 16. CONSISTENCIA DEL POS (garantías que toda propuesta debe respetar)

- **Stock, ventas, pagos, caja, gastos, precios** deben seguir viniendo de PostgreSQL (source of truth). Nada de esto debe depender de cache potencialmente stale.
- Solo datos **de catálogo/información** (productos, categorías, settings, taxes, NCF) son candidatos a cache con invalidación por evento.
- Cualquier propuesta de Redis debe cumplir: **PostgreSQL = source of truth; Redis = acelerador opcional; caída de Redis no pierde ventas/caja/inventario.**

---

## 17. EVIDENCIA DE MEDICIÓN (resumen de datos crudos)

| Medición | Valor |
|---|---|
| Ping API | 91 ms (min 90, max 92) |
| Ping host FULLPOS | 92–153 ms |
| `/health` cold / warm | 518 / 292–309 ms |
| `/health` p50 (10 muestras) | 298 ms |
| `/health/db` | ~300 ms (DB ~0 ms) |
| `/products` sin auth (401) | ~297 ms |
| HTTP/2: 6 concurrentes | 383 ms (64 ms/req) |
| HTTP/1.1: 6 secuenciales | 1882 ms (314 ms/req) |
| Imagen FULLPOS cold | ~1.17 s |
| Imagen FULLPOS warm (3) | 504–708 ms |
| image-proxy (logs previos, n=8568) | avg 156–171 ms, max 2222–2659 ms |

---

## ⛔ DETENIDO — ESPERANDO AUTORIZACIÓN

Esta auditoría es de **solo lectura**. No se modificó código, no se instaló Redis, no se crearon índices, no se ejecutaron migraciones, no se hicieron deploys/pushes, no se reinició ningún servicio, no se cambiaron variables de entorno ni configuración de EasyPanel. Los cambios locales preexistentes del worktree quedaron intactos.

**Siguiente paso:** revisar el diagnóstico y autorizar las fases de implementación.
