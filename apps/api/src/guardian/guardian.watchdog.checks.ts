/**
 * APPYRA Guardian AI — lógica del watchdog independiente.
 *
 * Este módulo es PURO a propósito: no importa Prisma ni ningún servicio de
 * `src/guardian`, de modo que puede probarse sin base de datos y el watchdog
 * sigue funcionando aunque Guardian, sus workers o su IA estén caídos.
 */

export type WatchdogSeverity = 'CRITICAL' | 'WARNING';

export type WatchdogFinding = {
  code: string;
  severity: WatchdogSeverity;
  detail: string;
  count: number;
};

export type StaleWorker = { workerName: string; ageMinutes: number };

/** Estado de un worker según la antigüedad de su latido. */
export type WorkerHeartbeatStatus = 'ok' | 'stale' | 'missing';

/**
 * Clasifica el latido de un worker. Es puro y compartido por el watchdog y el
 * panel de plataforma para que ambos no discrepen al informar del mismo estado.
 *
 * - `missing`: no hay latido registrado (el worker nunca arrancó o se borró).
 * - `stale`: el último latido supera el umbral configurado.
 * - `ok`: latido dentro del umbral.
 */
export function classifyWorkerHeartbeat(
  ageMinutes: number | null | undefined,
  staleMinutes: number,
): WorkerHeartbeatStatus {
  if (ageMinutes === null || ageMinutes === undefined || !Number.isFinite(ageMinutes)) {
    return 'missing';
  }
  const threshold = Number.isFinite(staleMinutes) && staleMinutes > 0 ? staleMinutes : 10;
  return ageMinutes > threshold ? 'stale' : 'ok';
}

export type WatchdogSnapshot = {
  /** false cuando la consulta a PostgreSQL falló. */
  databaseReachable: boolean;
  databaseError?: string | null;
  stuckMinutes: number;
  sev1UnackMinutes: number;
  heartbeatStaleMinutes: number;
  alertsPendingStuck: number;
  diagnosesPendingStuck: number;
  incidentsUnprocessed: number;
  alertProviderFailures: number;
  sev1Unacknowledged: number;
  staleWorkers: StaleWorker[];
};

export const WATCHDOG_CODES = {
  databaseUnreachable: 'DATABASE_UNREACHABLE',
  alertsStuck: 'ALERTS_STUCK',
  diagnosisStuck: 'DIAGNOSIS_STUCK',
  incidentsUnprocessed: 'INCIDENTS_UNPROCESSED',
  alertProviderFailing: 'ALERT_PROVIDER_FAILING',
  sev1Unacknowledged: 'SEV1_UNACKNOWLEDGED',
  workerHeartbeatStale: 'WORKER_HEARTBEAT_STALE',
  watchdogRecovered: 'WATCHDOG_RECOVERED',
} as const;

/**
 * Evalúa una foto del estado. Una base inaccesible NUNCA es un estado sano:
 * corta la evaluación y devuelve un hallazgo crítico único, porque el resto de
 * contadores no son fiables sin conexión.
 */
export function evaluateGuardianHealth(snapshot: WatchdogSnapshot): WatchdogFinding[] {
  if (!snapshot.databaseReachable) {
    return [
      {
        code: WATCHDOG_CODES.databaseUnreachable,
        severity: 'CRITICAL',
        detail: `No se pudo consultar PostgreSQL: ${snapshot.databaseError ?? 'error desconocido'}`,
        count: 1,
      },
    ];
  }

  const findings: WatchdogFinding[] = [];

  if (snapshot.alertsPendingStuck > 0) {
    findings.push({
      code: WATCHDOG_CODES.alertsStuck,
      severity: 'CRITICAL',
      detail: `Alertas en PENDING hace mas de ${snapshot.stuckMinutes} min (worker de alertas detenido).`,
      count: snapshot.alertsPendingStuck,
    });
  }

  if (snapshot.diagnosesPendingStuck > 0) {
    findings.push({
      code: WATCHDOG_CODES.diagnosisStuck,
      severity: 'CRITICAL',
      detail: `Diagnosticos en PENDING hace mas de ${snapshot.stuckMinutes} min (worker de IA detenido).`,
      count: snapshot.diagnosesPendingStuck,
    });
  }

  if (snapshot.incidentsUnprocessed > 0) {
    findings.push({
      code: WATCHDOG_CODES.incidentsUnprocessed,
      severity: 'WARNING',
      detail: `Incidentes sin procesar cuya proxima ejecucion vencio hace mas de ${snapshot.stuckMinutes} min.`,
      count: snapshot.incidentsUnprocessed,
    });
  }

  if (snapshot.alertProviderFailures > 0) {
    findings.push({
      code: WATCHDOG_CODES.alertProviderFailing,
      severity: 'WARNING',
      detail: 'Alertas con error de proveedor que no progresan (revisar credenciales del canal).',
      count: snapshot.alertProviderFailures,
    });
  }

  if (snapshot.sev1Unacknowledged > 0) {
    findings.push({
      code: WATCHDOG_CODES.sev1Unacknowledged,
      severity: 'CRITICAL',
      detail: `Incidentes SEV1 sin reconocer hace mas de ${snapshot.sev1UnackMinutes} min.`,
      count: snapshot.sev1Unacknowledged,
    });
  }

  if (snapshot.staleWorkers.length > 0) {
    const names = snapshot.staleWorkers.map((worker) => worker.workerName).join(', ');
    findings.push({
      code: WATCHDOG_CODES.workerHeartbeatStale,
      severity: 'CRITICAL',
      detail:
        `Workers sin latido en mas de ${snapshot.heartbeatStaleMinutes} min (${names}). ` +
        'Un worker muerto con la cola vacia no se detecta por contadores: por eso se vigila el latido.',
      count: snapshot.staleWorkers.length,
    });
  }

  return findings;
}

export type WatchdogNotificationState = {
  /** Código de hallazgo -> instante ISO del último aviso enviado. */
  lastSentAt: Record<string, string>;
  /** Códigos actualmente notificados (para detectar la recuperación). */
  activeCodes: string[];
};

export const emptyWatchdogState: WatchdogNotificationState = { lastSentAt: {}, activeCodes: [] };

export type WatchdogNotificationPlan = {
  /** Hallazgos que deben avisarse en este ciclo. */
  send: WatchdogFinding[];
  /** Códigos que dejaron de ocurrir y deben avisarse como recuperados. */
  recovered: string[];
  nextState: WatchdogNotificationState;
  /** true si no hay hallazgos activos tras este ciclo. */
  healthy: boolean;
};

/**
 * Decide qué avisos enviar: evita repetir el mismo hallazgo en cada ciclo
 * (deduplicación) pero vuelve a avisar si sigue abierto pasado el intervalo,
 * y emite una notificación de recuperación cuando desaparece.
 */
export function planWatchdogNotifications(
  findings: WatchdogFinding[],
  previous: WatchdogNotificationState,
  now: Date,
  options: { reAlertMinutes: number },
): WatchdogNotificationPlan {
  const reAlertMs = Math.max(1, options.reAlertMinutes) * 60_000;
  const currentCodes = findings.map((finding) => finding.code);
  const send: WatchdogFinding[] = [];
  const lastSentAt: Record<string, string> = { ...previous.lastSentAt };

  for (const finding of findings) {
    const previousSent = previous.lastSentAt[finding.code];
    const previousMs = previousSent ? Date.parse(previousSent) : Number.NaN;
    const dueAgain = !Number.isFinite(previousMs) || now.getTime() - previousMs >= reAlertMs;
    if (dueAgain) {
      send.push(finding);
      lastSentAt[finding.code] = now.toISOString();
    }
  }

  const recovered = previous.activeCodes.filter((code) => !currentCodes.includes(code));

  // Solo se conserva el historial de códigos que siguen activos: si un hallazgo
  // desaparece, su marca de tiempo se descarta para que un rebrote avise de nuevo.
  const prunedLastSentAt: Record<string, string> = {};
  for (const code of currentCodes) {
    if (lastSentAt[code]) prunedLastSentAt[code] = lastSentAt[code];
  }

  return {
    send,
    recovered,
    nextState: { lastSentAt: prunedLastSentAt, activeCodes: currentCodes },
    healthy: findings.length === 0,
  };
}
