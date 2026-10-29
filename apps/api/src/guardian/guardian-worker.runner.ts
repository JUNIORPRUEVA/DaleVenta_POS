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

  // Supervisión propia (fase 12). Ver el comentario dentro de `tick()`.
  const maxConsecutiveFailures = Math.max(
    2,
    Number(process.env.GUARDIAN_WORKER_MAX_FAILED_CYCLES ?? 3),
  );
  const cycleTimeoutMs = Math.max(
    15_000,
    Number(process.env.GUARDIAN_WORKER_CYCLE_TIMEOUT_SECONDS ?? 120) * 1_000,
  );
  let consecutiveFailures = 0;

  // Latido real: el watchdog independiente no puede distinguir "sin trabajo" de
  // "proceso muerto" solo con contadores, así que cada worker deja su marca.
  // Devuelve `true` solo si el latido se persistió: es la señal de vida que usa
  // el autoguardado (ver `tick()`), porque los servicios de dominio capturan sus
  // propios errores y no siempre propagan un fallo de base de datos.
  let heartbeatCycle = 0;
  const beat = async (workerName: string, processedLastCycle: number): Promise<boolean> => {
    heartbeatCycle += 1;
    try {
      await prisma.guardianWorkerHeartbeat.upsert({
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
      });
      return true;
    } catch (error: unknown) {
      logger.warn(
        `latido ${workerName} no registrado: ${error instanceof Error ? error.message : String(error)}`,
      );
      return false;
    }
  };

  const tick = async () => {
    if (running || stopping) return;
    running = true;
    // Si un ciclo se queda colgado (conexión a medio abrir, driver bloqueado),
    // el healthcheck solo marcaría "unhealthy" sin reiniciar nada. Este tope
    // duro devuelve el proceso a Swarm para que lo levante de nuevo.
    const stallGuard = setTimeout(() => {
      logger.error(`ciclo bloqueado más de ${cycleTimeoutMs} ms: se reinicia el proceso`);
      process.exit(1);
    }, cycleTimeoutMs);
    try {
      const alertOutcome = await alerts.processDue(10).catch((error: unknown) => {
        logger.error(`Alertas: ${error instanceof Error ? error.message : String(error)}`);
        return null;
      });
      const diagnosisOutcome = await diagnosis.runBatch(5).catch((error: unknown) => {
        logger.error(`Diagnóstico: ${error instanceof Error ? error.message : String(error)}`);
        return null;
      });

      // Autoguardado (fase 12): un healthcheck en rojo NO reinicia el contenedor
      // en Swarm. La señal de vida fiable es el LATIDO persistido: si no se
      // puede escribir, el worker está inútil aunque el proceso siga vivo. Tras
      // varios ciclos seguidos sin latido se sale con código != 0 para que la
      // política `--restart-condition any` lo levante de nuevo.
      // No se considera fallo "processed=0": con Guardian desactivado es normal.
      const beatAlerts = await beat('alerts', alertOutcome?.processed ?? 0);
      const beatDiagnosis = await beat('diagnosis', diagnosisOutcome?.processed ?? 0);

      if (!beatAlerts && !beatDiagnosis) {
        consecutiveFailures += 1;
        logger.warn(
          `latido no persistido (${consecutiveFailures}/${maxConsecutiveFailures})`,
        );
        if (consecutiveFailures >= maxConsecutiveFailures) {
          logger.error('worker sin latido: se reinicia el proceso para recuperar el servicio');
          clearInterval(timer);
          await app.close().catch(() => undefined);
          process.exit(1);
        }
      } else {
        consecutiveFailures = 0;
      }

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
      clearTimeout(stallGuard);
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
