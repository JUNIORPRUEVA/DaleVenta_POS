# Runbook — creación de `guardian-uat` en EasyPanel

Operaciones numeradas y autorizables. **Ninguna se ha ejecutado.**
Cada paso indica verificación y rollback. Los valores de credenciales nunca
aparecen aquí: se leen de `C:\Users\pc\.guardian-uat\` o se pegan en el panel.

Estado de partida verificado (2026-10-26, solo lectura): Docker 28.3.0, Swarm
1 nodo, **0 servicios `guardian-*`**, 0 secretos, 5,1 GB RAM libres, 61 GB disco.

---

## OPS-1 · Proyecto y red (sin secretos)

1. EasyPanel → **Create Project** → nombre `guardian-uat`.
2. Verificar que aparece la red overlay `easypanel-guardian-uat`.

```bash
docker network ls --format '{{.Name}}' | grep guardian-uat
docker service ls --format '{{.Name}}' | grep -c guardian-uat   # debe ser 0
```

**Rollback:** eliminar el proyecto vacío desde el panel.

## OPS-2 · Base de datos aislada

1. Servicio **Postgres 16** (imagen `pgvector/pgvector:pg16`) dentro de `guardian-uat`.
2. Nombre del servicio: `db`. **Ningún puerto publicado** (dejar "Ports" vacío).
3. Volumen: `guardian-uat_db-data` (el panel lo crea).
4. Variables del servicio DB: `POSTGRES_DB=guardian_uat`, `POSTGRES_USER`, `POSTGRES_PASSWORD` (generadas por el panel o por ti; nunca por mí en claro).

```bash
docker service inspect guardian-uat_db --format '{{json .Endpoint.Ports}}'   # debe ser [] o no existir
docker service ps guardian-uat_db --format '{{.CurrentState}}'
```

**Rollback:** eliminar el servicio y su volumen (no hay datos productivos).

## OPS-3 · Esquema y usuario de solo lectura

Con la imagen del backend UAT (OPS-4) o un contenedor temporal de `node:24-alpine`
montando la imagen ya construida:

```bash
# dentro del contenedor de la app UAT, con DATABASE_URL apuntando a guardian-uat_db
npx prisma migrate deploy
```

```sql
-- rol de lectura para GUARDIAN_READER_DATABASE_URL
CREATE ROLE guardian_reader LOGIN PASSWORD '<definido por ti>';
GRANT CONNECT ON DATABASE guardian_uat TO guardian_reader;
GRANT USAGE ON SCHEMA public TO guardian_reader;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO guardian_reader;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON TABLES TO guardian_reader;
```

Verificación: `SELECT count(*) FROM _prisma_migrations;` > 0 y
`SELECT to_regclass('public.guardian_incidents');` no nulo.

**Rollback:** `DROP DATABASE guardian_uat` / recrear el volumen.

## OPS-4 · Servicio API

EasyPanel → servicio `api` dentro de `guardian-uat`:

- Imagen: build del repo UAT, rama `agent/guardian-uat-final` (API ya compila: `npm run build` ✅).
- Puerto interno `4000`, host público `guardian-uat.gcdndd.easypanel.host`.
- Variables: las del perfil `api` (ver `UAT_DEPLOYMENT_PLAN.md` §4) leídas de
  `C:\Users\pc\.guardian-uat\fullpos-backend.env` + `DATABASE_URL` de OPS-2.
- `GUARDIAN_ENABLED=true` **solo aquí**.

Verificación (sin enviar nada):

```bash
curl -s -o /dev/null -w '%{http_code}\n' https://guardian-uat.gcdndd.easypanel.host/guardian/webhooks/whatsapp \
  # esperado 403 (verify token ausente) -> el controlador existe
```

**Rollback:** `docker service update --replicas=0 guardian-uat_api`.

## OPS-5 · Workers y watchdog

1. Servicio `workers`: comando del worker, variables perfil `workers`, mismas IA/WhatsApp.
2. Servicio `watchdog`: comando `guardian:watchdog`, variables perfil `watchdog`
   (`GUARDIAN_WATCHDOG_DATABASE_URL` con el rol de lectura, `GUARDIAN_WATCHDOG_WEBHOOK_URL` al receptor).
3. Servicio `receiver`: `guardian-watchdog-receiver.js`, host `guardian-uat-watchdog.gcdndd.easypanel.host`.

Verificación:

```sql
SELECT worker_name, last_seen_at FROM guardian_worker_heartbeats ORDER BY last_seen_at DESC;
```

**Rollback:** `--replicas=0` en ambos; sin borrar datos.

## OPS-6 · Webhook en Meta

1. Callback URL: `https://guardian-uat.gcdndd.easypanel.host/guardian/webhooks/whatsapp`
2. Verify token: el de `GUARDIAN_WA_VERIFY_TOKEN` (ya generado en tu archivo privado).
3. Suscribir el campo `messages` (estados de entrega).

Verificación: `GET` con `hub.challenge=prueba` debe devolver `prueba` (200).

## OPS-7 · Panel Appyra UAT

Proyecto `appyra-uat` con `GUARDIAN_API_BASE_URL` (URL interna del API UAT) y
`GUARDIAN_PLATFORM_TOKEN` (mismo valor). Verificación:
`GET /api/admin/guardian/health` con sesión administrativa.

## OPS-8 · Respaldo y rollback global

```bash
# respaldo tras migrar
docker exec guardian-uat_db.1.<id> sh -c 'pg_dump -U "$POSTGRES_USER" "$POSTGRES_DB"' > /root/guardian-uat-backup.sql
```

Rollback total: eliminar proyectos `guardian-uat` y `appyra-uat` (servicios, red,
volumen). Ninguna base ni servicio productivo se modifica en ningún paso.

## OPS-9 · Pruebas previas al primer mensaje

1. `guardian-uat-config-check.ts --profile=api|workers|watchdog|appyra` → todo `ok`.
2. `guardian-ai-model-probe.ts --confirm` (autorización aparte).
3. Ingesta sintética vía `POST /guardian/ingest` con un evento de prueba →
   debe crear incidente, diagnóstico y (con destinatarios) alerta.
4. Confirmar en el expediente: `QUEUED → ACCEPTED → DELIVERED` con evidencia por capa.

## OPS-10 · Desactivación inmediata

```bash
docker service update --env-add GUARDIAN_ENABLED=false guardian-uat_api
docker service update --replicas=0 guardian-uat_workers guardian-uat_watchdog
```
