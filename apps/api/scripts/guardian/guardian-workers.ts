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
import { runGuardianWorker } from '../../src/guardian/guardian-worker.runner';

/**
 * Shim de desarrollo de los workers de APPYRA Guardian AI.
 *
 * La ÚNICA implementación del bucle vive en
 * `src/guardian/guardian-worker.runner.ts` y se compila a `dist/`, de modo que
 * en producción se arranca el artefacto compilado (sin `src/` ni ts-node):
 *
 *   node dist/guardian/guardian-worker.main.js
 *
 * Este script sólo la invoca, para que `npm --workspace apps/api run
 * guardian:workers` siga funcionando en desarrollo sin duplicar la lógica.
 */
runGuardianWorker().catch((error: unknown) => {
  // eslint-disable-next-line no-console
  console.error('[guardian-workers] fallo fatal', error);
  process.exit(1);
});

