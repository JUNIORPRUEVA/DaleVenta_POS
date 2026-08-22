# REPORTE — VALIDACIÓN POST-DEPLOY FASE A (RENDIMIENTO)

**Proyecto:** DaleVentas POS / FullPOS Cloud
**Fecha:** 2026-08-22
**Modo:** SOLO LECTURA (medición y comparación; sin modificaciones)
**Host medido:** `https://daleventapos-backend.gcdndd.easypanel.host`

---

## 1. ESTADO DEL DEPLOY

```
Commit local / remoto (HEAD = origin/main): 5b01611a "FSDFSDFSD"
Rama: main
¿El código de Fase A está en HEAD?          SÍ
    - apps/api/src/main.ts            → compression (Vista en git show)
    - apps/api/src/products/products.service.ts → select explícito
    - .../product_tax_options_provider.dart → cache taxes por empresa
    - .../registrar_venta_screen.dart → NCF sin autoDispose
    - tests nuevos y reportes

Health:          /health    200 OK (p50 ~300 ms)
Health DB:       /health/db 200 OK (p50 ~306 ms)

⚠️ HALLAZGO CLAVE: La compresión NO está activa en el backend desplegado.
    - Señal de referencia: el middleware `compression` añade `Vary: Accept-Encoding`
      a TODAS las respuestas (verificado localmente con la misma config, incluso en
      respuestas de 15 B).
    - En producción: `Vary: Accept-Encoding` presente en 0/10 muestras de /health.
    → El backend en ejecución NO incluye el cambio de `main.ts`.
    → El deploy del servicio `backend` NO materializó la compresión (build/imagen
      desactualizada o build no regenerado). Hay que reconstruir/re-desplegar la imagen.
```

---

## 2. COMPRESIÓN (GZIP) — PRODUCCIÓN

```
GZIP EN PRODUCCIÓN:
NO ACTIVO

Content-Encoding en /health o /products:  ausente
Vary: Accept-Encoding:                    0/10 respuestas
Reducción de payload real en prod:        NO materializada (aún se sirve sin comprimir)

Modelo local (misma config, verificado):
    JSON 3000 productos: 238.771 B → 31.653 B  (−87%)
```
> La reducción del 87% está **probada localmente** y el código está en HEAD, pero **no es visible en producción** hasta que el backend se reconstruya con `main.ts`.

---

## 3. PRODUCTS

```
TTFB (/products, sin auth → 401):  ~303 ms  (igual que antes; sin cambio, como se esperaba)
Total:                              ~303 ms
Payload autenticado:                NO MEDIBLE sin credenciales (no se exponen tokens)

Contrato compatible (campos ProductModel):  SÍ (validado por tests)
    id, nombre, codigo, precio, stock, categoria, imagen, imageKey,
    imageUpdatedAt, taxTreatment, taxRate, taxPriceMode, companyId
Multiempresa:  OK por tests (products.service.tenant.spec) —
               VALIDACIÓN REAL NO DISPONIBLE (sin dos empresas/sesiones autorizadas)
```
> La optimización `select` es transparente al contrato: se validó que el JSON sigue incluyendo todos los campos que `ProductModel` consume.

---

## 4. TAXES

```
Requests antes (por invalidación/apertura):  1 por evento
Requests después (por hora/empresa):         ≤ 1/h (cache-first + SWR), clave `taxes_cache_v1:company:<companyId>`

Cache por empresa:  OK (test "A nunca ve la caché de B" ✅)
Estado en producción:  el cambio es del CLIENTE (Flutter); está en el código commiteado.
    VALIDACIÓN DE CLIENTE EN VIVO NO DISPONIBLE (requiere app con sesión).
```
> La asignación del impuesto de una venta se recalcula SIEMPRE en el servidor (`calculatorService.calculate`), por lo que la caché de taxes solo afecta al pre-relleno UX, no al resultado transaccional.

---

## 5. NCF

```
Requests antes (por entrada al POS):  1 por entrada (autoDispose)
Requests después:                     1 por sesión+empresa (o al cambiar de empresa/login)

Asignación server-side del próximo NCF:  OK (incremento atómico transaccional en el backend — sin cambios)
Aislamiento por empresa:                 OK por tests + código (provider depende de authStateProvider.companyId)
Estado en producción:                    cambio de CLIENTE; en código commiteado.
    VALIDACIÓN DE CLIENTE EN VIVO NO DISPONIBLE (requiere app con sesión).
```

---

## 6. POS (CARGA DE FACTURACIÓN)

```
First Useful UI cold:   NO MEDIBLE (requiere app/dispositivo con sesión real)
First Useful UI warm:   NO MEDIBLE
Fully Loaded:           NO MEDIBLE
Requests por entrada:   NO MEDIBLE en vivo.
    Validado estructuralmente: /products cache-first (2 min), /settings en memoria,
    /taxes ≤1/h/empresa, /ncf/sequences 1 por sesión+empresa.
```
> Medir la experiencia real del POS requiere ejecutar la app con una sesión válida; no está disponible en este entorno de auditoría. No se inventan valores.

---

## 7. ESCALABILIDAD (impacto multiusuario estimado con datos reales del modelo)

Modelo basado en la medición local verificada (payload real de producción no medible sin auth):

```
/products (3000 items): 238,8 KB sin gzip → 31,7 KB con gzip (−87%)

Escenario (una sincronización de catálogo por usuario):
    10 usuarios:   antes ≈ 2,4 MB   →  después ≈ 0,3 MB
    100 usuarios:  antes ≈ 23,9 MB  →  después ≈ 3,2 MB
    500 usuarios:  antes ≈ 119,4 MB →  después ≈ 15,8 MB

Ahorro de requests NCF (si un cajero abre el POS 20 veces/día):
    antes ≈ 20 requests/día  →  después ≈ 2–3 requests/día (≈ 17 ahorrados/usuario/día)
```
> Estos ahorros se materializan UNA VEZ que: (a) el backend se reconstruya con compresión y (b) se publique la app con la caché de cliente. Hoy, en producción, el payload aún se sirve sin comprimir.

---

## 8. ERRORES / REGRESIONES

```
Errores en muestras de producción:  NINGUNO
    /health, /health/db → 200 (todas las muestras)
    /products, /settings, /taxes, /ncf/sequences → 401 esperado (sin token) — sin 5xx
Concurrencia ligera (10 GET /health simultáneos): 10/10 OK, 288–438 ms
Regresiones detectadas: NINGUNA en estabilidad/salud
Logs de producción: NO ACCESIBLES desde este entorno (EasyPanel) — no se pudo auditar 500/502/503/504
CPU/RAM backend y DB: NO ACCESIBLES (requiere consola EasyPanel) — sin evidencia de picos
```

---

## 9. CONCLUSIÓN

```
¿HUBO MEJORA REAL?
PARCIAL — Y CON UN PROBLEMA DE DEPLOY EN EL BACKEND

PRINCIPAL MEJORA (en código, aún NO viva en prod):
    gzip −87% payload de /products (verificado localmente, código en HEAD)
    Reducción de requests: /ncf/sequences y /taxes (cambios de cliente, en código)

CUELLO DE BOTELLA ACTUAL (confirmado):
    1) Red RD→Boston ≈ 300 ms/request (piso geográfico, sin cambio)
    2) Imágenes FULLPOS: ~137 KB de media, ~0,5–0,6 s cada una, Cache-Control: max-age=0
       (sin caché, host externo, RTT ~118 ms) → SIGUEN SIENDO EL CUELLO DOMINANTE

⚠️ ACCIÓN REQUERIDA ANTES DE SEGUIR:
    El backend desplegado NO tiene la compresión activa (Vary: Accept-Encoding ausente 0/10).
    → Reconstruir/re-desplegar el servicio `backend` de EasyPanel con la imagen que
      incluya `main.ts` (npm run build + redeploy). Luego repetir la verificación:
      `curl -I -H "Accept-Encoding: gzip" https://.../products` debe mostrar
      `Vary: Accept-Encoding` y `Content-Encoding: gzip` en respuestas grandes.

SIGUIENTE FASE RECOMENDADA (tras confirmar el redeploy del backend):
    FASE B — IMÁGENES FULLPOS → R2 + thumbnails + cache inmutable/CDN
    Evidencia de revalidación:
        5 imágenes FULLPOS: media 137 KB, media 564 ms, sin cabeceras de cache
        (max-age=0) → por catálogo visual con decenas de imágenes esto domina la
        percepción de lentitud.

Validaciones marcadas como NO DISPONIBLES (requieren credenciales/dispositivo con sesión):
    - payload autenticado de /products
    - prueba real A vs B multiempresa en vivo
    - medición en vivo de requests de taxes/NCF y carga del POS
    - logs de producción y métricas CPU/RAM de EasyPanel
```

---

## DETENERSE

Validación completada en solo lectura. **Sin modificaciones, sin deploy, sin Redis, sin tocar imágenes.**
Pendiente de tu autorización: reconstruir el backend (para materializar gzip) y, después, decidir Fase B (imágenes).
