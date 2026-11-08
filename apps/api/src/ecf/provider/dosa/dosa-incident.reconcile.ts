/**
 * Decisión de reconciliación de incidencias DOSA. Función pura.
 *
 * El barrido hace dos cosas distintas y conviene no mezclarlas:
 *
 * 1. **Detectar** (SQL, en `dosa-incident.service.ts`) qué condiciones siguen
 *    vivas en la base.
 * 2. **Decidir** (aquí, sin E/S) qué hacer con cada una comparándola con lo que
 *    ya está registrado.
 *
 * Separarlas permite probar exhaustivamente las reglas de deduplicación,
 * backoff y escalado sin base de datos, y deja el servicio con la única
 * responsabilidad de ejecutar el plan.
 */

import {
  DOSA_INCIDENT_MAX_ATTEMPTS,
  DOSA_INCIDENT_STATUS,
  backoffDelayMs,
  incidentKeyOf,
  isDue,
  isRetryableIncident,
  severityOfIncident,
  type DosaIncidentKind,
} from "./dosa-incident.policy";

/** Condición viva detectada en la base. Sin datos sensibles. */
export type DosaIncidentCandidate = {
  companyId: string;
  rnc: string | null;
  kind: DosaIncidentKind;
  subjectType: "WEBHOOK_EVENT" | "CREDENTIAL" | "SESSION";
  /** Identificador de dominio del sujeto (evento, credencial, postulación). */
  subjectRef: string | null;
  detail?: Record<string, unknown>;
};

/** Fila ya registrada. Solo lo que la decisión necesita. */
export type DosaIncidentOpenRow = {
  id: string;
  incidentKey: string;
  kind: string;
  status: string;
  attempts: number;
  nextAttemptAt: Date | null;
};

export type DosaIncidentAction =
  /** Incidencia nueva: se registra y, si procede, se alerta. */
  | { type: "CREATE"; candidate: DosaIncidentCandidate; incidentKey: string; severity: string }
  /** Sigue viva y no toca reintentar: solo se actualiza `last_seen_at`. */
  | { type: "TOUCH"; id: string; candidate: DosaIncidentCandidate }
  /** Toca reintentar la operación interna idempotente. */
  | { type: "RETRY"; id: string; candidate: DosaIncidentCandidate }
  /** Se agotaron los intentos: pasa a revisión humana. */
  | { type: "ESCALATE"; id: string }
  /** La condición desapareció: se cierra sola. */
  | { type: "RESOLVE"; id: string };

/**
 * Plan de acciones para una empresa.
 *
 * `openRows` son solo las incidencias NO terminales de esa empresa. Si una
 * incidencia ya se resolvió y la condición vuelve, se crea una nueva: es un
 * incidente distinto y merece su propia alerta.
 */
export function planIncidentActions(input: {
  candidates: DosaIncidentCandidate[];
  openRows: DosaIncidentOpenRow[];
  now: Date;
}): DosaIncidentAction[] {
  const actions: DosaIncidentAction[] = [];

  const byKey = new Map<string, DosaIncidentOpenRow>();
  for (const row of input.openRows) byKey.set(row.incidentKey, row);

  const seenKeys = new Set<string>();

  for (const candidate of input.candidates) {
    const key = incidentKeyOf({
      kind: candidate.kind,
      subjectRef: candidate.subjectRef,
    });
    // Un candidato duplicado en el mismo barrido no se procesa dos veces.
    if (seenKeys.has(key)) continue;
    seenKeys.add(key);

    const existing = byKey.get(key);

    if (!existing) {
      actions.push({
        type: "CREATE",
        candidate,
        incidentKey: key,
        severity: severityOfIncident(candidate.kind),
      });
      continue;
    }

    const retryable = isRetryableIncident(candidate.kind);
    if (!retryable) {
      actions.push({ type: "TOUCH", id: existing.id, candidate });
      continue;
    }

    if (existing.attempts >= DOSA_INCIDENT_MAX_ATTEMPTS) {
      actions.push({ type: "ESCALATE", id: existing.id });
      continue;
    }

    if (
      isDue({
        attempts: existing.attempts,
        nextAttemptAt: existing.nextAttemptAt,
        now: input.now,
      })
    ) {
      actions.push({ type: "RETRY", id: existing.id, candidate });
      continue;
    }

    actions.push({ type: "TOUCH", id: existing.id, candidate });
  }

  for (const row of input.openRows) {
    if (seenKeys.has(row.incidentKey)) continue;
    // Una incidencia escalada no se cierra sola: espera a una persona.
    if (row.status === DOSA_INCIDENT_STATUS.ESCALATED) continue;
    actions.push({ type: "RESOLVE", id: row.id });
  }

  return actions;
}

/** Estado y agenda que deja un reintento. */
export function outcomeOfAttempt(input: {
  attempts: number;
  now: Date;
  succeeded: boolean;
  errorCode?: string | null;
}): {
  attempts: number;
  nextAttemptAt: Date | null;
  status: string;
  lastErrorCode: string | null;
} {
  const attempts = input.attempts + 1;
  if (input.succeeded) {
    return {
      attempts,
      nextAttemptAt: null,
      status: DOSA_INCIDENT_STATUS.RESOLVED,
      lastErrorCode: null,
    };
  }
  if (attempts >= DOSA_INCIDENT_MAX_ATTEMPTS) {
    return {
      attempts,
      nextAttemptAt: null,
      status: DOSA_INCIDENT_STATUS.ESCALATED,
      lastErrorCode: input.errorCode ?? "RETRY_EXHAUSTED",
    };
  }
  return {
    attempts,
    nextAttemptAt: new Date(input.now.getTime() + backoffDelayMs(attempts)),
    status: DOSA_INCIDENT_STATUS.OPEN,
    lastErrorCode: input.errorCode ?? "RETRY_FAILED",
  };
}
