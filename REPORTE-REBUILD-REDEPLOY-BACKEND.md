# REPORTE — REBUILD + REDEPLOY CONTROLADO DEL BACKEND

**Proyecto:** DaleVentas POS / FullPOS Cloud
**Fecha:** 2026-08-22
**Objetivo:** conseguir que producción ejecute el backend con compression (gzip) y verificar.

---

## RESUMEN EJECUTIVO

```
¿Se pudo hacer el redeploy desde este entorno?
NO — No hay acceso a la consola/API de EasyPanel, ni CLI, ni token, ni Docker local,
ni pipeline CI→EasyPanel. El redeploy DEBE dispararse desde EasyPanel (pasos en la
sección "ACCIÓN REQUERIDA").

Diagnóstico de la causa (definitivo):
    Producción corre apps/api (NestJS) — confirmado por fingerprint.
    La imagen desplegada es ANTERIOR al commit de compression.
    Solo la rama `main` contiene el commit de compression; el resto de ramas NO.
    No hay señal de que EasyPanel haya reconstruido tras el push.
```

---

## 1. ESTADO GIT

```
COMMIT LOCAL / REMOTO (HEAD = origin/main):  359ef560 "sasasasas" (2026-08-22 13:29 -0400)
Rama:                                         main
main.ts contiene compression:                 SÍ
    - import compression from 'compression'
    - app.use(compression({ threshold: 1024, filter: json/text }))
apps/api/package.json:
    - "compression": "^1.8.1"
    - "@types/compression": "^1.8.1"

Ramas que CONTIENEN el commit de compression (5b01611a):
    SOLO main (local y origin/main)

Ramas que NO lo contienen:
    backup-main-antes-rollback, recovery-before-auth-regression,
    fix-auth-company-bootstrap-resume, fix-tax-product-persistence,
    fullpos-hardening, recovery-stack-37cd136
```
> ⚠️ Si el servicio `backend` de EasyPanel está configurado con una rama distinta a `main`
> (p.ej. una rama de recuperación/backup), jamás recibiría la compresión. Verificar la rama.

---

## 2. QUÉ CONSTRUYE EASYPANEL (deducción)

```
Repositorio:    github.com/JUNIORPRUEVA/DaleVenta_POS.git
Rama probable:  main (verificar en EasyPanel)
Dockerfile:     apps/api/Dockerfile
Build context:  apps/api (el Dockerfile referencia package.json/prisma/src/scripts de apps/api)

apps/api/Dockerfile (verificado):
    builder:
        COPY package*.json ./        → copia package.json (NO hay package-lock.json en apps/api)
        RUN npm install --include=dev
        COPY prisma ./prisma
        RUN npx prisma generate
        COPY tsconfig*.json ./
        COPY src ./src
        RUN npm run build            → genera dist con compression (validado localmente)
    runner:
        COPY --from=builder node_modules, dist, prisma, scripts
        ENV PORT=4000, RUN_MIGRATIONS=true, PRODUCTS_SOURCE=LOCAL, REDIS_ENABLED=false
        HEALTHCHECK wget /health
        CMD sh scripts/start-prod.sh

build context NOTA:
    El Dockerfile requiere build context = apps/api (o raíz con Dockerfile path apps/api/Dockerfile).
    Si el context fuera la raíz, `COPY prisma ./prisma` y `COPY src ./src` fallarían
    (no existen en la raíz) → el backend no arrancaría. Como el backend CORRE,
    el context/Dockerfile actual funciona; solo está desactualizado.
```

---

## 3. COMPRESSION DENTRO DEL CONTENEDOR

```
¿COMPRESSION INSTALADO EN EL CONTENEDOR ACTUAL?
No verificable desde este entorno (sin acceso al contenedor/servidor).

Evidencia indirecta:
    - `apps/api` NO tiene package-lock.json (hoisted en la raíz del monorepo).
    - El Dockerfile copia package.json y ejecuta `npm install` → instalaría compression ^1.8.1.
    - localmente el build resuelve compression (hoisted) y dist/main.js lo incluye.

¿DIST CONTIENE EL CAMBIO?
SÍ — build local con HEAD (npm run build) generó dist/main.js con:
    - import compression from 'compression'
    - app.use(compression(...))
    (fecha dist: 2026-08-22 13:31)
```

---

## 4. CAUSA DEL DEPLOY ANTERIOR (conclusión)

```
Producción NO tiene compression:
    - Vary: Accept-Encoding: AUSENTE en 0/10 (validación previa) y 0/6 (ahora)
    - El middleware `compression` añade Vary a TODA respuesta (verificado local,
      incluso en respuestas de 15 B) → su ausencia = middleware NO cargado.

Causas posibles (por orden de probabilidad):
    1) EasyPanel NO reconstruyó tras el push (auto-deploy desactivado o deploy manual pendiente).
    2) El servicio `backend` está en una rama distinta a `main`
       (solo `main` contiene el commit de compression).
    3) La imagen se construyó pero el contenedor no se reemplazó.

Descartado:
    - Código incorrecto: NO (main.ts + package.json + dist correctos).
    - Dockerfile roto: NO (es sound y el backend corre).
    - Backend equivocado (fulltech-pwa/apps Hono): NO (producción = apps/api NestJS,
      confirmado por X-Powered-By: Express, Etag y rutas).
```

---

## 5. REBUILD

```
REBUILD LOCAL (validación del pipeline):
    OK — `npm run build` con HEAD compila y dist/main.js contiene compression.

REBUILD EASYPANEL:
    PENDIENTE — requiere acción desde la consola de EasyPanel (ver ACCIÓN REQUERIDA).
    Desde este entorno NO hay mecanismo para dispararlo (sin API/CLI/token, sin Docker,
    sin pipeline CI→EasyPanel; solo existe .github/workflows/multi-tenant-security.yml
    y codemagic.yaml para la app Flutter).
```

---

## 6. HEALTH (ESTADO ACTUAL, PRODUCCIÓN — ANTES DEL REDEPLOY)

```
/health        → 200 OK
    min ~290 ms, p50 ~300 ms, p95 ~324 ms, max ~324 ms (15 muestras)
/health/db     → 200 OK
    min ~297 ms, p50 ~306 ms, max ~323 ms (8 muestras)
Concurrencia 10 GET /health → 10/10 OK (288–438 ms)
Sin 5xx en todas las muestras (/health, /health/db, /products, /settings, /taxes, /ncf/sequences → 200/401 esperados)
```

---

## 7. PRUEBA DE COMPRESSION (PRODUCCIÓN, ACTUAL)

```
VARY: ACCEPT-ENCODING:         AUSENTE  (0/10 + 0/6)
CONTENT-ENCODING GZIP:         AUSENTE
/PRODUCTS SIN GZIP (bytes):    no medible sin auth (401 ~116 B)
/PRODUCTS CON GZIP (bytes):    no medible sin auth
REDUCCIÓN REAL:                no aplicable aún en producción
Reducción modelo local (misma config): 238.771 B → 31.653 B (−87%)
```
> El número real de producción solo podrá medirse DESPUÉS del redeploy y con una
> sesión autenticada (o con un endpoint público grande).

---

## 8. ERRORES / LOGS

```
Logs de producción:    no accesibles desde este entorno (EasyPanel).
Señales externas:      ningún 5xx en todas las muestras; salud estable.
```

---

## ACCIÓN REQUERIDA (debe ejecutarla el usuario en EasyPanel)

No tengo acceso a la consola de EasyPanel. Pasos verificados para materializar la Fase A:

1. Abrir **EasyPanel** → proyecto **`daleventapos`** → servicio **`backend`**.
2. En **Settings / Source** verificar:
   - Repositorio: `JUNIORPRUEVA/DaleVenta_POS`
   - **Rama: `main`**  ← clave: solo `main` contiene compression.
   - Build: **Dockerfile** con ruta `apps/api/Dockerfile` (context `apps/api` o raíz con esa ruta).
   - Auto Deploy: opcional (si está activo, un push a `main` debería reconstruir).
3. Pulsar **Deploy / Rebuild / Deploy latest commit** (fuerza rebuild de la imagen).
4. En el build log debe aparecer: `npm install`, `prisma generate`, `npm run build`,
   y al final el arranque `node dist/main.js` (sin `MODULE_NOT_FOUND` ni TypeScript errors).
5. Tras el deploy, ejecutar estas verificaciones (puedo hacerlas yo cuando indiques):

```bash
# Señal de middleware activo (debe aparecer Vary: Accept-Encoding)
curl -sI -H "Accept-Encoding: gzip" https://daleventapos-backend.gcdndd.easypanel.host/health

# Salud
curl -s https://daleventapos-backend.gcdndd.easypanel.host/health
curl -s https://daleventapos-backend.gcdndd.easypanel.host/health/db

# gzip en JSON grande (con sesión autenticada):
curl -s -D - -H "Authorization: Bearer <token>" -H "Accept-Encoding: gzip" \
  https://daleventapos-backend.gcdndd.easypanel.host/products
# → debe mostrar: Content-Encoding: gzip  y  Vary: Accept-Encoding
```

---

## 9. ESTADO FINAL

```
FASE A FINALMENTE ACTIVA EN PRODUCCIÓN:
NO (aún) — el redeploy de EasyPanel está pendiente (requiere acción del usuario).

LISTO PARA FASE B DE IMÁGENES:
SÍ (en cuanto se confirme gzip en producción; las imágenes FULLPOS siguen siendo
el cuello dominante: media ~137 KB, ~0,5–0,6 s, Cache-Control: max-age=0).

Mientras tanto NO se inicia Fase B, NO Redis, NO imágenes, NO más cambios.
```

---

## DETENERSE

Diagnóstico y rebuild local completados. El redeploy de EasyPanel debe ejecutarlo el
usuario (pasos arriba). Al confirmarlo, puedo re-verificar gzip y medir el payload real
de producción.
