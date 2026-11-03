/**
 * Política de emisión DOSA — lo que el adaptador se NIEGA a automatizar.
 *
 * Dos reglas se codifican aquí porque son las que más daño fiscal pueden hacer
 * si se dejan "a la interpretación":
 *
 * 1. **Ningún reintento automático** de un comprobante cuyo resultado es
 *    incierto. Reenviar a ciegas puede duplicar un comprobante o consumir dos
 *    secuencias. La reconciliación es un acto humano con evidencia.
 * 2. **La identidad fiscal de prueba no se mezcla con la real.** En entorno de
 *    pruebas, el RNC emisor debe ser exactamente el RNC de prueba configurado,
 *    de modo que el RNC real de la empresa no pueda usarse en un flujo de test.
 */

export type DosaFiscalEnvironment = "test" | "production";

/** Desenlace de un intento de emisión, tal como se puede observar. */
export type DosaEmissionOutcome =
  | { kind: "NOT_SENT" }
  | { kind: "UNKNOWN" }
  | { kind: "REJECTED"; codes: readonly string[] }
  | { kind: "IN_PROCESS" }
  | { kind: "ACCEPTED" };

export type DosaRetryDecision =
  | { allowed: false; reason: string }
  | { allowed: true; reason: string };

/**
 * Decisión de reintento automático. Hoy y en esta fase: **siempre no**.
 *
 * El tipo admite `allowed: true` para no reescribir la interfaz, pero esta
 * implementación nunca lo devuelve; hay una prueba que lo verifica para todos
 * los desenlaces posibles.
 */
export function mayRetryAutomatically(_outcome: DosaEmissionOutcome): DosaRetryDecision {
  return {
    allowed: false,
    reason:
      "ECF_DOSA_NO_AUTOMATIC_RETRY: un resultado incierto no se reenvia solo; " +
      "requiere reconciliacion con evidencia.",
  };
}

/** Constantes visibles para la revisión de seguridad. */
export const DOSA_RETRY_POLICY = {
  maxAttemptsPerDocument: 1,
  retryOnUnknown: false,
  retryOnTimeout: false,
  retryOnRejected: false,
  requiresHumanReconciliationOnUnknown: true,
} as const;

export type DosaIdentityRejection =
  | "TEST_RNC_NOT_CONFIGURED"
  | "TEST_RNC_MISMATCH"
  | "SENDER_RNC_MISSING";

/**
 * Comprueba que la identidad fiscal usada corresponde al entorno.
 *
 * En `test` el emisor debe ser el RNC de prueba que entregó DOSA. Esto es lo que
 * impide que una prueba acabe declarando el RNC real de la empresa y obtenga un
 * comprobante con validez fiscal.
 */
export function verifyFiscalIdentity(input: {
  environment: DosaFiscalEnvironment;
  senderTaxId: string | null | undefined;
  configuredTestRnc: string | null | undefined;
}): { ok: true } | { ok: false; reason: DosaIdentityRejection } {
  const sender = normalize(input.senderTaxId);
  if (sender === null) return { ok: false, reason: "SENDER_RNC_MISSING" };

  if (input.environment === "production") return { ok: true };

  const testRnc = normalize(input.configuredTestRnc);
  if (testRnc === null) return { ok: false, reason: "TEST_RNC_NOT_CONFIGURED" };
  if (sender !== testRnc) return { ok: false, reason: "TEST_RNC_MISMATCH" };
  return { ok: true };
}

function normalize(value: string | null | undefined): string | null {
  if (typeof value !== "string") return null;
  const cleaned = value.replace(/[^0-9A-Za-z]/g, "").toUpperCase();
  return cleaned.length > 0 ? cleaned : null;
}
