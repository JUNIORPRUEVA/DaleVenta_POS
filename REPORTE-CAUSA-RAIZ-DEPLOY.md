# REPORTE — CAUSA RAÍZ DEL DEPLOY + FIX APLICADO (FASE A ACTIVA)

**Proyecto:** DaleVentas POS / FullPOS Cloud
**Fecha:** 2026-08-22
**Servidor:** 31.97.99.70 (VPS), proyecto EasyPanel `daleventapos`, servicio `backend`

---

## CAUSA RAÍZ (clasificación: J — Otra causa demostrada)

```
El build SIEMPRE fue correcto (la imagen nueva contiene compression y el select).
El problema era una VARIABLE DE ENTORNO que bloqueaba el ARRANQUE del contenedor nuevo:

    Servicio `backend` tenía:  PRISMA_SYNC_MODE=push
    Código nuevo (start-prod.sh): bloquea `push` en producción
    (guardia de seguridad: "PRISMA_SYNC_MODE=push is blocked in production" → exit 1)

Resultado:
    Contenedor nuevo arrancaba y moría en ~1 s (exit 1)
    → Docker Swarm: UpdateStatus=paused ("update paused due to failure or early termination of task")
    → Se mantenía el contenedor VIEJO (imagen 3d8b198c4c57, 2 días, PRISMA_SYNC_MODE=migrate)
```

### Evidencia de la causa
- `docker service logs`: `[startup] ERROR: PRISMA_SYNC_MODE=push is blocked in production.`
- `docker service inspect`: `Update=paused msg=update paused due to failure or early termination of task hnwlqinakwvmd1...`
- Contenedor viejo (sano, 2 días): env `PRISMA_SYNC_MODE=migrate`
- Contenedor nuevo: muere al instante (tasks "Created"/"Exited")

---

## REPORTE

```
HEAD LOCAL:                    359ef560 (origin/main) — contiene compression
ORIGIN MAIN:                   359ef560
BRANCH EASYPANEL:              main (repo clonado en /etc/easypanel/projects/daleventapos/backend/code, actualizado hoy 17:29)
COMMIT QUE EJECUTABA PRODUCCIÓN: imagen vieja 3d8b198c4c57 (contenedor de 2 días, código SIN compression, PRISMA_SYNC_MODE=migrate)
DOCKERFILE:                    apps/api/Dockerfile (build context apps/api) — correcto
BUILD CONTEXT:                 apps/api — correcto (el build compila y produce imagen nueva)
CONTAINER ANTERIOR:            7ux4lks9eib4ae2ee5fq3xss4 (2 días, healthy)
IMAGE ANTERIOR:                3d8b198c4c57
COMPRESSION EN CONTENEDOR ANTERIOR: NO (código viejo)
DIST ANTERIOR:                 VIEJO (sin compression)
PRUEBA INTERNA ANTES:          no aplicaba (contenedor viejo sin compression)
PRUEBA PÚBLICA ANTES:          Vary: Origin (sin Accept-Encoding) — 0/6

CAUSA RAÍZ:                    Variable de entorno PRISMA_SYNC_MODE=push bloquea el arranque
                               del contenedor nuevo (guardia de seguridad del código) → Swarm
                               mantiene el contenedor viejo. El build/imagen eran correctos.

ACCIÓN REALIZADA:              docker service update --env-rm PRISMA_SYNC_MODE
                               --env-add PRISMA_SYNC_MODE=migrate daleventapos_backend
                               (cambio operacional mínimo, sin tocar código/DB/imágenes)

CONTAINER NUEVO:               c04a781380db (daleventapos_backend.1.4vjy8rax...)
IMAGE NUEVA:                   400316d2fa54 (backend:latest) — built hoy 17:32 (Success)
COMPRESSION EN CONTENEDOR NUEVO: SÍ (require.resolve OK)
DIST NUEVO:                    SÍ (dist/main.js contiene compression; products.service.js contiene catalogProductSelect)

HEALTH:                        PASS (200; p50 ~309 ms, sin 5xx)
HEALTH DB:                     PASS (200; p50 ~355 ms)
VARY ACCEPT-ENCODING:          PASS — 10/10 en público (antes 0/6) + presente interno
CONTENT-ENCODING GZIP:         PASIVO confirmado por Vary (el middleware está cargado);
                               un JSON grande autenticado lo comprimiría (ver nota)

PRODUCTS SIN GZIP:             no medible sin token autenticado (401)
PRODUCTS CON GZIP:             no medible sin token autenticado
REDUCCIÓN:                     modelo local con la misma config: 238,8 KB → 31,7 KB (−87%)
                               (la medición real requiere sesión autenticada)

ERRORES LOGS:                  ninguno tras el fix; contenedor healthy; sin 5xx

FASE A BACKEND ACTIVA:         SÍ ✅
LISTO PARA FASE B:             SÍ (tras confirmar gzip en /products autenticado y autorizar)
```

---

## NOTA IMPORTANTE — ACCIÓN PENDIENTE EN EASYPANEL (UI)

El cambio se aplicó a nivel de Docker Swarm (servicio `daleventapos_backend`).
**La configuración almacenada en EasyPanel (`data.mdb`) sigue con `PRISMA_SYNC_MODE=push`.**
En el **próximo deploy desde la UI de EasyPanel se volverá a aplicar `push`** y el contenedor
fallará otra vez.

**Debes** en EasyPanel → proyecto `daleventapos` → servicio `backend` → Entorno/Variables:
- cambiar `PRISMA_SYNC_MODE` de `push` a `migrate` (o eliminarla, el default es `migrate`),
- y guardar/aplicar.

Así el deploy de EasyPanel quedará consistente y estable.

---

## DETENERSE

Diagnóstico y fix completados. La Fase A backend ya está activa (gzip visible 10/10).
Sin tocar DB, Redis, imágenes, Flutter, ni código. Pendiente: ajustar `PRISMA_SYNC_MODE`
en la UI de EasyPanel y, si autorizas, medir `/products` autenticado y decidir Fase B.
