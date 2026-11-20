# 19 — Publicación y rollback

> Procedimiento histórico, no ejecutable como aprobación del candidato integrado.
> Ver [20-integracion-ia-planes-20261119.md](20-integracion-ia-planes-20261119.md).
> Se conserva `RUN_MIGRATIONS=false`; las migraciones compartidas requieren
> revisión y autorización manual separadas. No hacer seed/backfill ni desplegar
> por seguir los comandos históricos de este archivo.

Fecha: 2026-11-19
Estado: procedimiento preparado. **No se ha desplegado nada.**

Commit candidato local: **`7f1abb04`** (rama `agent/planes-de-pago-impl-20261116`),
compuesto por dos commits locales sin publicar:

```
7f1abb04 chore(license): candado de autorizacion en el backfill y plan de publicacion
21f61aeb feat(license): sistema de planes, ordenes, comprobantes y migracion segura
```

Base: `origin/production-main` = `e6e7e8fc`. **No hay commits de producción que
falten**: el commit candidato es esa base + el sistema de planes (0 archivos
borrados respecto a producción).

## 1. Respaldo previo (obligatorio)

```bash
# Base de datos
pg_dump "$DATABASE_URL" --format=custom \
  --file=/backups/fullpos-pre-planes-$(date +%Y%m%d-%H%M).dump

# Comprobación de que el respaldo se puede leer
pg_restore --list <archivo>.dump | head -20
```

Sin este archivo no se continúa.

## 2. Identificar la imagen productiva actual

Antes de tocar nada, guardar **qué** está corriendo hoy:

```bash
# En el VPS (Docker Swarm / EasyPanel)
docker service ls
docker service inspect --format '{{.Spec.TaskTemplate.ContainerSpec.Image}}' <servicio-api>
docker service ps <servicio-api> --format '{{.Name}} {{.CurrentState}} {{.Image}}'
```

Anotar el **tag o digest exacto**. Ese valor es el rollback.

Si el panel de EasyPanel permite ver el historial de despliegues, capturarlo
también: es la vía más rápida de volver.

## 3. Imagen candidata

```bash
git log -1 --format='%H %s'          # debe ser el commit preparado
docker build -t fullpos-api:planes-20261119 .
docker image inspect fullpos-api:planes-20261119 --format '{{.Id}}'
```

El `Dockerfile` de `apps/api` ya:

- copia `scripts/` (incluye los scripts de licencias),
- copia `prisma/` (migraciones),
- ejecuta `prisma generate` en el build,
- arranca con `scripts/start-prod.sh`, que aplica `prisma migrate deploy`.

> **Requisito que no está en Git:** `apps/fulltech_app/.env` es un *asset*
> declarado en `pubspec.yaml` y está en `.gitignore`. Sin él, `flutter test` y
> `flutter build` fallan con «No file or variants found for asset: .env». En la
> máquina de build hay que crearlo (o copiarlo del servidor de forma segura).
> Para producción, pasar además `--dart-define=API_BASE_URL=...` explícito.

## 4. Orden exacto en el servidor

1. **Respaldo** (paso 1).
2. Anotar imagen actual (paso 2).
3. Subir la imagen candidata.
4. Definir variables (sección 5) **antes** de arrancar.
5. Desplegar. Al arrancar, `start-prod.sh` aplica las migraciones pendientes.
6. `npm run license:preflight` con el entorno del servidor (o ejecutarlo dentro
   del contenedor) → **0 errores**.
7. `npm run license:seed` → 4 planes (idempotente).
8. `npm run license:backfill` **solo simulación**: genera el informe de las
   empresas ACTIVO sin plan para revisión. **No se aplica.**
9. `npm run license:check` → sin hallazgos de cobertura.
10. Humo (sección 6).

> Las 6 migraciones son aditivas. La API anterior sigue funcionando con el
> esquema nuevo: si hay que volver atrás, no hay que revertir la base.

## 5. Variables de entorno requeridas

Sin revelar valores aquí. La lista completa está en
`docs/planes-de-pago/18-preparacion-deploy.md` §5. Las imprescindibles:

| Variable | Comprobación |
| --- | --- |
| `DATABASE_URL` | conexión correcta |
| `JWT_SECRET` | distinto de `change-me`, ≥ 32 caracteres |
| `LICENSE_BANK_ACCOUNT` | ≥ 4 dígitos de la cuenta real |
| `LICENSE_EVIDENCE_DIR` | ruta escribible y persistente |
| `LICENSE_ADMIN_SECRET` | clave del puente administrativo (si se usa el CRM) |
| `CRM_LICENSE_MANAGEMENT_ENABLED` | `false` hasta que el CRM esté listo |
| `LICENSE_WA_DRY_RUN` | `true` (no enviar avisos reales todavía) |
| `RUN_MIGRATIONS` | `true` |
| `RUN_SEED` | **vacío** |

`LICENSE_WA_DRY_RUN=true` cumple la restricción de esta fase: **ningún mensaje
de WhatsApp real**.

## 6. Humo posterior

En este orden, y parando en el primer fallo:

1. `GET /health` → 200.
2. `GET /license` **sin** token → 401 (la ruta existe y está protegida).
3. `GET /license/plans` **sin** token → 401 (en la versión anterior daba 404).
4. `GET /license/payment-instructions` sin token → 401.
5. Login real de una empresa **ACTIVA** de producción (con autorización):
   - entra,
   - abre **Planes** y ve su estado y su uso,
   - **no** cambia su plan ni su vencimiento.
6. Revisar que `/license` devuelve el mismo `licenseStatus` y la misma
   `licenseExpiresAt` que había antes del despliegue para esa empresa.
7. Revisar los logs: ni `P2002` ni `P2025` repetidos.

## 7. Criterios para detener el despliegue

Detener y hacer rollback si ocurre **cualquiera** de estos:

- `/health` no responde 200 en 3 minutos.
- `/license` deja de responder 401 y pasa a 404 o 500 (el problema histórico).
- Cualquier empresa activa recibe `LICENSE_BLOCKED`, `EXPIRED` o pierde una
  función que ya usaba.
- Aparecen errores 500 en `/license/orders`, `/license/plans` o `/license/orders/quote`.
- El preflight da **cualquier** error (no aviso).
- El log muestra migraciones fallidas o `MIGRATION_STRICT` activo con fallo.

## 8. Rollback

```bash
# Volver a la imagen anotada en el paso 2
docker service update --image <tag-anterior> <servicio-api>
# o, si Swarm conserva la versión anterior:
docker service rollback <servicio-api>
```

Qué pasa con la base de datos: **nada que deshacer**. Las migraciones son
aditivas (columnas y tablas nuevas). La API anterior ignora las tablas de planes
y sigue usando `companies`, que no cambia de forma.

Las empresas solo cambian si se ejecutó el backfill, y **no se ejecuta** en este
despliegue. Si alguna vez se aplicara, el rollback exacto está en
`18-preparacion-deploy.md` §4.

## 9. Separación del POS Local

El sistema de licencias de **FullPOS Cloud** vive en `apps/api/src/license` y en
las tablas:

```
license_plans
license_payment_orders
license_payment_evidences
license_company_overrides
company_license_audit_logs
license_notification_jobs
license_reminder_logs
```

Todas dentro de la base de FullPOS Cloud. **No** comparte tablas ni claves con el
sistema de licencias del POS Local (`FULLTECHPOS_BAKEND_LICENCIA`), que es otro
proyecto y otra base. Este despliegue no toca el POS Local.
