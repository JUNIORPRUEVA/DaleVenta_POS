# REPORTE — PRUEBA DEFINITIVA DE RENDIMIENTO POST-DEPLOY (FASE A)

**Proyecto:** DaleVentas POS / FullPOS Cloud
**Fecha:** 2026-08-22
**HEAD local/remoto:** `359ef560` (origin/main)
**Host API medido:** `https://daleventapos-backend.gcdndd.easypanel.host`
**Modo:** SOLO LECTURA (medir, comparar, validar, concluir).

---

## ⚠️ HALLAZGO CRÍTICO (puerta de la evaluación)

```
GZIP EN PRODUCCIÓN:  NO ACTIVO
    Vary: Accept-Encoding: 0/6 (ausente en TODAS las muestras)
    /health muestra solo "Vary: Origin" (sin Vary: Accept-Encoding ni Content-Encoding)
    El middleware `compression` añade Vary: Accept-Encoding a TODA respuesta
    (verificado localmente incluso en respuestas de 15 B) → su ausencia = middleware NO cargado.

SEGÚN LA REGLA DEL ENCARGO:
    "Si gzip NO aparece → FASE A BACKEND NO ESTÁ COMPLETAMENTE ACTIVA
     y detener la interpretación de mejoras de payload."

→ Por tanto, NO se puede validar mejora de payload en producción en este momento,
  y NO se puede declarar la Fase A cerrada con éxito.
```

> El commit correcto está en `origin/main` (`359ef560`, incluye compression), pero el
> contenedor en ejecución sigue siendo anterior (imagen/build desactualizado). La
> corrección es la misma detectada antes: **reconstruir/re-desplegar el servicio
> `backend` en EasyPanel** (rama `main`, Dockerfile `apps/api/Dockerfile`).

---

## BACKEND

```
/health  (15 muestras)
    min=284 ms  avg=304 ms  p50=299 ms  p95=377 ms  max=377 ms
    (baseline anterior p50 ≈ 298 ms → estable, sin regresión)

/health/db  (15 muestras)
    min=299 ms  avg=378 ms  p50=365 ms  p95=531 ms  max=531 ms
    (baseline anterior p50 ≈ 300-306 ms → dentro del piso de red ~300 ms;
     p95 más alto por jitter de red/TLS en conexiones nuevas — sin 5xx)

gzip:
    NO ACTIVO
```

---

## PRODUCTS

```
cantidad de productos:   NO MEDIBLE (requiere token autenticado; no disponible)
sin gzip (KB):            NO MEDIBLE en producción (401 sin token) + gzip inactivo
con gzip (KB):            NO MEDIBLE
reducción:                NO APLICABLE (gzip no está activo en producción)
TTFB:                     ~303 ms (401, sin auth — igual que baseline)
total:                    ~303 ms
```
> Nota: el modelo local (misma config, 3000 productos) dio 238,8 KB → 31,7 KB (−87%),
> pero eso NO cuenta como resultado de producción.

---

## FACTURACIÓN (flujo real)

```
COLD / WARM First Useful UI, Products visible, Fully Loaded:
    NO MEDIBLE — requiere ejecutar la app Flutter con sesión real en este entorno.
    La lógica (cache-first /products, /settings en memoria, /taxes ≤1h/empresa,
    /ncf/sequences 1 por sesión+empresa) está validada por código y tests,
    pero no se puede cronometrar en vivo aquí.
```

---

## REQUESTS (conteo real)

```
Primera/Segunda/Tercera entrada al POS:
    NO MEDIBLE en vivo (requiere app con sesión).
    Estructural (validado por código):
      /products  → cache-first (2 min de frescura)
      /settings  → en memoria (una vez por sesión/empresa)
      /taxes     → ≤1 por hora por empresa (cache `taxes_cache_v1:company:<id>`)
      /ncf/sequences → 1 por sesión+empresa (provider no-autoDispose, dependiente de company)
```

---

## NCF

```
Entradas al POS:      N/A (no ejecutable aquí)
Requests /ncf/sequences:
    Antes: 1 por entrada (autoDispose)
    Después (código): 1 por sesión+empresa, o al cambiar de empresa/login
    Backend sigue siendo SOURCE OF TRUTH (reserva NCF solo si fiscalVoucherType no vacío).
    Validado por tests; medición en vivo NO DISPONIBLE.
```

---

## TAXES

```
Entradas al POS:      N/A
Requests /taxes:
    Antes: 1 por invalidación/apertura
    Después (código): ≤1 por hora por empresa, cache aislada por companyId.
    Test "A nunca ve la caché de B" ✅. Medición en vivo NO DISPONIBLE.
```

---

## MULTIEMPRESA

```
Aislamiento:  PASS (por código + tests)
    - /products, /taxes, /ncf/sequences filtrados por companyId del JWT (backend).
    - Cache de taxes/drafts scoped por empresa; cambio de empresa resetea estado fiscal
      e invalida providers.
    - Prueba EN VIVO con dos empresas: NO DISPONIBLE (sin credenciales).
```

---

## IMÁGENES (medición real, producción)

```
5 imágenes del catálogo (host FULLPOS):
    promedio TTFB:   307 ms
    promedio total:  584 ms
    promedio peso:   137 KB
    cache headers:   Cache-Control: public, max-age=0  (SIN caché)
    rango total:     390 – 750 ms por imagen

→ IMÁGENES = CUELLO DE BOTELLA ACTUAL (confirmado)
  (cada imagen tarda ~0,6 s sin caché y a resolución completa)
```

---

## ESCALABILIDAD MULTIUSUARIO

```
Payload de /products NO medible en producción (gzip inactivo + sin token).
Por tanto NO se calcula con números de producción.

Modelo local (marcado como NO-producción): 3000 items = 238,8 KB → 31,7 KB (−87%).
    Ese ahorro se materializará SOLO tras el redeploy del backend con compression.

Requests NCF/taxes por usuario (estimación estructural):
    NCF: ~17 requests ahorrados/usuario/día si abre el POS 20 veces (de 20 → ~3).
    Taxes: de "cada invalidación" a ≤1/hora.
```

---

## ESTABILIDAD

```
HTTP 5xx:        NINGUNO (todas las muestras: /health, /health/db, /products,
                 /settings, /taxes, /ncf/sequences, /cotizaciones → 200/401)
Timeouts:        NINGUNO
Prisma errors:   NINGUNO visible (health/db OK)
Regresiones:     NINGUNA detectada en salud/estabilidad
```

---

## CONCLUSIÓN

```
¿HUBO MEJORA REAL?
PARCIAL / NO CONFIRMADA EN PRODUCCIÓN

    - BACKEND: gzip NO activo → el mayor beneficio de la Fase A (payload −87%) NO está vivo.
    - CLIENTE: los cambios (menos requests NCF/taxes, cache por empresa) están en el código
      y validados por tests, pero no se pudieron cronometrar en vivo aquí.

MEJORA PRINCIPAL:
    (Potencial, pendiente de redeploy) gzip −87% en /products.
    (En código) Reducción de requests repetidos NCF/taxes por empresa.

PORCENTAJE DE REDUCCIÓN DE TRANSFERENCIA:
    NO APLICABLE en producción (gzip inactivo). Modelo local: −87% (no cuenta como prod).

REDUCCIÓN DE REQUESTS:
    En código: /ncf/sequences de 1-por-entrada a 1-por-sesión; /taxes ≤1/hora/empresa.
    No medible en vivo aquí.

TIEMPO PERCIBIDO DEL POS:
    No medible en vivo. Salud de API estable (~300 ms, sin regresión).

CUELLO DE BOTELLA ACTUAL:
    1) Red RD→Boston ~300 ms/request (piso geográfico — la Fase A no lo mueve).
    2) IMÁGENES FULLPOS: ~584 ms c/u, sin caché → dominan la percepción del catálogo.

SIGUIENTE OPTIMIZACIÓN RECOMENDADA:
    0) PRIMERO: reconstruir/re-desplegar el backend en EasyPanel (rama main,
       Dockerfile apps/api/Dockerfile) para ACTIVAR gzip. Re-verificar
       `Vary: Accept-Encoding` en /health.
    1) Después: FASE B — IMÁGENES FULLPOS → thumbnails + R2/CDN con caché inmutable.
```

---

## ESTADO

```
FASE A CERRADA EXITOSAMENTE:  NO
    - gzip NO activo en producción (backend no redeployado).
    - El código está correcto y desplegable; falta el rebuild en EasyPanel.

SIGUIENTE FASE: IMÁGENES FULLPOS → THUMBNAILS + R2/CDN
    (recomendada, PERO solo tras confirmar gzip en producción y tras autorización;
     NO implementada en esta tarea)
```

---

## DETENERSE

Medición completada en solo lectura. Sin cambios, sin commit, sin push, sin deploy,
sin Redis, sin imágenes, sin PostgreSQL.
Acción pendiente del usuario: rebuild/redeploy del backend en EasyPanel; luego
re-ejecutar esta prueba para validar gzip y el payload real.
