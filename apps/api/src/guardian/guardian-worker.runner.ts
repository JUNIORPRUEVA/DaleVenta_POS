import { Logger } from '@nestjs/common';
import { NestFactory } from '@nestjs/core';
import { hostname } from 'node:os';

import { AppModule } from '../app.module';
import { PrismaService } from '../prisma/prisma.service';
import { GuardianAlertService } from './guardian.alert.service';
import { GuardianDiagnosisService } from './guardian.diagnosis.service';

/**
 * APPYRA Guardian AI — bucle de workers.
 *
 * Vive en `src/` (no en `scripts/`) para que `tsc -p tsconfig.build.json` lo
 * emita a `dist/` y el proceso pueda arrancarse desde los artefactos compilados
 * de producción sin necesitar el árbol de fuentes ni ts-node:
 *
 *   node dist/guardian/guardian-worker.main.js
 *
 * Es la ÚNICA implementación del bucle: el script histórico
 * (`scripts/guardian/guardian-workers.ts`, usado por `npm run guardian:workers`
 * en desarrollo) ahora delega aquí, así que no hay dos motores de diagnóstico.
 *
 * Nunca atiende tráfico comercial: se ejecuta como proceso aparte del API para
 * que el diagnóstico IA y el envío de alertas no compitan con ventas/caja.
 */
export async function runGuardianWorker(): Promise<void> {
  const logger = new Logger('GuardianWorkers');
  const app = await NestFactory.createApplicationContext(AppModule, {
    logger: ['error', 'warn', 'log'],
  });

  const alerts = app.get(GuardianAlertService);
  const diagnosis = app.get(GuardianDiagnosisService);
  const prisma = app.get(PrismaService);

  const intervalMs = Math.max(
    2_000,
    Number(process.env.GUARDIAN_WORKER_INTERVAL_SECONDS ?? 5) * 1_000,
  );
  let running = false;
  let stopping = false;

  // Latido real: el watchdog independiente no puede distinguir "sin trabajo" de
  // "proceso muerto" solo con contadores, así que cada worker deja su marca.
  let heartbeatCycle = 0;
  const beat = async (workerName: string, processedLastCycle: number) => {
    heartbeatCycle += 1;
    await prisma.guardianWorkerHeartbeat
      .upsert({
        where: { workerName },
        create: {
          workerName,
          lastSeenAt: new Date(),
          cycleCount: BigInt(1),
          processedLastCycle,
          host: hostname(),
          pid: process.pid,
        },
        update: {
          lastSeenAt: new Date(),
          cycleCount: { increment: 1 },
          processedLastCycle,
          host: hostname(),
          pid: process.pid,
        },
      })
      .catch((error: unknown) => {
        logger.warn(
          `latido ${workerName} no registrado: ${error instanceof Error ? error.message : String(error)}`,
        );
      });
  };

  const tick = async () => {
    if (running || stopping) return;
    running = true;
    try {
      const alertOutcome = await alerts.processDue(10).catch((error: unknown) => {
        logger.error(`Alertas: ${error instanceof Error ? error.message : String(error)}`);
        return null;
      });
      const diagnosisOutcome = await diagnosis.runBatch(5).catch((error: unknown) => {
        logger.error(`Diagnóstico: ${error instanceof Error ? error.message : String(error)}`);
        return null;
      });

      await beat('alerts', alertOutcome?.processed ?? 0);
      await beat('diagnosis', diagnosisOutcome?.processed ?? 0);

      if (
        alertOutcome &&
        (alertOutcome.processed > 0 || alertOutcome.failed > 0 || (alertOutcome.deferred ?? 0) > 0)
      ) {
        logger.log(
          `alertas procesadas=${alertOutcome.processed} enviadas=${alertOutcome.sent} fallidas=${alertOutcome.failed} esperando-diagnostico=${alertOutcome.deferred ?? 0}`,
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

  const timer = setInterval(() => void tick(), intervalMs);
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
