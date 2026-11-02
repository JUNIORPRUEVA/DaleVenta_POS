/**
 * Política de INTENTOS de certificación.
 *
 * La regla que protege el dinero y el trámite: **una operación que escribe no se
 * reenvía si no se sabe si la anterior se aplicó**. Un timeout, una caída del
 * backend o un 5xx dejan el intento en estado incierto y obligan a reconciliar.
 *
 * Se reutiliza `EcfCertificationAttempt` tal como existe (sin migración): el
 * estado incierto se representa con `status = IN_PROGRESS` +
 * `errorCode = ECF_PROVIDER_RESULT_UNKNOWN`, que es distinguible de un
 * `IN_PROGRESS` normal precisamente por ese código.
 */

/** Código que marca «resultado desconocido»: exige reconciliación. */
export const ECF_ATTEMPT_UNCERTAIN_CODE = "ECF_PROVIDER_RESULT_UNKNOWN";

/** Estados persistidos de `EcfCertificationAttempt` que esta política entiende. */
export type EcfAttemptSnapshot = {
  status: string;
  errorCode: string | null;
  /** Antigüedad del intento, en milisegundos, calculada por el llamador. */
  ageMs: number;
};

export type EcfAttemptDecision =
  /** No había intento: se puede crear y ejecutar. */
  | { action: "PROCEED" }
  /** Ya se completó: se devuelve el resultado anterior, sin repetir la llamada. */
  | { action: "RETURN_SUCCESS" }
  /** Falló de forma definitiva y es reintentable: se puede volver a intentar. */
  | { action: "RETRY" }
  /** Hay otro intento en curso: no se duplica. */
  | { action: "BLOCK_IN_FLIGHT"; code: string }
  /** No se sabe si se aplicó: prohibido reenviar hasta reconciliar. */
  | { action: "BLOCK_UNCERTAIN"; code: string };

/** Marca de un intento cuyo resultado se desconoce. */
export function isUncertain(attempt: EcfAttemptSnapshot): boolean {
  return attempt.errorCode === ECF_ATTEMPT_UNCERTAIN_CODE;
}

export function decideAttempt(input: {
  attempt: EcfAttemptSnapshot | null;
  now: Date;
  /** A partir de aquí un intento «en curso» se considera abandonado. */
  staleAfterMs: number;
  /** Si el fallo anterior fue definitivo y reintentable. */
  retryableFailure?: boolean;
}): EcfAttemptDecision {
  const attempt = input.attempt;
  if (!attempt) return { action: "PROCEED" };

  // 1. Éxito previo: nunca se repite una operación ya aplicada.
  if (attempt.status === "SUCCEEDED") return { action: "RETURN_SUCCESS" };

  // 2. Resultado desconocido: reconciliar antes de cualquier reintento.
  if (isUncertain(attempt)) {
    return { action: "BLOCK_UNCERTAIN", code: ECF_ATTEMPT_UNCERTAIN_CODE };
  }

  // 3. Bloqueo administrativo explícito.
  if (attempt.status === "BLOCKED") {
    return { action: "BLOCK_UNCERTAIN", code: attempt.errorCode ?? "ECF_ATTEMPT_BLOCKED" };
  }

  // 4. Fallo definitivo: solo se reintenta si la causa era reintentable.
  if (attempt.status === "FAILED") {
    return input.retryableFailure === false
      ? { action: "BLOCK_UNCERTAIN", code: attempt.errorCode ?? "ECF_ATTEMPT_FAILED" }
      : { action: "RETRY" };
  }

  // 5. En curso: se espera, salvo que esté abandonado… y entonces tampoco se
  //    reenvía, porque pudo haberse aplicado antes de la caída.
  if (attempt.status === "IN_PROGRESS" || attempt.status === "REGISTERED") {
    if (attempt.ageMs >= input.staleAfterMs) {
      return { action: "BLOCK_UNCERTAIN", code: ECF_ATTEMPT_STALE_CODE };
    }
    return { action: "BLOCK_IN_FLIGHT", code: "ECF_ATTEMPT_IN_FLIGHT" };
  }

  // Estado desconocido: falla cerrado.
  return { action: "BLOCK_UNCERTAIN", code: "ECF_ATTEMPT_STATE_UNKNOWN" };
}

export const ECF_ATTEMPT_STALE_CODE = "ECF_ATTEMPT_STALE_IN_FLIGHT";

/**
 * Clave de idempotencia de una operación.
 *
 * Determinista y estable entre reinicios: la misma operación lógica produce la
 * misma clave, así que un reintento del usuario cae en el MISMO intento.
 */
export function certificationIdempotencyKey(input: {
  operation: string;
  companyId: string;
  /** Distingue intentos legítimamente distintos (p. ej. retryNumber del set). */
  discriminator?: string | number;
}): string {
  const suffix =
    input.discriminator === undefined ? "" : `:${String(input.discriminator)}`;
  return `${input.operation}:${input.companyId}${suffix}`.slice(0, 128);
}
