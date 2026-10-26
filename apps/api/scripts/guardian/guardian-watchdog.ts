/**
 * Fase B — Autovigilancia independiente (watchdog).
 *
 * Comprueba la salud del pipeline Guardian desde FUERA: no importa ningún módulo
 * de `src/guardian`, habla con la base por SQL directo y reporta por un canal
 * propio (`GUARDIAN_WATCHDOG_WEBHOOK_URL`), de modo que sigue avisando aunque
 * Guardian, sus alertas o su IA estén caídos.
 *
 * Uso:
 *   GUARDIAN_WATCHDOG_DATABASE_URL=postgresql://... npx ts-node --transpile-only \
 *     -P tsconfig.scripts.json scripts/guardian/guardian-watchdog.ts
 *
 * Códigos de salida: 0 = sano, 2 = hallazgos, 1 = error de ejecución.
 * Pensado para ejecutarse por cron/tarea programada cada 5-10 minutos.
 */
import { PrismaClient } from '@prisma/client';

const STUCK_MINUTES = Number(process.env.GUARDIAN_WATCHDOG_STUCK_MINUTES ?? 30);
const SEV1_UNACK_MINUTES = Number(process.env.GUARDIAN_WATCHDOG_SEV1_MINUTES ?? 60);

interface Finding {
  code: string;
  severity: 'CRITICAL' | 'WARNING';
  detail: string;
  count: number;
}

function assertLocal(url: string): string {
  let host = '';
  try {
    host = new URL(url).hostname;
  } catch {
    host = '';
  }
  if (!host) throw new Error('URL de base de datos invalida');
  return host;
}

async function main(): Promise<void> {
  const url =
    process.env.GUARDIAN_WATCHDOG_DATABASE_URL ??
    process.env.GUARDIAN_READER_DATABASE_URL ??
    process.env.GUARDIAN_UAT_DATABASE_URL;
  if (!url) throw new Error('Falta GUARDIAN_WATCHDOG_DATABASE_URL');

  const host = assertLocal(url);
  const prisma = new PrismaClient({ datasources: { db: { url } } });
  const findings: Finding[] = [];
  const startedAt = new Date().toISOString();

  try {
    const count = async (sql: string, ...params: unknown[]): Promise<number> => {
      const rows = await prisma.$queryRawUnsafe<Array<{ n: bigint }>>(sql, ...params);
      return Number(rows[0]?.n ?? 0);
    };

    const alertsStuck = await count(
      `SELECT COUNT(*)::bigint AS n FROM "guardian_alerts"
       WHERE state = 'PENDING' AND created_at < now() - ($1 || ' minutes')::interval`,
      String(STUCK_MINUTES),
    );
    if (alertsStuck > 0) {
      findings.push({
        code: 'ALERTS_STUCK',
        severity: 'CRITICAL',
        detail: `Alertas en PENDING hace mas de ${STUCK_MINUTES} min (canal de notificacion sin avanzar).`,
        count: alertsStuck,
      });
    }

    const diagnosisStuck = await count(
      `SELECT COUNT(*)::bigint AS n FROM "guardian_diagnoses"
       WHERE status = 'PENDING' AND created_at < now() - ($1 || ' minutes')::interval`,
      String(STUCK_MINUTES),
    );
    if (diagnosisStuck > 0) {
      findings.push({
        code: 'DIAGNOSIS_STUCK',
        severity: 'CRITICAL',
        detail: `Diagnosticos en PENDING hace mas de ${STUCK_MINUTES} min (worker de IA detenido).`,
        count: diagnosisStuck,
      });
    }

    const incidentsStuck = await count(
      `SELECT COUNT(*)::bigint AS n FROM "guardian_incidents"
       WHERE processing_state NOT IN ('DIAGNOSED', 'SKIPPED')
         AND next_diagnosis_at < now() - ($1 || ' minutes')::interval`,
      String(STUCK_MINUTES),
    );
    if (incidentsStuck > 0) {
      findings.push({
        code: 'INCIDENTS_UNPROCESSED',
        severity: 'WARNING',
        detail: `Incidentes sin procesar cuya proxima ejecucion vencio hace mas de ${STUCK_MINUTES} min.`,
        count: incidentsStuck,
      });
    }

    const alertFailures = await count(
      `SELECT COUNT(*)::bigint AS n FROM "guardian_alerts"
       WHERE state = 'PENDING' AND last_error IS NOT NULL
         AND updated_at < now() - ($1 || ' minutes')::interval`,
      String(STUCK_MINUTES),
    );
    if (alertFailures > 0) {
      findings.push({
        code: 'ALERT_PROVIDER_FAILING',
        severity: 'WARNING',
        detail: 'Alertas con error de proveedor que no progresan (revisar credenciales del canal).',
        count: alertFailures,
      });
    }

    const sev1Unack = await count(
      `SELECT COUNT(*)::bigint AS n FROM "guardian_incidents"
       WHERE severity = 'SEV1' AND status = 'OPEN' AND acknowledged_at IS NULL
         AND occurred_at < now() - ($1 || ' minutes')::interval`,
      String(SEV1_UNACK_MINUTES),
    );
    if (sev1Unack > 0) {
      findings.push({
        code: 'SEV1_UNACKNOWLEDGED',
        severity: 'CRITICAL',
        detail: `Incidentes SEV1 sin reconocer hace mas de ${SEV1_UNACK_MINUTES} min.`,
        count: sev1Unack,
      });
    }

    const report = {
      watchdog: 'guardian-watchdog',
      startedAt,
      databaseHost: host,
      stuckMinutes: STUCK_MINUTES,
      sev1UnackMinutes: SEV1_UNACK_MINUTES,
      healthy: findings.length === 0,
      findings,
    };
    console.log(JSON.stringify(report, null, 2));

    const webhook = process.env.GUARDIAN_WATCHDOG_WEBHOOK_URL;
    if (findings.length > 0 && webhook) {
      try {
        const response = await fetch(webhook, {
          method: 'POST',
          headers: {
            'content-type': 'application/json',
            ...(process.env.GUARDIAN_WATCHDOG_WEBHOOK_TOKEN
              ? { authorization: `Bearer ${process.env.GUARDIAN_WATCHDOG_WEBHOOK_TOKEN}` }
              : {}),
          },
          body: JSON.stringify(report),
        });
        console.log(`webhook enviado: HTTP ${response.status}`);
      } catch (error) {
        console.error('webhook fallido:', (error as Error).message);
      }
    }

    if (findings.length > 0) process.exitCode = 2;
  } finally {
    await prisma.$disconnect();
  }
}

main().catch((error) => {
  console.error('watchdog error:', error);
  process.exit(1);
});
