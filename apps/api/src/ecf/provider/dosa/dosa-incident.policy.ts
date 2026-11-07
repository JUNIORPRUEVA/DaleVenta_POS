/**
 * Política de incidencias del flujo DOSA. Funciones puras.
 *
 * Qué resuelve este archivo: hasta hoy un evento que quedaba en
 * `PENDING_CREDENTIALS` o `CONFLICT_PENDING_REVIEW` solo se veía mirando la
 * base a mano. Aquí se decide, sin acceso a datos, **qué** es una incidencia,
 * **cuánto** pesa, **si** se puede reintentar sola y **cuándo** toca el
 * siguiente intento.
 *
 * Reglas que NO se negocian:
 *
 * 1. **Nada de secretos.** Una incidencia identifica empresa, RNC, postulación
 *    y tipo de problema. Nunca una clave, un secreto ni el cuerpo del evento.
 * 2. **Reintento automático solo de operaciones internas idempotentes.** Un
 *    conflicto de identidad, una rotación sospechosa o una credencial inválida
 *    son actos humanos: reintentarlas podría sustituir material vigente o
 *    esconder un ataque.
 * 3. **Backoff con techo y límite de intentos.** Sin límite, un evento
 *    irrecuperable se reintentaría para siempre.
 */

/** Tipos de incidencia. Cada uno tiene una causa y una salida distintas. */
export const DOSA_INCIDENT_KINDS = [
  /** El evento llegó autenticado pero las credenciales no se pudieron guardar. */
  "EVENT_CREDENTIALS_NOT_STORED",
  /** Llegaron credenciales que NO coinciden con las vigentes: rotación a revisar. */
  "CREDENTIAL_CONFLICT_REVIEW",
  /** Hay credenciales guardadas esperando confirmación humana. */
  "CREDENTIAL_AWAITING_CONFIRMATION",
  /** El evento tiene `postulacion_id` pero la sesión activa no quedó vinculada. */
  "POSTULATION_NOT_BOUND",
  /** El evento se guardó sin tipo confirmado (`PENDING_CLASSIFICATION`). */
  "EVENT_TYPE_UNKNOWN",
] as const;

export type DosaIncidentKind = (typeof DOSA_INCIDENT_KINDS)[number];

export type DosaIncidentSeverity = "ALTA" | "MEDIA" | "BAJA";

/**
 * Solo estas incidencias se reintentan solas.
 *
 * `POSTULATION_NOT_BOUND` reejecuta `bindProviderPostulation`, cuya propia
 * consulta exige intento activo, no sobrescribe un identificador confirmado y
 * no acepta uno de otra empresa. Es idempotente por construcción.
 *
 * Todo lo demás es humano a propósito: `EVENT_CREDENTIALS_NOT_STORED` no puede
 * resolverse desde aquí porque **no guardamos los secretos** (solo la huella
 * del cuerpo); la única recuperación real es que DOSA reenvíe el evento, y eso
 * ya lo contempla la reanudación por deduplicación.
 */
const RETRYABLE_KINDS: ReadonlySet<DosaIncidentKind> = new Set<DosaIncidentKind>([
  "POSTULATION_NOT_BOUND",
]);

export function isRetryableIncident(kind: DosaIncidentKind): boolean {
  return RETRYABLE_KINDS.has(kind);
}

const SEVERITY_BY_KIND: Record<DosaIncidentKind, DosaIncidentSeverity> = {
  // Un conflicto puede significar que alguien intenta rotar credenciales sin
  // autorización: es lo más alto de la lista.
  CREDENTIAL_CONFLICT_REVIEW: "ALTA",
  // Hay una entrega del proveedor que no se pudo materializar: la empresa no
  // podrá operar hasta que se resuelva.
  EVENT_CREDENTIALS_NOT_STORED: "ALTA",
  CREDENTIAL_AWAITING_CONFIRMATION: "MEDIA",
  POSTULATION_NOT_BOUND: "BAJA",
  EVENT_TYPE_UNKNOWN: "BAJA",
};

export function severityOfIncident(kind: DosaIncidentKind): DosaIncidentSeverity {
  return SEVERITY_BY_KIND[kind];
}

/** Descripción legible para el panel. Sin datos sensibles. */
const DESCRIPTION_BY_KIND: Record<DosaIncidentKind, string> = {
  EVENT_CREDENTIALS_NOT_STORED:
    "Un evento autenticado de DOSA no pudo guardar las credenciales de la empresa.",
  CREDENTIAL_CONFLICT_REVIEW:
    "DOSA envió credenciales distintas a las vigentes. Requiere revisión antes de rotar.",
  CREDENTIAL_AWAITING_CONFIRMATION:
    "Hay credenciales recibidas pendientes de confirmación. No se activan solas.",
  POSTULATION_NOT_BOUND:
    "El evento tiene postulación pero la sesión activa de la empresa no quedó vinculada.",
  EVENT_TYPE_UNKNOWN:
    "El evento está guardado sin tipo confirmado porque DOSA no envía el campo de tipo.",
};

export function describeIncidentKind(kind: DosaIncidentKind): string {
  return DESCRIPTION_BY_KIND[kind];
}

/**
 * Clave de deduplicación de una incidencia.
 *
 * Determinista **y estable**: el mismo problema sobre el mismo sujeto produce la
 * misma clave, así que el barrido no crea filas nuevas cada 10 minutos. Cuando
 * el sujeto cambia (otro evento, otra postulación) es una incidencia distinta y
 * merece su propia alerta.
 */
export function incidentKeyOf(input: {
  kind: DosaIncidentKind;
  subjectRef?: string | null;
}): string {
  const subject = normalizeSubject(input.subjectRef);
  return subject ? `${input.kind}:${subject}` : input.kind;
}

function normalizeSubject(value: string | null | undefined): string {
  return String(value ?? "").trim().toLowerCase().slice(0, 96);
}

/** Ventana mínima entre alertas de la misma incidencia (milisegundos). */
export const DOSA_INCIDENT_MIN_ALERT_INTERVAL_MS = 6 * 60 * 60 * 1000;

/** Intentos automáticos máximos antes de escalar a revisión humana. */
export const DOSA_INCIDENT_MAX_ATTEMPTS = 6;

/** Backoff exponencial: 5 min, 10, 20, 40, 80, 160… con techo de 6 h. */
export function backoffDelayMs(attempt: number): number {
  const base = 5 * 60 * 1000;
  const cap = 6 * 60 * 60 * 1000;
  const safeAttempt = Number.isFinite(attempt) ? Math.max(1, Math.floor(attempt)) : 1;
  return Math.min(base * 2 ** (safeAttempt - 1), cap);
}

/**
 * ¿Toca actuar ahora?
 *
 * `attempts` es el número de intentos **ya realizados**. Sin `nextAttemptAt`
 * (incidencia recién detectada) siempre toca.
 */
export function isDue(input: {
  attempts: number;
  nextAttemptAt: Date | null;
  now: Date;
}): boolean {
  if (!input.nextAttemptAt) return true;
  return input.nextAttemptAt.getTime() <= input.now.getTime();
}

/** Estado persistido de una incidencia. */
export const DOSA_INCIDENT_STATUS = {
  /** Detectada, sin resolver. */
  OPEN: "OPEN",
  /** Se agotaron los intentos automáticos: la revisa una persona. */
  ESCALATED: "ESCALATED",
  /** La condición desapareció por sí sola (p. ej. DOSA reenvió el evento). */
  RESOLVED: "RESOLVED",
  /** Una persona la cerró con un motivo. */
  CLOSED: "CLOSED",
} as const;

export type DosaIncidentStatus =
  (typeof DOSA_INCIDENT_STATUS)[keyof typeof DOSA_INCIDENT_STATUS];

/** Estados que ya no se tocan en el barrido. */
export function isTerminalIncidentStatus(status: string): boolean {
  return (
    status === DOSA_INCIDENT_STATUS.RESOLVED ||
    status === DOSA_INCIDENT_STATUS.CLOSED
  );
}

/**
 * Motivos de cierre admitidos por la ruta administrativa.
 *
 * Lista cerrada a propósito: cerrar una incidencia es una afirmación auditable,
 * así que se elige de un catálogo y no se escribe texto libre en un campo que
 * luego se lee como si fuera un estado.
 */
export const DOSA_INCIDENT_RESOLUTIONS = [
  "PROVIDER_RESENT_EVENT",
  "CREDENTIALS_CONFIRMED_BY_ADMIN",
  "ROTATION_AUTHORIZED",
  "FALSE_POSITIVE",
  "COMPANY_DISABLED",
] as const;

export type DosaIncidentResolution = (typeof DOSA_INCIDENT_RESOLUTIONS)[number];

export function isDosaIncidentResolution(value: unknown): value is DosaIncidentResolution {
  return (
    typeof value === "string" &&
    (DOSA_INCIDENT_RESOLUTIONS as readonly string[]).includes(value)
  );
}
