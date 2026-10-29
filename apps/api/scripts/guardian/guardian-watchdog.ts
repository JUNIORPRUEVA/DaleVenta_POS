/**
 * Fase 3 — Watchdog independiente de APPYRA Guardian.
 *
 * Se ejecuta FUERA del API y del worker de Guardian: no importa ningún servicio
 * de `src/guardian`, solo la lógica pura de `guardian.watchdog.checks`. Habla
 * con PostgreSQL por SQL directo y avisa por un canal propio
 * (`GUARDIAN_WATCHDOG_WEBHOOK_URL`), de modo que sigue funcionando aunque
 * Guardian, sus workers o su IA estén caídos.
 *
 * Uso:
 *   GUARDIAN_WATCHDOG_DATABASE_URL=postgresql://... \
 *   GUARDIAN_WATCHDOG_WEBHOOK_URL=http://127.0.0.1:4501/alert \
 *   npm --workspace apps/api run guardian:watchdog
 *
 * Códigos de salida: 0 = sano, 2 = hallazgos, 1 = error de ejecución.
 * Pensado para cron/tarea programada cada 5-10 minutos.
 *
 * Deduplicación: guarda el estado en `GUARDIAN_WATCHDOG_STATE_PATH`
 * (por defecto `.guardian-watchdog-state.json`) para no repetir el mismo aviso
 * en cada ciclo y para emitir una notificación de recuperación.
 */
import { readFileSync, writeFileSync } from 'node:fs';
import { PrismaClient } from '@prisma/client';
import {
  emptyWatchdogState,
  evaluateGuardianHealth,
  planWatchdogNotifications,
  WATCHDOG_CODES,
  type StaleWorker,
  type WatchdogNotificationState,
  type WatchdogSnapshot,
} from '../../src/guardian/guardian.watchdog.checks';

const DEFAULT_STATE_PATH = '.guardian-watchdog-state.json';

function num(name: string, fallback: number): number {
  const parsed = Number.parseInt(String(process.env[name] ?? '').trim(), 10);
  return Number.isFinite(parsed) ? parsed : fallback;
}

function loadState(path: string): WatchdogNotificationState {
  try {
    const raw = JSON.parse(readFileSync(path, 'utf8')) as Partial<WatchdogNotificationState>;
    return { lastSentAt: raw.lastSentAt ?? {}, activeCodes: raw.activeCodes ?? [] };
  } catch {
    return emptyWatchdogState;
  }
}

function saveState(path: string, state: WatchdogNotificationState): void {
  try {
    writeFileSync(path, JSON.stringify(state, null, 2), 'utf8');
  } catch (error) {
    console.error('no se pudo guardar el estado del watchdog:', (error as Error).message);
  }
}

function expectedWorkers(): string[] {
  return String(process.env.GUARDIAN_WATCHDOG_WORKERS ?? 'alerts,diagnosis')
    .split(',')
    .map((name) => name.trim())
    .filter(Boolean);
}

async function collectSnapshot(
  stuckMinutes: number,
  heartbeatStaleMinutes: number,
): Promise<WatchdogSnapshot> {
  const url =
    process.env.GUARDIAN_WATCHDOG_DATABASE_URL ??
    process.env.GUARDIAN_READER_DATABASE_URL ??
    process.env.GUARDIAN_UAT_DATABASE_URL;
  if (!url) throw new Error('Falta GUARDIAN_WATCHDOG_DATABASE_URL');

  const base: WatchdogSnapshot = {
    databaseReachable: false,
    stuckMinutes,
    sev1UnackMinutes: num('GUARDIAN_WATCHDOG_SEV1_MINUTES', 60),
    heartbeatStaleMinutes,
    alertsPendingStuck: 0,
    diagnosesPendingStuck: 0,
    incidentsUnprocessed: 0,
    alertProviderFailures: 0,
    sev1Unacknowledged: 0,
    staleWorkers: [],
  };

  const prisma = new PrismaClient({ datasources: { db: { url } } });
  try {
    const count = async (sql: string, ...params: unknown[]): Promise<number> => {
      const rows = await prisma.$queryRawUnsafe<Array<{ n: bigint }>>(sql, ...params);
      return Number(rows[0]?.n ?? 0);
    };

    // Sonda explícita: si falla, la base está inaccesible y NO es un estado sano.
    await count('SELECT 1::bigint AS n');

    base.databaseReachable = true;
    base.alertsPendingStuck = await count(
      `SELECT COUNT(*)::bigint AS n FROM "guardian_alerts"
       WHERE state IN ('PENDING', 'QUEUED') AND created_at < (now() AT TIME ZONE 'UTC') - ($1 || ' minutes')::interval`,
      String(stuckMinutes),
    );
    base.diagnosesPendingStuck = await count(
      `SELECT COUNT(*)::bigint AS n FROM "guardian_diagnoses"
       WHERE status = 'PENDING' AND created_at < (now() AT TIME ZONE 'UTC') - ($1 || ' minutes')::interval`,
      String(stuckMinutes),
    );
    base.incidentsUnprocessed = await count(
      `SELECT COUNT(*)::bigint AS n FROM "guardian_incidents"
       WHERE processing_state NOT IN ('DIAGNOSED', 'SKIPPED')
         AND next_diagnosis_at < (now() AT TIME ZONE 'UTC') - ($1 || ' minutes')::interval`,
      String(stuckMinutes),
    );
    base.alertProviderFailures = await count(
      `SELECT COUNT(*)::bigint AS n FROM "guardian_alerts"
       WHERE state = 'PENDING' AND last_error IS NOT NULL
         AND updated_at < (now() AT TIME ZONE 'UTC') - ($1 || ' minutes')::interval`,
      String(stuckMinutes),
    );
    base.sev1Unacknowledged = await count(
      `SELECT COUNT(*)::bigint AS n FROM "guardian_incidents"
       WHERE severity = 'SEV1' AND status = 'OPEN' AND acknowledged_at IS NULL
         AND occurred_at < (now() AT TIME ZONE 'UTC') - ($1 || ' minutes')::interval`,
      String(base.sev1UnackMinutes),
    );

    const workers = expectedWorkers();
    if (workers.length > 0) {
      const activeRecently = await count(
        `SELECT COUNT(*)::bigint AS n FROM "guardian_incidents"
         WHERE received_at > (now() AT TIME ZONE 'UTC') - ($1 || ' minutes')::interval`,
        String(Math.max(heartbeatStaleMinutes, 60)),
      );
      const heartbeats = await prisma.$queryRawUnsafe<
        Array<{ worker_name: string; age_minutes: number }>
      >(
        `SELECT worker_name,
                EXTRACT(EPOCH FROM ((now() AT TIME ZONE 'UTC') - last_seen_at)) / 60 AS age_minutes
         FROM "guardian_worker_heartbeats"
         WHERE worker_name = ANY($1::text[])`,
        workers,
      );
      const seen = new Map(heartbeats.map((row) => [row.worker_name, Number(row.age_minutes)]));
      const stale: StaleWorker[] = [];
      for (const workerName of workers) {
        const ageMinutes = seen.get(workerName);
        // Sin latido solo se alerta si el pipeline muestra actividad reciente: un
        // entorno donde nunca se arrancaron los workers no genera ruido eterno.
        const missing = ageMinutes === undefined && activeRecently > 0;
        const expired = ageMinutes !== undefined && ageMinutes > heartbeatStaleMinutes;
        if (missing || expired) {
          stale.push({ workerName, ageMinutes: ageMinutes ?? Number.POSITIVE_INFINITY });
        }
      }
      base.staleWorkers = stale;
    }
  } catch (error) {
    base.databaseReachable = false;
    base.databaseError = (error as Error).message;
  } finally {
    await prisma.$disconnect().catch(() => undefined);
  }

  return base;
}

async function notify(payload: unknown): Promise<void> {
  const webhook = String(process.env.GUARDIAN_WATCHDOG_WEBHOOK_URL ?? '').trim();
  if (!webhook) return;
  try {
    const response = await fetch(webhook, {
      method: 'POST',
      headers: {
        'content-type': 'application/json',
        ...(process.env.GUARDIAN_WATCHDOG_WEBHOOK_TOKEN
          ? { authorization: `Bearer ${process.env.GUARDIAN_WATCHDOG_WEBHOOK_TOKEN}` }
          : {}),
      },
      body: JSON.stringify(payload),
    });
    console.log(`webhook enviado: HTTP ${response.status}`);
  } catch (error) {
    console.error('webhook fallido:', (error as Error).message);
  }
}

async function main(): Promise<void> {
  const stuckMinutes = num('GUARDIAN_WATCHDOG_STUCK_MINUTES', 30);
  const heartbeatStaleMinutes = num('GUARDIAN_WATCHDOG_HEARTBEAT_MINUTES', 10);
  const reAlertMinutes = num('GUARDIAN_WATCHDOG_REALERT_MINUTES', 60);
  const statePath = String(process.env.GUARDIAN_WATCHDOG_STATE_PATH ?? DEFAULT_STATE_PATH);

  const snapshot = await collectSnapshot(stuckMinutes, heartbeatStaleMinutes);
  const findings = evaluateGuardianHealth(snapshot);
  const now = new Date();
  const plan = planWatchdogNotifications(findings, loadState(statePath), now, { reAlertMinutes });

  const report = {
    watchdog: 'guardian-watchdog',
    checkedAt: now.toISOString(),
    databaseReachable: snapshot.databaseReachable,
    stuckMinutes,
    heartbeatStaleMinutes,
    healthy: plan.healthy,
    findings: plan.send.length > 0 ? plan.send : findings,
    recovered: plan.recovered,
    notified: plan.send.length > 0 || plan.recovered.length > 0,
  };
  console.log(JSON.stringify(report, null, 2));

  if (plan.send.length > 0 || plan.recovered.length > 0) {
    await notify({
      ...report,
      code: plan.send[0]?.code ?? WATCHDOG_CODES.watchdogRecovered,
      event: plan.send.length > 0 ? 'GUARDIAN_ALERT' : 'GUARDIAN_RECOVERED',
    });
  }

  saveState(statePath, plan.nextState);
  if (!plan.healthy) process.exitCode = 2;
}

main().catch((error) => {
  console.error('watchdog error:', error);
  process.exit(1);
});
