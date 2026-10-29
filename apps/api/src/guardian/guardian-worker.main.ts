import { runGuardianWorker } from './guardian-worker.runner';

/**
 * Punto de entrada COMPILADO del worker de APPYRA Guardian AI.
 *
 * Se emite a `dist/guardian/guardian-worker.main.js` con el resto del backend,
 * así que la imagen de runtime no necesita `src/` ni ts-node:
 *
 *   node dist/guardian/guardian-worker.main.js
 *
 * Reutiliza exactamente los mismos servicios (`GuardianAlertService`,
 * `GuardianDiagnosisService`) que usa el API: no hay un segundo motor.
 */
runGuardianWorker().catch((error: unknown) => {
  // eslint-disable-next-line no-console
  console.error('[guardian-workers] fallo fatal', error);
  process.exit(1);
});
