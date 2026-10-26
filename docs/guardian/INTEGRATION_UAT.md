# Integración Fullpos ↔ Appyra (UAT)

Estado verificado de la integración de los dos entregables (backend Guardian y
panel Appyra) sobre una base UAT aislada. Sin secretos y sin datos de producción.

## Contrato que consume el panel

El panel Flutter **nunca** llama a Guardian ni transporta el token de plataforma.
Habla con su propio backend (`/api/admin/guardian/*`), que firma en servidor la
llamada a `/guardian/platform/*`.

| Panel (Appyra) | Guardian (Fullpos) | Notas |
| --- | --- | --- |
| `GET /health` | `GET /guardian/platform/health` | WhatsApp solo se reporta configurado con identidad propia (`GUARDIAN_WA_*`), nunca por heredar `META_*`. |
| `GET /summary` | `GET /guardian/platform/summary` | Incluye alertas `QUEUED` como pendientes. |
| `GET /companies` | `GET /guardian/platform/companies` | Contadores abiertos/críticos y `monitored`. |
| `GET /incidents` | `GET /guardian/platform/incidents` | Filtros y cursor; allowlist de query params en el proxy. |
| `GET /incidents/:id` | `GET /guardian/platform/incidents/:id` | `attemptsLog` se proyecta sin `id` (BigInt) para que sea serializable. |
| `POST /incidents/:id/{ack,investigate,resolve,close,reopen}` | mismo path | Historial con `platform:<acción>`. |
| `GET /workers` | `GET /guardian/platform/workers` | **Nuevo en la integración**. Reutiliza el clasificador del watchdog (`ok`/`stale`/`missing`). |

## Esquema de alertas unificado

La base UAT ya contenía una migración `20261026210000_guardian_alert_delivery_states`
(estados `QUEUED`/`ACCEPTED`/`READ`, columnas `accepted_at`/`read_at`) creada por
otro agente. Para no perderla ni reescribir historial, la integración adopta la
unión:

1. `20261026210000_guardian_alert_delivery_states` — estados base y `read_at`.
2. `20261026220000_guardian_alert_delivery_states` — añade
   `recipient_number`, `last_provider_status`, índice por `provider_message_id`.

Orden monotónico: `PENDING < QUEUED ≈ SENDING < ACCEPTED ≈ SENT < DELIVERED < READ`.
Nunca retrocede; un `failed` posterior a la entrega conserva la evidencia.

## Comprobaciones ejecutadas

- Migraciones desde base nueva y sobre UAT existente (Fullpos y Appyra).
- Suite backend completa (913 pruebas) y build.
- E2E real: ingesta HTTP → alerta → entrega/lectura → diagnóstico → proxy Appyra
  → reconocer → resolver → historial → workers → aislamiento multiempresa.
- Caída del backend Guardian: el proxy responde `502 GUARDIAN_UNREACHABLE`;
  recuperación automática a `200` al volver.
- Watchdog: sano, base caída y recuperación con receptor local.
- Playwright: escritorio, móvil y expediente (ver `guardian-evidence/` en el repo Appyra).

## Ejecución local

```text
# Fullpos (apps/api)
DATABASE_URL=postgresql://postgres@127.0.0.1:55661/guardian_uat_integration
JWT_SECRET=<local> PORT=4010 GUARDIAN_ENABLED=true GUARDIAN_INGEST_ENABLED=true
GUARDIAN_DIAGNOSIS_ENABLED=true GUARDIAN_ALERTS_ENABLED=true
GUARDIAN_PLATFORM_TOKEN=<local> GUARDIAN_ALERT_RECIPIENT=<número-de-prueba>
npm run start:dev

# Appyra (backend)
PG_HOST=127.0.0.1 PG_PORT=55661 PG_USER=postgres PG_DATABASE=appyra_panel_uat_integration
GUARDIAN_API_BASE_URL=http://127.0.0.1:4010 GUARDIAN_PLATFORM_TOKEN=<local>
ADMIN_USERNAME=<local> ADMIN_PASSWORD=<local> PORT=3100
node backend/server.js

# E2E
npx ts-node --transpile-only -P tsconfig.scripts.json \
  scripts/guardian/guardian-panel-integration-uat.ts
```

Nunca usar credenciales ni bases de producción.
