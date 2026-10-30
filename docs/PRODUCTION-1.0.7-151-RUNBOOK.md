# Runbook — Backend integrado `1.0.7+151` (Guardian AI activo + autocorrección V2)

Documento operativo. **Nada de este runbook se ejecutó todavía**: la imagen está
construida y probada en local, y cada paso de producción requiere autorización
explícita del propietario en la tarea en curso.

Este runbook **sustituye al §3 del runbook 150** (`PRODUCTION-1.0.7-150-RUNBOOK.md`)
para el despliegue del backend: producción ya ejecuta Guardian AI y no se puede
desplegar una imagen que no lo contenga.

---

## 0. Estado real de producción (verificado en modo lectura, 2026-10-30 ~04:35 UTC)

| Dato | Valor |
| --- | --- |
| Host | `srv902744` = `31.97.99.70` (1 vCPU, 58 GB libres, ~4,7 GB RAM disponible) |
| Base | `daleventa` · PostgreSQL **17.11** · 66 MB · contenedor `daleventapos_database.1.zh8ls3st60soybaw6jlxmbwdd` |
| `_prisma_migrations` | **181 aplicadas** · última `20261028180000_guardian_company_optin` · **0** tablas V2 |
| Backend | `easypanel/daleventapos/backend:autoenroll-5d8a5f98` · `Id sha256:7805798…3ac78` · creada 2026-10-30T03:12Z · desplegada **03:35:00 UTC** |
| Guardian worker | misma imagen · **actualizado 03:30:40 UTC** |
| PWA | `fullpos/daleventapos-pwa:offline-144` (sin cambios desde 2026-10-19) |
| Réplicas | backend 1/1 · guardian_worker 1/1 · database 1/1 · dbgate 1/1 · pwa 1/1 · pgweb 0/0 |
| `UpdateStatus` | `completed` en backend y worker · **ningún despliegue en curso**, ningún `docker build/push` activo |
| Backend `/health` | `{"status":"ok"}` |
| Guardian en BD | **12 tablas** · `companies.guardian_enabled=true` en **1** empresa · 7 credenciales de estación · 6 incidentes · 4 diagnósticos · 2 alertas · 2 intentos de alerta |
| Guardian flags activos | backend: `GUARDIAN_ENABLED=true`, `GUARDIAN_ALERTS_ENABLED=true`; worker: además `GUARDIAN_DIAGNOSIS_ENABLED=true`, `GUARDIAN_AI_PROVIDER=deepseek`, WhatsApp con secretos montados (`/run/secrets/ai_api_key`, `/run/secrets/wa_cloud_token`), WABA `1574660008027902`, phone id `1403225316204356`, plantilla `guardian_incident_alert`, `GUARDIAN_AUTO_ENROLL_ENABLED=false` |

**Regla de oro de este despliegue: se actualiza la imagen del servicio, nunca se
recrea el servicio.** `docker service update --image …` conserva todo el `Spec`
(env, secretos, límites, healthchecks); un `docker service rm` + `create` los perdería.

Discrepancia menor detectada (informativa): el env `GIT_SHA` del servicio sigue en
`20e862680eb2fac42c3a1fca2b92b92b52906f1c`, valor anterior al build `autoenroll-5d8a5f98`.
No afecta al funcionamiento, pero conviene corregirlo al desplegar el 151.

---

## 1. Imagen integrada definitiva

| Dato | Valor |
| --- | --- |
| Rama | `agent/guardian-151-release` |
| Commit | **`2fd7be4d`** (`fix(guardian): la consulta de estado del panel…`), padre `f6fdbce4` (merge) sobre `3b5fabdb` |
| Tag local | `daleventapos-prod-api:1.0.7-151-2fd7be4d` |
| Digest | `sha256:14af9bd01c13fdc03bdae70afcb0c6b63957a3b2e229af3e25b89a09cc8273bc` |
| Tamaño | 762.811.961 B (763 MB) |
| Base | `node:20-bookworm-slim`, CMD `sh scripts/start-prod.sh`, healthcheck `/health` |

### Contenido comprobado

| Check | Resultado |
| --- | --- |
| Guardian **idéntico** a producción | huella `md5` de `dist/guardian/*.js` = **`14e8b89c83245a8edafb2b5fddeb4b35`** en la imagen nueva **y** en la imagen activa de producción |
| `git diff 5d8a5f98 2fd7be4d -- apps/api/src/guardian` | **0 archivos** (el código de backend de Guardian entra sin un solo cambio) |
| Auto-enrolamiento | presente (`guardian.auto-enrollment.service.js`, `.controller.js`) |
| Saldo real DeepSeek | presente (`guardian.ai.balance.monitor.js`) |
| Recuperación V2 | presente (`dist/sales/sale-reconciliation-obligation.service.js`; ruta en `sales.controller.js`) |
| `git diff 5d8a5f98 2fd7be4d -- apps/api/src/sales` | **+44 / −0** en `sales.controller.ts`, **+2 / −0** en `sales.module.ts` |
| Rutas nuevas (solo 3) | `POST attempts/:clientRequestId/declaration`, `GET reconciliation-obligations`, `GET reconciliation-obligations/:id/events` |
| `prisma/schema.prisma` vs `production-main` | **+92 / −0** (solo los dos modelos V2; ningún modelo existente tocado) |
| Migraciones nuevas | exactamente 2, ambas aditivas |
| Cliente | único cambio en `lib/core/guardian/guardian_monitoring_panel.dart` (consulta explícita; ver §5) |

---

## 2. Prueba ejecutada contra copia restaurada de PostgreSQL

Respaldo verificado: `fullpos_prod_20261030_030249.dump` · 6.776.529 B ·
SHA256 `9f544e54ff58b92cd5c6a3a31618aed11f71da6f0da0c928e9f55eedca76b8a2`.

Procedimiento: `postgres:17` aislado en red propia (sin puertos publicados) →
`pg_restore --no-owner` (exit 0) → contenedor de la imagen integrada con
`RUN_MIGRATIONS=true` contra esa copia.

| Check | Antes | Después |
| --- | --- | --- |
| `_prisma_migrations` con `finished_at` | 181 | **183** |
| Tablas V2 | 0 | **2** |
| `Sale` | 11.828 | **11.828** |
| `SaleItem` | 17.884 | **17.884** |
| `Product` | 526 | **526** |
| `inventory_movements` | 8.541 | **8.541** |
| `cash_sessions` / `cashbox_daily` | 279 / 179 | **279 / 179** |
| `auth_sessions` | 21.061 | **21.061** |
| Tablas `guardian*` | 12 (25 access_logs, 14 evidences, 7 machine_credentials, 6 incidents, 4 diagnoses, 2 alerts…) | **12 · idénticas** |
| Índices V2 | — | 5 en `sale_reconciliation_obligations` (incl. único parcial `…active_operation_key`) + 3 en `sale_reconciliation_declaration_events` |
| Arranque | — | `healthy`, `/health` 200, `All migrations have been successfully applied` |

Rutas con la imagen integrada (sin token): `/health` **200** ·
`/sales/open-tickets` **401** · `/sales/reconciliation-obligations` **401** ·
`/sales/attempts/x/reconciliation` **401** · `/guardian/admin/company/status`
**401** · `/products` **401**. Es decir: recuperación V2 y Guardian conviven y
ninguna ruta existente desaparece.

Otras validaciones ya hechas sobre `2fd7be4d`: `npm ci` exit 0 · `npm run api:build`
exit 0 · `npm --workspace apps/api test` **115 suites / 1178 tests PASS** (101 skip,
0 fail) · `flutter analyze` **No issues found** · `flutter test` **1533 PASS / 9 skip / 0 FAIL**.

---

## 3. Compatibilidad con los clientes Windows 148 / 149

| Check | Resultado |
| --- | --- |
| Rutas existentes modificadas | **ninguna** (`sales.controller.ts` +44/−0, `sales.module.ts` +2/−0) |
| DTO / contratos existentes | sin cambios (los 3 endpoints nuevos son aditivos) |
| Esquema de datos | solo 2 modelos nuevos; ningún `ALTER` sobre tablas existentes |
| PWA | sin cambios (`offline-144`), se sirve igual |
| Riesgo residual | el cliente 148 no conoce las tablas nuevas y no las usa: no puede romperse por su existencia |

Conclusión: el backend 151 es compatible hacia atrás con 148 y 149. Los clientes
antiguos siguen operando sin cambios; las funciones V2 solo las usa un cliente 150/151.

---

## 4. Orden exacto de operaciones (cada una requiere autorización)

```text
[1] Respaldo fresco de PostgreSQL  ->  AUTORIZAR RESPALDO
[2] Transferir imagen + verificar digest  ->  AUTORIZAR TRANSFERENCIA
[3] prisma migrate deploy (2 migraciones) ->  AUTORIZAR MIGRACIÓN
[4] Verificación posterior (SQL + rutas)  ->  incluida en [3]
[5] docker service update --image (backend y worker) -> AUTORIZAR DESPLIEGUE
[6] Comprobaciones 148 + piloto           ->  AUTORIZAR PILOTO
[7] Publicación del instalador            ->  AUTORIZAR PUBLICACIÓN
```

### [1] Respaldo fresco (obligatorio: los datos cambiaron desde el 03:02)

```bash
TS=$(date -u +%Y%m%dT%H%M%SZ)
CID=$(docker ps --format '{{.ID}} {{.Names}}' | awk '/daleventapos_database\.1\./ {print $1; exit}')
docker exec "$CID" sh -c 'pg_dump -U "$POSTGRES_USER" -d "$POSTGRES_DB" --format=custom' \
  > "/root/daleventas-backups/fullpos_prod_${TS}.dump"
sha256sum "/root/daleventas-backups/fullpos_prod_${TS}.dump"
```

Sin este respaldo no se ejecuta [3] ni [5].

### [2] Transferir la imagen (construida en local, **nunca** en el servidor)

```bash
# en el equipo de build
docker save daleventapos-prod-api:1.0.7-151-2fd7be4d | gzip -1 > 151-2fd7be4d.tar.gz
scp -i ~/.ssh/daleventas_codex 151-2fd7be4d.tar.gz root@31.97.99.70:/root/
# en el servidor
gunzip -c /root/151-2fd7be4d.tar.gz | docker load
docker image inspect daleventapos-prod-api:1.0.7-151-2fd7be4d --format '{{.Id}}'
# DEBE imprimir sha256:14af9bd01c13fdc03bdae70afcb0c6b63957a3b2e229af3e25b89a09cc8273bc
```

Si el digest no coincide, **detenerse**.

### [3] Migraciones (las dos de V2, aditivas)

```bash
DU=$(docker service inspect daleventapos_backend \
  --format '{{range .Spec.TaskTemplate.ContainerSpec.Env}}{{println .}}{{end}}' \
  | sed -n 's/^DATABASE_URL=//p')
DBNET=$(docker inspect "$(docker ps --format '{{.ID}} {{.Names}}' \
  | awk '/daleventapos_database\.1\./ {print $1; exit}')" \
  --format '{{range $k,$v := .NetworkSettings.Networks}}{{$k}} {{end}}' | awk '{print $1}')

docker run --rm --network "$DBNET" -e "DATABASE_URL=$DU" \
  daleventapos-prod-api:1.0.7-151-2fd7be4d npx prisma migrate deploy
```

La `DATABASE_URL` se lee del propio servicio y **no se imprime**.
Prohibido: `migrate reset`, borrar filas de `_prisma_migrations`, tocar
`20260329140000_add_fifteen_minutes_pending_job`.

Verificación inmediata (leer `DATABASE_URL` igual, sin imprimirla):

```sql
select count(*) from _prisma_migrations where finished_at is not null;   -- 183
select count(*) from information_schema.tables where table_name in
  ('sale_reconciliation_obligations','sale_reconciliation_declaration_events'); -- 2
select count(*) from "Sale";              -- 11828
select count(*) from "SaleItem";          -- 17884
select count(*) from "Product";           -- 526
select count(*) from inventory_movements; -- 8541
select count(*) from cash_sessions;       -- 279
select count(*) from cashbox_daily;       -- 179
select count(*) from information_schema.tables where table_name like 'guardian%'; -- 12
select count(*) from companies where guardian_enabled = true;            -- 1
```

### [5] Despliegue (start-first, conservando todo el `Spec`)

```bash
# referencia de rollback (no borra nada)
docker service inspect daleventapos_backend --format '{{.Spec.TaskTemplate.ContainerSpec.Image}}'

docker service update \
  --image daleventapos-prod-api:1.0.7-151-2fd7be4d \
  --no-resolve-image \
  --update-order start-first --update-parallelism 1 \
  daleventapos_backend

docker service update \
  --image daleventapos-prod-api:1.0.7-151-2fd7be4d \
  --no-resolve-image \
  --update-order start-first --update-parallelism 1 \
  daleventapos_guardian_worker
```

`--no-resolve-image` es necesario porque la imagen está en el almacén local del
nodo y no en un registro. `--image` **no** toca env, secretos ni flags de Guardian.

Post-despliegue obligatorio:

```bash
docker service ps daleventapos_backend --filter desired-state=running
docker service inspect daleventapos_backend --format '{{range .Spec.TaskTemplate.ContainerSpec.Env}}{{println .}}{{end}}' \
  | grep -E '^(GUARDIAN_ENABLED|GUARDIAN_ALERTS_ENABLED|RUN_MIGRATIONS|RUN_SEED)='
# esperado: GUARDIAN_ENABLED=true, GUARDIAN_ALERTS_ENABLED=true, RUN_MIGRATIONS=false, RUN_SEED=false
curl -s -o /dev/null -w '%{http_code}\n' https://daleventapos-backend.gcdndd.easypanel.host/health   # 200
```

### [6] Rollback (plan)

| Situación | Acción | Efecto |
| --- | --- | --- |
| Backend no arranca o `/health` falla tras [5] | `docker service rollback daleventapos_backend` y `… daleventapos_guardian_worker` | Swarm restaura la spec anterior (`autoenroll-5d8a5f98`, con secretos y flags intactos) en segundos |
| Guardian deja de diagnosticar | mismo `rollback` del worker + revisar `docker service logs daleventapos_guardian_worker` | vuelve la imagen actual de Guardian |
| Migraciones aplicadas pero se revierte el backend | **no revertir la base**: las 2 tablas nuevas son inertes para el código antiguo | 0 impacto en ventas/caja/inventario |
| Corrupción de datos (no esperada: migraciones aditivas) | `pg_restore` del respaldo de [1] en una base nueva y reapuntar la `DATABASE_URL` | pérdida acotada a la ventana posterior al respaldo |

Rollback de datos **nunca** con `DROP`/`DELETE`: se restaura a una base nueva.

### [7] Publicación del cliente (fase posterior, separada)

El cliente debe publicarse como **`1.0.7+151`** (integrado: recuperación V2 +
panel Guardian). El `1.0.7+150` se conserva como build de recuperación sin panel;
el actualizador compara **solo `buildNumber`**, así que no puede haber dos 150.
No publicar 150 y 151 a la vez; `1.0.6-148` sigue siendo el estable por defecto.

---

## 5. Cambio de cliente incluido en 151 (no es de Guardian, es un defecto suyo)

`guardian_monitoring_panel.dart`: el panel lanzaba la consulta autenticada en
`initState`; ese camino arma el temporizador de 6 s de `TokenStorage` sobre
`SharedPreferences` y quedaba vivo si la pantalla desaparecía (2 tests de
`AccountUpdatesScreen` fallaban: `A Timer is still pending…`). Ahora la consulta es
explícita («Consultar estado del monitoreo»), el repositorio acepta `CancelToken`
y se cierra en `dispose()`, y los timeouts viven en `BaseOptions`.
**No altera ninguna funcionalidad de Guardian** (mismo backend, mismas rutas,
mismos datos); solo evita una petición y un temporizador innecesarios.

---

## 6. Intocables

- Secretos, `Spec` de los servicios, alertas, diagnóstico y opt-in de Guardian.
- La estable `1.0.6-148` y sus artefactos.
- La fila histórica `20260329140000_add_fifteen_minutes_pending_job`.
- Datos de clientes reales: ninguna operación de escritura fuera de las dos migraciones.
- No construir imágenes en el servidor (1 vCPU, 4,7 GB RAM).
