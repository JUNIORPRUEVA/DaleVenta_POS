# APPYRA Guardian AI — Runbook de piloto (UAT)

Documento operativo para levantar, verificar, desactivar y revertir Guardian en un
entorno **UAT**. No describe ningún procedimiento de producción: el piloto en
producción requiere autorización explícita y las credenciales reales de la sección 9.

Estado del código: rama `agent/guardian-fase0` (Fullpos Cloud) y `agent/guardian-panel` (Appyra).

---

## 1. Variables de entorno

Guardian está **desactivado por defecto** (`fail-closed`): sin configuración no captura,
no diagnostica y no alerta.

| Variable | Obligatoria | Default | Descripción |
| --- | --- | --- | --- |
| `GUARDIAN_ENABLED` | sí (para activar) | `false` | Interruptor maestro. |
| `GUARDIAN_INGEST_ENABLED` | no | = `GUARDIAN_ENABLED` | Acepta `POST /guardian/incidents`. |
| `GUARDIAN_BACKEND_CAPTURE_ENABLED` | no | `false` | Captura excepciones 5xx del API. |
| `GUARDIAN_DIAGNOSIS_ENABLED` | no | `false` | Worker de diagnóstico IA. |
| `GUARDIAN_ALERTS_ENABLED` | no | `false` | Worker de alertas. |
| `GUARDIAN_PLATFORM_TOKEN` | sí (panel) | — | Token del canal de plataforma. Solo en servidor. |
| `GUARDIAN_READER_DATABASE_URL` | sí (IA) | — | Rol PostgreSQL de **solo lectura**. |
| `GUARDIAN_MAX_BATCH_EVENTS` | no | `20` | Eventos por lote de ingesta. |
| `GUARDIAN_ALERT_RECIPIENT` | no | — | Destinatario administrativo de alertas. |
| `GUARDIAN_DIAGNOSIS_MAX_ATTEMPTS` | no | `4` | Reintentos de diagnóstico. |
| `GUARDIAN_RETENTION_DAYS` | no | `90` | Retención de SEV3/SEV4. |
| `GUARDIAN_RETENTION_CRITICAL_DAYS` | no | `365` | Retención de SEV1/SEV2 y de auditoría. |
| `GUARDIAN_RETENTION_MAX_PER_COMPANY` | no | `5000` | Tope de incidentes por empresa. |
| `GUARDIAN_RETENTION_APPLY` | no | `false` | Sin `true`, la retención solo simula. |
| `GUARDIAN_RETENTION_BATCH_SIZE` | no | `500` | Filas por lote de borrado. |
| `GUARDIAN_RETENTION_MAX_BATCHES` | no | `20` | Lotes por ejecución. |

Watchdog (proceso aparte):

| Variable | Default | Descripción |
| --- | --- | --- |
| `GUARDIAN_WATCHDOG_DATABASE_URL` | — | Base a vigilar (usa rol de lectura). |
| `GUARDIAN_WATCHDOG_WEBHOOK_URL` | — | Canal propio, independiente de Guardian. |
| `GUARDIAN_WATCHDOG_WEBHOOK_TOKEN` | — | Bearer opcional del webhook. |
| `GUARDIAN_WATCHDOG_STUCK_MINUTES` | `30` | Umbral de cola atascada. |
| `GUARDIAN_WATCHDOG_SEV1_MINUTES` | `60` | Umbral de SEV1 sin reconocer. |
| `GUARDIAN_WATCHDOG_HEARTBEAT_MINUTES` | `10` | Umbral de latido de workers. |
| `GUARDIAN_WATCHDOG_REALERT_MINUTES` | `60` | Reaviso del mismo hallazgo. |
| `GUARDIAN_WATCHDOG_WORKERS` | `alerts,diagnosis` | Workers que deben latir. |
| `GUARDIAN_WATCHDOG_STATE_PATH` | `.guardian-watchdog-state.json` | Estado de deduplicación. |

Appyra (panel):

| Variable | Descripción |
| --- | --- |
| `GUARDIAN_API_BASE_URL` | URL del API de Fullpos (ej. `http://127.0.0.1:4010`). |
| `GUARDIAN_PLATFORM_TOKEN` | Mismo token; **nunca** se envía al navegador. |

## 2. Migraciones

Tres migraciones aditivas, ninguna destructiva:

| Migración | Contenido |
| --- | --- |
| `20261026140000_guardian_phase1` | 7 tablas base de Guardian. |
| `20261026160000_guardian_phase4_alerts` | 2 tablas de alertas. |
| `20261026180000_guardian_alerts_fk` | FK de alertas a incidentes (`ON DELETE CASCADE`). |
| `20261026200000_guardian_worker_heartbeats` | Latido de workers. |

Aplicación en UAT:

```powershell
Set-Location apps/api
$env:DATABASE_URL='postgresql://<usuario>:<clave>@127.0.0.1:55661/daleventa_pos_uat'
npx prisma migrate deploy
```

Rollback: `npx prisma migrate resolve` no revierte SQL. Para deshacer, ejecutar el
`DROP TABLE` correspondiente solo en UAT y con copia previa (ver §10).

## 3. Secretos

- `GUARDIAN_PLATFORM_TOKEN`: cadena aleatoria ≥32 caracteres, distinta por entorno.
  Vive solo en el proceso del API y en el backend de Appyra; nunca en el cliente Flutter.
- `GUARDIAN_READER_DATABASE_URL`: rol de lectura con contraseña rotable.
- Ninguno de los dos debe aparecer en logs. El proxy de Appyra no registra el token.
- Rotación: cambiar el valor en el gestor de secretos y reiniciar API + backend de Appyra
  (los workers no lo usan).

## 4. Roles PostgreSQL

```sql
-- Rol de solo lectura para las herramientas de diagnóstico IA.
CREATE ROLE guardian_reader LOGIN PASSWORD '<clave>';
GRANT CONNECT ON DATABASE daleventa_pos_uat TO guardian_reader;
GRANT USAGE ON SCHEMA public TO guardian_reader;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO guardian_reader;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON TABLES TO guardian_reader;
REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON ALL TABLES IN SCHEMA public FROM guardian_reader;
```

Verificación obligatoria antes del piloto:

```sql
-- Debe devolver 0 filas de escritura permitida.
SELECT table_name, privilege_type
FROM information_schema.role_table_grants
WHERE grantee = 'guardian_reader'
  AND privilege_type IN ('INSERT','UPDATE','DELETE','TRUNCATE');
```

## 5. Activación por empresa

1. `GUARDIAN_ENABLED=true` a nivel de servicio (interruptor global).
2. La cuota por empresa vive en `guardian_company_quotas` (`companyId`, límites).
   Una empresa sin cuota no recibe captura del cliente.
3. El cliente Flutter solo envía si `GuardianConfig.enabled` está activo en el build
   (por defecto desactivado) — ver `lib/core/guardian/guardian_config.dart`.

## 6. Desactivación remota

| Acción | Efecto |
| --- | --- |
| `GUARDIAN_ENABLED=false` + reinicio del API | Deja de aceptar ingesta y de capturar. |
| `GUARDIAN_ALERTS_ENABLED=false` + reinicio de workers | Detiene alertas salientes. |
| `GUARDIAN_DIAGNOSIS_ENABLED=false` + reinicio de workers | Detiene el diagnóstico IA. |
| Cuota de empresa a 0 en `guardian_company_quotas` | Bloquea esa empresa sin tocar el resto. |

El watchdog **no** depende de Guardian: seguirá avisando aunque todo lo anterior esté apagado.

## 7. Workers e instalación

```powershell
Set-Location apps/api
# Diagnóstico IA + alertas, en proceso aparte del API
npm run guardian:workers
```

Programación en UAT (no activar en producción):

```powershell
# Retención diaria en dry-run
schtasks /create /tn "GuardianRetention" /sc daily /st 03:30 ^
  /tr "cmd /c cd /d C:\src\fullpos-guardian-fase0\apps\api && npx ts-node --transpile-only -P tsconfig.scripts.json scripts/guardian/guardian-retention.ts"

# Watchdog cada 5 minutos
schtasks /create /tn "GuardianWatchdog" /sc minute /mo 5 ^
  /tr "cmd /c cd /d C:\src\fullpos-guardian-fase0\apps\api && npm run guardian:watchdog"
```

## 8. Reinicio y recuperación

1. Detener workers (`Ctrl+C` / señal). El API sigue atendiendo ventas.
2. Reiniciar el API: `node dist/main.js`.
3. Reiniciar workers: `npm run guardian:workers`. Reanudan por `nextDiagnosisAt`/`nextAttemptAt`,
   sin perder trabajo: los claims son por CAS con TTL.
4. Si los workers no arrancan: ejecutar el watchdog; sus hallazgos indican la fase rota
   (`ALERTS_STUCK`, `DIAGNOSIS_STUCK`, `WORKER_HEARTBEAT_STALE`).

## 9. Requisitos externos pendientes (bloquean el piloto real)

| Requisito | Dónde se configura | Estado |
| --- | --- | --- |
| WhatsApp Cloud API: token, phone number id, plantilla aprobada, idioma | `GUARDIAN_WA_CLOUD_TOKEN`, `GUARDIAN_WA_PHONE_NUMBER_ID`, plantilla HSM | **pendiente**: sin credenciales no se envía nada real |
| `verify_token` y `app_secret` del webhook | `GUARDIAN_WA_VERIFY_TOKEN`, `GUARDIAN_WA_APP_SECRET` | **pendiente** |
| Número administrativo autorizado por escrito | `GUARDIAN_ALERT_RECIPIENT` | **pendiente** |
| Proveedor IA real | `GUARDIAN_AI_PROVIDER=openai` + `OPENAI_API_KEY` | **pendiente** (hoy `mock`) |
| Canal de respaldo | `GUARDIAN_ALERT_FALLBACK_WEBHOOK_URL` | **pendiente** |
| Watchdog | `GUARDIAN_WATCHDOG_WEBHOOK_URL` | probado con receptor local |

## 10. Copias de seguridad

Antes de aplicar retención o migraciones en UAT:

```powershell
& 'C:\Program Files\PostgreSQL\16\bin\pg_dump.exe' -h 127.0.0.1 -p 55661 -U postgres `
  -d daleventa_pos_uat -f "C:\src\guardian_backup_$(Get-Date -Format yyyyMMdd-HHmmss).sql"
```

Verificar el archivo (tamaño > 0 y contiene `CREATE TABLE`) antes de continuar.

## 11. Rollback

| Escenario | Procedimiento |
| --- | --- |
| Guardian molesta en operación | `GUARDIAN_ENABLED=false` + reiniciar API; los workers se detienen. |
| Workers consumen recursos | detener `guardian:workers`; las ventas no se ven afectadas. |
| Migración problemática | restaurar el `pg_dump` previo en UAT; el código tolera tablas Guardian vacías. |
| Panel Appyra falla | `GUARDIAN_API_BASE_URL` vacío → el proxy responde 503 `GUARDIAN_NOT_CONFIGURED`; el resto del panel sigue operativo. |

## 12. Compatibilidad con versiones antiguas

- El contrato de ingesta acepta `schemaVersion: 1` y descarta eventos con versión distinta.
- Clientes Flutter sin módulo Guardian simplemente no envían nada.
- El contrato financiero legacy (`FINANCIAL_LEGACY_COMPAT`) es independiente de Guardian.
- Ninguna migración de Guardian toca tablas de ventas, caja, inventario, NCF o licencias.

## 13. Despliegue reproducible en UAT (sin ejecutar todavía)

```powershell
# 1. Base aislada
$env:DATABASE_URL='postgresql://postgres@127.0.0.1:55661/daleventa_pos_uat'

# 2. Esquema
Set-Location C:\src\fullpos-guardian-fase0\apps\api
npx prisma migrate deploy

# 3. API
$env:PORT='4010'; $env:JWT_SECRET='<secreto-uat>'
$env:GUARDIAN_ENABLED='true'; $env:GUARDIAN_INGEST_ENABLED='true'
$env:GUARDIAN_PLATFORM_TOKEN='<token-32+>'
$env:GUARDIAN_READER_DATABASE_URL='postgresql://guardian_reader:<clave>@127.0.0.1:55661/daleventa_pos_uat'
node dist/main.js

# 4. Workers (otra terminal)
npm run guardian:workers

# 5. Panel Appyra
Set-Location C:\src\appyra-guardian-panel
$env:GUARDIAN_API_BASE_URL='http://127.0.0.1:4010'
$env:GUARDIAN_PLATFORM_TOKEN='<mismo token>'
$env:SKIP_STARTUP_MIGRATIONS='1'   # solo si la base local ya está migrada
node backend/server.js

# 6. Verificación
curl -H "x-guardian-platform-token: <token>" http://127.0.0.1:4010/guardian/platform/summary
npm --workspace apps/api run guardian:watchdog
```
