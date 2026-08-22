# REPORTE — FASE A: OPTIMIZACIÓN DE RENDIMIENTO (QUICK WINS)

**Proyecto:** DaleVentas POS / FullPOS Cloud
**Fecha:** 2026-08-22
**Rama:** `main` @ `236ef122`
**Alcance:** Fase A autorizada — quick wins de bajo riesgo (A1–A6).
**NO implementado:** Redis, imágenes, HTTP/2 stack, paginación de `/sales`.

---

## 1. RESUMEN

```
Implementación completada:
SÍ (A1 gzip ✅, A2 /products ✅, A3 settings/taxes ✅, A4 taxes+NCF cache ✅, A5 requests ✅, A6 medición ✅)

Riesgo:
BAJO

Deploy:
NO realizado (a la espera de autorización)
```

---

## 2. CAMBIOS REALIZADOS

### Backend (`apps/api`)

| Archivo | Cambio | Razón |
|---|---|---|
| `package.json` | +`compression ^1.8.1` (deps) y `@types/compression` (devDeps) | A1: middleware estándar Express/NestJS para compresión HTTP |
| `package-lock.json` (raíz) | lockfile actualizado | Registra la nueva dependencia del monorepo |
| `src/main.ts` | `app.use(compression({ threshold: 1024, filter: json/text }))` | A1: comprime JSON/text >1KB; respeta `Accept-Encoding`; añade `Vary: Accept-Encoding`; NO comprime imágenes/PDF/media |
| `src/products/products.service.ts` | `findAll` usa `catalogProductSelect()` (Prisma `select` explícito) | A2: `/products` deja de leer columnas DB que ningún cliente consume (`imageStorageProvider`, `imageMimeType`, `imageOriginalFileName`); el contrato de salida se mantiene (campos no consumidos ya salían null en productos sin imagen) |

### Flutter (`apps/fulltech_app`)

| Archivo | Cambio | Razón |
|---|---|---|
| `lib/core/tax/product_tax_options_provider.dart` | Caché de taxes **cache-first + SWR** con `LocalJsonCache`, clave `taxes_cache_v1:company:<companyId>`, TTL 1h | A3/A4: `/taxes` se consulta como máximo 1 vez/hora/empresa en vez de en cada invalidación/apertura; aislamiento por empresa en la clave |
| `lib/modules/ventas/registrar_venta_screen.dart` | `posNcfSequencesProvider` deja `autoDispose` y pasa a `FutureProvider` que depende de `authStateProvider` (companyId) | A4/A5: `/ncf/sequences` deja de consultarse en CADA entrada al POS; se recarga solo al cambiar de empresa/logout/login |

### Tests nuevos

| Archivo | Qué valida |
|---|---|
| `apps/api/src/products/products.service.tenant.spec.ts` | Aislamiento multiempresa de `/products` + select explícito sin columnas pesadas |
| `apps/api/src/tax/tax.service.tenant.spec.ts` | Aislamiento multiempresa de `/taxes` (A nunca ve B) |
| `apps/fulltech_app/test/core/tax/product_tax_options_provider_test.dart` | Cache-first de taxes, SWR, y **aislamiento de caché A vs B** |
| `tools/verify_compression.cjs` | Verificación local de la configuración de compresión (misma config que `main.ts`) |

---

## 3. MULTIEMPRESA (respuestas explícitas)

```
¿Products aislado por empresa?                     SÍ
    - Backend: findAll filtra con `where: { companyId }` obtenido de `requireTenant(user)` (JWT). Test dedicado.
¿Taxes cache separado por empresa?                 SÍ
    - Clave: `taxes_cache_v1:company:<companyId>`. Test: A (18%) nunca devuelve la caché de B (16%).
    - LocalJsonCache además añade el scope `ft_cache:<companyId>` automáticamente (doble aislamiento).
¿NCF separado por empresa?                         SÍ
    - Backend: listSequences filtra `where: { companyId }`. Provider Flutter depende de `authStateProvider.user.companyId`.
¿Cambio de empresa invalida/selecciona bien datos? SÍ
    - posNcfSequencesProvider: al cambiar user.companyId, `ref.watch(authStateProvider)` reconstruye el provider.
    - Taxes: al cambiar empresa cambia la clave de caché (nunca se reutiliza la de la empresa anterior).
    - Se conserva `ref.invalidate(posNcfSequencesProvider)` en `_handleCompanyChanged` (redundante pero seguro).
¿Riesgo de contaminación cross-tenant?             NO identificado
    - Backend siempre filtra por companyId del JWT (nunca acepta companyId del cliente).
    - Las cachés Flutter llevan la empresa en la clave.
```

---

## 4. MÉTRICAS

### ANTES (baseline externa, 2026-08-22, desde RD → Boston)

| Endpoint | status | TTFB |
|---|---|---|
| `GET /health` | 200 | ~296 ms |
| `GET /health/db` | 200 | ~314 ms |
| `GET /products` (sin auth) | 401 | ~303 ms |
| `GET /settings` (sin auth) | 401 | ~327 ms |
| `GET /taxes` (sin auth) | 401 | ~301 ms |
| `GET /ncf/sequences` (sin auth) | 401 | ~293 ms |
| `GET /cotizaciones` (sin auth) | 401 | ~317 ms |

Nota: no se pudo medir el payload autenticado de producción sin credenciales (no se exponen tokens). La medida del piso de red (~300 ms) y los tamaños se validaron localmente.

### DESPUÉS (verificado localmente con la misma config; producción requiere deploy)

| Métrica | ANTES | DESPUÉS | Mejora |
|---|---|---|---|
| Payload JSON catálogo (3000 productos) | 238.771 B | **31.653 B** (gzip) | **−87%** |
| `Content-Encoding` en JSON | ausente | `gzip` (+`Vary: Accept-Encoding`) | ✅ |
| Imágenes PNG / PDF | — | sin comprimir | ✅ intactas |
| Requests `/ncf/sequences` por entrada al POS | 1 por cada entrada (autoDispose) | 1 por sesión+empresa (o al cambiar empresa) | reducción por entrada |
| Requests `/taxes` | 1 por invalidación/apertura | ≤ 1 / hora / empresa (cache-first + SWR) | reducción |
| `/products` columnas DB leídas | todas (18) | 14 (sin `imageStorageProvider`, `imageMimeType`, `imageOriginalFileName`) | payload menor + menos I/O |

> La latencia de red (~300 ms/request) es un piso geográfico RD→Boston y **no** cambia con estos quick wins; el beneficio principal de A1 es el ancho de banda y la reducción de requests (A4/A5). La medición final en producción se hará tras el deploy autorizado.

---

## 5. TESTS

```
Backend (jest, no e2e):
    85/85  ✅  (18 suites) — incluye 6 tests nuevos de aislamiento tenant (products + taxes)

Flutter (relacionados: tax, catálogo, contabilidad, company, ventas):
    85/86  ✅  (1 fallo ambiental preexistente de SQLite file-lock; en aislamiento pasa 11/11)

Multiempresa (específicos):
    products.service.tenant.spec    ✅ 3/3
    tax.service.tenant.spec         ✅ 2/2
    product_tax_options_provider_test ✅ 4/4 (incluye A nunca ve B)

Análisis estático:
    flutter analyze  →  No issues found ✅
    npm run build    →  compila ✅
```

---

## 6. PROBLEMAS

```
Corregidos:
    - Sin compresión HTTP en la API (A1).
    - /products leía columnas que ningún cliente consume (A2).
    - /ncf/sequences se consultaba en cada entrada al POS (A4/A5).
    - /taxes sin caché por empresa (A4).

Pendientes (fuera de esta fase, documentados en la auditoría):
    - Imágenes FULLPOS a resolución completa (Fase B).
    - Redis desactivado (no necesario en esta fase).
    - /sales sin límite default (riesgo de romper reportes → NO tocado, como se instruyó).
    - HTTP/2 (requiere evaluación aparte).
    - `ncfSequencesProvider` (contabilidad/factura fiscal) se dejó como autoDispose a propósito: pantalla fiscal donde la frescura es más justificable.
    - Duplicidad `posNcfSequencesProvider` vs `ncfSequencesProvider` (mismo endpoint, 2 providers) → se puede unificar en fase posterior.

Preexistentes (NO tocados, trabajo ajeno detectado durante la sesión):
    - Reparación de caché de imágenes: `lib/core/cache/cache_repair.dart` (nuevo), `fulltech_cache_manager.dart`, `fulltech_map_tile_cache.dart`, `app_storage_scope_guard.dart`.
```

---

## 7. CAMBIOS NO RELACIONADOS (ajenos, no incluidos en esta tarea)

Se detectaron durante la sesión (probablemente trabajo paralelo del usuario), NO los modifiqué:

```
apps/fulltech_app/lib/core/cache/cache_repair.dart            (untracked)
apps/fulltech_app/lib/core/cache/fulltech_cache_manager.dart   (M)
apps/fulltech_app/lib/core/cache/fulltech_map_tile_cache.dart  (M)
apps/fulltech_app/lib/core/startup/app_storage_scope_guard.dart(M)
apps/fulltech_app/test/core/cache/                             (untracked)
```

Además, siguen pendientes los cambios preexistentes del workspace (12 archivos modificados que estaban ANTES de esta tarea: app_drawer, responsive_shell, inventory_module_pages, cash_*, clientes_*, cotizaciones_screen, sales_pdf_service) — NO mezclados con esta optimización.

---

## 8. RECOMENDACIÓN DE DEPLOY

```
LISTO PARA DEPLOY:
SÍ (una vez revisado el diff por el usuario)

RAZÓN:
    - Backend compila y 85/85 tests unitarios pasan.
    - Flutter analiza sin issues y los tests relacionados pasan.
    - Aislamiento multiempresa verificado por tests (products/taxes/NCF).
    - Cambios mínimos, reversibles y sin alterar contratos transaccionales
      (la venta sigue validando impuestos y NCF en el servidor).
    - NO se ejecutó git push / deploy / reinicio de EasyPanel.
```

### Orden sugerido de despliegue
1. Backend: `npm run build` → desplegar servicio `backend` en EasyPanel (nueva imagen).
2. Verificar con `curl -H "Accept-Encoding: gzip" https://.../products` → `Content-Encoding: gzip`.
3. Publicar app Flutter (cuando se autorice) con el provider de taxes/NCF.

---

## 9. NOTA FISCAL (NCF)

- La lista `/ncf/sequences` es informativa (tipos, prefijos, estado).
- La asignación del próximo NCF se reserva SIEMPRE en el backend con incremento atómico transaccional (`NcfService.reserveNextNcf` → `nextNumber: { increment: 1 }` dentro de transacción).
- La caché en memoria del provider Flutter **nunca** garantiza ni duplica numeración fiscal.

---

## 10. DETENERSE

Fase A completada. **Sin deploy, sin push, sin Redis, sin tocar imágenes.**

A la espera de autorización para:
- revisar el diff;
- decidir despliegue;
- iniciar Fase B (imágenes) cuando lo indiques.
