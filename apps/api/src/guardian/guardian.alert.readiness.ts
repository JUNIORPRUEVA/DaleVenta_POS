/**
 * Regla de "alert readiness": ¿puede enviarse ya la alerta administrativa?
 *
 * Objetivo (Fase 4): que el diagnóstico real de la IA llegue al mensaje de
 * WhatsApp sin bloquear los incidentes críticos.
 *
 * Regla:
 * - **SEV1** → siempre listo (no se espera a la IA). Un incidente crítico no
 *   puede quedarse sin aviso porque el proveedor de IA esté lento o caído.
 * - **SEV2 / SEV3** → se espera al diagnóstico hasta un plazo configurable
 *   (`GUARDIAN_ALERT_DIAGNOSIS_WAIT_SECONDS`). Se envía en cuanto el diagnóstico
 *   está `DONE`, o al vencer el plazo con texto de respaldo.
 * - **SEV4** → no genera alerta (solo se registra), igual que antes.
 *
 * Este módulo es puro: sin base de datos, sin red, sin Nest. La consulta Prisma
 * de `claimDue` se construye con las mismas constantes para que no puedan
 * divergir, y estas funciones se prueban de forma determinista.
 */

export const ALERT_DIAGNOSIS_WAIT_SEVERITIES = ['SEV2', 'SEV3'] as const;
export const ALERT_IMMEDIATE_SEVERITY = 'SEV1';

export type AlertReadinessReason =
  | 'SEV1_IMMEDIATE'
  | 'DIAGNOSIS_DONE'
  | 'DEADLINE_REACHED'
  | 'WAIT_DISABLED'
  | 'AWAITING_DIAGNOSIS';

export type AlertReadinessInput = {
  /** `SEV1`..`SEV4` (o el valor que llegue del incidente). */
  severity: string;
  /** Momento en que el incidente entró en Guardian. */
  receivedAt: Date;
  /** Estado del diagnóstico más reciente, o `null` si aún no existe. */
  diagnosisStatus: 'PENDING' | 'RUNNING' | 'DONE' | 'FAILED' | null;
  now: Date;
  /** Segundos de espera configurados (0 = sin espera). */
  waitSeconds: number;
};

export type AlertReadiness = {
  ready: boolean;
  reason: AlertReadinessReason;
  /** Momento a partir del cual se envía aunque no haya diagnóstico. */
  deadlineAt: Date | null;
};

/** Plazo de espera del diagnóstico, o `null` si no aplica. */
export function diagnosisDeadline(input: {
  receivedAt: Date;
  waitSeconds: number;
}): Date | null {
  const waitSeconds = Math.max(0, Math.trunc(input.waitSeconds));
  if (waitSeconds <= 0) return null;
  return new Date(input.receivedAt.getTime() + waitSeconds * 1000);
}

export function resolveAlertReadiness(input: AlertReadinessInput): AlertReadiness {
  const waitSeconds = Math.max(0, Math.trunc(input.waitSeconds));

  // Crítico: nunca se espera a la IA.
  if (input.severity === ALERT_IMMEDIATE_SEVERITY) {
    return { ready: true, reason: 'SEV1_IMMEDIATE', deadlineAt: null };
  }

  // Sin espera configurada: comportamiento previo (envío inmediato).
  if (waitSeconds <= 0) {
    return { ready: true, reason: 'WAIT_DISABLED', deadlineAt: null };
  }

  const deadlineAt = diagnosisDeadline({ receivedAt: input.receivedAt, waitSeconds });

  if (input.diagnosisStatus === 'DONE') {
    return { ready: true, reason: 'DIAGNOSIS_DONE', deadlineAt };
  }

  if (deadlineAt && input.now.getTime() >= deadlineAt.getTime()) {
    // La IA falló, agotó presupuesto o sigue sin terminar: se envía con respaldo.
    return { ready: true, reason: 'DEADLINE_REACHED', deadlineAt };
  }

  return { ready: false, reason: 'AWAITING_DIAGNOSIS', deadlineAt };
}

/**
 * Texto de respaldo de la posición 6 de la plantilla cuando no hay diagnóstico.
 * Coincide con el usado por `buildGuardianAlertTemplateParams`.
 */
export const ALERT_DIAGNOSIS_FALLBACK_TEXT = 'Información pendiente de confirmar.';
