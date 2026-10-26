/**
 * APPYRA Guardian AI — workers en proceso aislado.
 *
 * No atiende tráfico comercial: se ejecuta como proceso aparte del API para que
 * el diagnóstico IA y el envío de alertas nunca compitan con ventas/caja.
 *
 *   npm --workspace apps/api run guardian:workers
 *
 * Variables relevantes:
 *   GUARDIAN_DIAGNOSIS_ENABLED, GUARDIAN_ALERTS_ENABLED, GUARDIAN_ALERT_RECIPIENT
 *   GUARDIAN_WORKER_INTERVAL_SECONDS (default 5)
 *   GUARDIAN_WA_CLOUD_TOKEN / GUARDIAN_WA_PHONE_NUMBER_ID (canal oficial)
 *   GUARDIAN_ALERT_FALLBACK_WEBHOOK_URL (canal de respaldo independiente)
 */
import { NestFactory } from '@nestjs/core';
import { Logger } from '@nestjs/common';
import { AppModule } from '../../src/app.module';
import { GuardianAlertService } from '../../src/guardian/guardian.alert.service';
import { GuardianDiagnosisService } from '../../src/guardian/guardian.diagnosis.service';

async function main() {
  const logger = new Logger('GuardianWorkers');
  const app = await NestFactory.createApplicationContext(AppModule, {
    logger: ['error', 'warn', 'log'],
  });

  const alerts = app.get(GuardianAlertService);
  const diagnosis = app.get(GuardianDiagnosisService);

  const intervalMs = Math.max(2_000, Number(process.env.GUARDIAN_WORKER_INTERVAL_SECONDS ?? 5) * 1_000);
  let running = false;
  let stopping = false;

  const tick = async () => {
    if (running || stopping) return;
    running = true;
    try {
      const alertOutcome = await alerts.processDue(10).catch((error) => {
        logger.error(`Alertas: ${error instanceof Error ? error.message : String(error)}`);
        return null;
      });
      const diagnosisOutcome = await diagnosis.runBatch(5).catch((error) => {
        logger.error(`Diagnóstico: ${error instanceof Error ? error.message : String(error)}`);
        return null;
      });

      if (alertOutcome && (alertOutcome.processed > 0 || alertOutcome.failed > 0)) {
        logger.log(
          `alertas procesadas=${alertOutcome.processed} enviadas=${alertOutcome.sent} fallidas=${alertOutcome.failed}`,
        );
      }
      if (diagnosisOutcome && diagnosisOutcome.processed > 0) {
        logger.log(
          `diagnósticos procesados=${diagnosisOutcome.processed} ok=${diagnosisOutcome.diagnosed} fallidos=${diagnosisOutcome.failed}`,
        );
      }
    } finally {
      running = false;
    }
  };

  const timer = setInterval(tick, intervalMs);
  logger.log(`Workers Guardian iniciados (intervalo ${intervalMs} ms)`);
  await tick();

  const shutdown = async (signal: string) => {
    if (stopping) return;
    stopping = true;
    logger.log(`Señal ${signal}: cerrando workers Guardian`);
    clearInterval(timer);
    await app.close();
    process.exit(0);
  };

  process.on('SIGINT', () => void shutdown('SIGINT'));
  process.on('SIGTERM', () => void shutdown('SIGTERM'));
}

main().catch((error) => {
  // eslint-disable-next-line no-console
  console.error('[guardian-workers] fallo fatal', error);
  process.exit(1);
});
