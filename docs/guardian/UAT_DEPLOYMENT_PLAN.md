# Plan de despliegue — APPYRA Guardian AI UAT aislado

Estado: **propuesta**, sin ejecutar. Nada de este plan se ha aplicado al VPS.

Base verificada (solo lectura, 2026-10-26): Docker 28.3.0, Swarm 1 nodo,
**0 servicios con nombre `guardian-*`**, 0 secretos, 5,1 GB de RAM libres,
61 GB de disco libres, 2 vCPU. Redes existentes: `easypanel`,
`easypanel-fullpos`, `easypanel-ventas`, `easypanel-daleventapos`,
`easypanel-altomamita`, `easypanel-altomamita-uat` (precedente de proyecto UAT).

---

## 1. Recursos nuevos (nada existente se modifica)

| Recurso | Nombre propuesto | Detalle |
| --- | --- | --- |
| Proyecto EasyPanel | `guardian-uat` | Nuevo; el panel crea su red overlay |
| Red overlay | `easypanel-guardian-uat` | Automática, sin acceso a las redes de producción |
| Servicio API | `guardian-uat_api` | Backend NestJS con `GuardianModule` (ingesta, webhook, plataforma) |
| Servicio workers | `guardian-uat_workers` | `npm run guardian:workers` |
| Servicio watchdog | `guardian-uat_watchdog` | `npm run guardian:watchdog` |
| Servicio receptor | `guardian-uat_receiver` | `scripts/guardian/guardian-watchdog-receiver.js` (canal de respaldo) |
| Base de datos | `guardian-uat_db` | PostgreSQL 16/pgvector, **sin puerto publicado** |
| Volumen | `guardian-uat_db-data` | Persistente, propio |
| Appyra UAT | proyecto `appyra-uat` | Panel administrativo separado (imagen de `agent/appyra-guardian-uat-final`) |

**No se toca**: `ventas_appyra`, `ventas_fullpos_backend`, `fullpos_*`,
`daleventapos_*`, `altomamita_*`, sus BD, sus volúmenes ni sus dominios.

## 2. Red y puertos

- Ningún puerto publicado al host: el acceso es sólo por Traefik (80/443 ya en uso).
- Internos: API `4000`, receptor `4501`, PostgreSQL `5432`.
- El tráfico de Meta entra por `https://guardian-uat.gcdndd.easypanel.host`
  (wildcard `*.gcdndd.easypanel.host`, certificado ya emitido).

## 3. Hosts

| Host | Servicio | Uso |
| --- | --- | --- |
| `guardian-uat.gcdndd.easypanel.host` | `guardian-uat_api` | Webhook de Meta `/guardian/webhooks/whatsapp` + `/guardian/platform/*` (solo red interna, no se publica) |
| `guardian-uat-watchdog.gcdndd.easypanel.host` | `guardian-uat_receiver` | Recibe el JSON del watchdog con `Bearer` |
| `appyra-uat.gcdndd.easypanel.host` | Appyra UAT | Panel Guardian |

> El webhook **debe** apuntar a `/guardian/webhooks/whatsapp` del backend
> Guardian, nunca a una ruta administrativa de Appyra.

## 4. Variables por servicio (solo nombres)

| Servicio | Variables |
| --- | --- |
| `guardian-uat_api` | `DATABASE_URL`; `GUARDIAN_ENABLED`, `GUARDIAN_INGEST_ENABLED`, `GUARDIAN_DIAGNOSIS_ENABLED`, `GUARDIAN_ALERTS_ENABLED`, `GUARDIAN_BACKEND_CAPTURE_ENABLED`; `GUARDIAN_PLATFORM_TOKEN`; `GUARDIAN_AI_API_KEY`, `GUARDIAN_AI_BASE_URL`, `GUARDIAN_AI_MODEL`, `GUARDIAN_AI_TIMEOUT_MS`, `GUARDIAN_AI_MAX_TOKENS`, `GUARDIAN_AI_MAX_CONCURRENCY`, `GUARDIAN_AI_TOKENS_PER_COMPANY_DAY`; `GUARDIAN_WA_CLOUD_TOKEN`, `GUARDIAN_WA_PHONE_NUMBER_ID`, `GUARDIAN_WA_WABA_ID`, `GUARDIAN_WA_APP_SECRET`, `GUARDIAN_WA_VERIFY_TOKEN`, `GUARDIAN_WA_TEMPLATE_NAME`, `GUARDIAN_WA_TEMPLATE_LANG`; `GUARDIAN_ALERT_RECIPIENTS`; `GUARDIAN_READER_DATABASE_URL` |
| `guardian-uat_workers` | `DATABASE_URL`; `GUARDIAN_ENABLED`, `GUARDIAN_DIAGNOSIS_ENABLED`, `GUARDIAN_ALERTS_ENABLED`; `GUARDIAN_WORKER_INTERVAL_SECONDS`; IA (`GUARDIAN_AI_*`); WhatsApp (`GUARDIAN_WA_CLOUD_TOKEN`, `_PHONE_NUMBER_ID`, `_WABA_ID`, `_VERIFY_TOKEN`, `_TEMPLATE_NAME`, `_TEMPLATE_LANG`); `GUARDIAN_ALERT_RECIPIENTS`; `GUARDIAN_ALERT_FALLBACK_WEBHOOK_URL`, `GUARDIAN_ALERT_FALLBACK_SECRET` |
| `guardian-uat_watchdog` | `GUARDIAN_WATCHDOG_DATABASE_URL` (o `GUARDIAN_READER_DATABASE_URL`), `GUARDIAN_WATCHDOG_WEBHOOK_URL`, `GUARDIAN_WATCHDOG_WEBHOOK_TOKEN`, `GUARDIAN_WATCHDOG_WORKERS`, `GUARDIAN_WATCHDOG_HEARTBEAT_MINUTES`, `GUARDIAN_WATCHDOG_STATE_PATH` (volumen propio) |
| `guardian-uat_receiver` | `GUARDIAN_RECEIVER_TOKEN` (mismo valor que `GUARDIAN_WATCHDOG_WEBHOOK_TOKEN`) |
| `guardian-uat_db` | `POSTGRES_DB`, `POSTGRES_USER`, `POSTGRES_PASSWORD` |
| `appyra-uat` | `GUARDIAN_API_BASE_URL` (URL interna del API UAT), `GUARDIAN_PLATFORM_TOKEN` (mismo valor que en la API) |

`GUARDIAN_AI_PROVIDER` **no se configura**: no cambia el adaptador (ver
`guardian.ai.runtime.spec.ts`). Si se define, el arranque registrará una
advertencia clara.

## 5. Orden de ejecución propuesto

1. **Pre-flight** (solo lectura): confirmar que no existe `guardian-uat*` y que
   los hosts no colisionan.
2. Crear proyecto `guardian-uat` en EasyPanel + servicio `guardian-uat_db`
   (sin puertos). Anotar el nombre de la BD.
3. Copiar el esquema: `docker exec` sobre `guardian-uat_db` para
   `npx prisma migrate deploy` desde la imagen UAT (nunca contra una BD existente).
4. Crear rol de solo lectura `guardian_reader` (SELECT en `guardian_*` y `companies`).
5. Crear `guardian-uat_api` con las variables del §4 y host `guardian-uat...`.
6. Verificar (sin enviar nada): `GET /health` interno y
   `GET /guardian/webhooks/whatsapp?hub.mode=subscribe&hub.verify_token=<verify>&hub.challenge=1` → debe devolver `1`.
7. Crear `guardian-uat_workers` y `guardian-uat_watchdog` + `guardian-uat_receiver`.
8. Comprobar latidos: `SELECT worker_name, last_seen_at FROM guardian_worker_heartbeats`.
9. Crear `appyra-uat` con `GUARDIAN_API_BASE_URL` + token y validar `/api/admin/guardian/health`.
10. Registrar el webhook en Meta (acción externa, requiere autorización).

## 6. Respaldos y rollback

- **Antes de empezar**: `pg_dump` de `guardian-uat_db` en cuanto tenga esquema
  (el despliegue es aditivo; no hay datos productivos en riesgo).
- **Rollback total**: eliminar el proyecto `guardian-uat` (servicios + red) y el
  volumen `guardian-uat_db-data`; eliminar `appyra-uat`. Ningún recurso
  productivo queda afectado porque no se modifica ninguno.
- **Rollback parcial**: `docker service update --replicas=0 guardian-uat_api`
  detiene la ingesta sin borrar datos.
- **Desactivar Guardian sin borrar**: `GUARDIAN_ENABLED=false` en el servicio
  (fail-closed) y `docker service update --replicas=0` en workers.

## 7. Recursos estimados

| Servicio | RAM | vCPU |
| --- | --- | --- |
| api | 384 MB | 0,50 |
| workers | 256 MB | 0,25 |
| watchdog | 128 MB | 0,25 |
| receiver | 64 MB | 0,10 |
| db | 384 MB | 0,50 |
| Appyra UAT | 256 MB | 0,25 |
| **Total** | **~1,5 GB** | **~1,85** |

Con 5,1 GB libres y 2 vCPU: cabe, pero deja ~3,6 GB de margen; conviene no
añadir más cargas sin revisar `free -m` primero.

## 8. Riesgos del plan

1. **Aislamiento**: si por error se usa una `DATABASE_URL` productiva, Guardian
   escribiría en tablas `guardian_*` **inexistentes** allí (fallo visible, no
   corrupción). Mitigación: nombre `guardian-uat_db` y revisión de la cadena de
   conexión antes de crear el servicio.
2. **Webhook público**: expone un endpoint sin sesión (protegido por HMAC).
   Mitigación: `GUARDIAN_WA_APP_SECRET` obligatorio; sin él responde 503.
3. **Coste IA**: acotado por `GUARDIAN_AI_TOKENS_PER_COMPANY_DAY`.
4. **Mensajes reales**: bloqueados mientras `GUARDIAN_ALERT_RECIPIENTS` esté vacío.
5. **Edición manual de Traefik**: no se hará; los hosts se crean desde EasyPanel.

## 9. Puertas de aprobación

| # | Acción | Requiere |
| --- | --- | --- |
| A1 | Crear proyecto y servicios en el VPS | Autorización explícita |
| A2 | Crear BD y ejecutar migraciones | Autorización explícita |
| A3 | Transferir secretos (scp / panel) | Autorización explícita |
| A4 | Verificar el modelo con la sonda | Autorización explícita (petición externa) |
| A5 | Registrar webhook y plantilla en Meta | Acción del propietario |
| A6 | Primer mensaje real / primera alerta | Autorización explícita |
