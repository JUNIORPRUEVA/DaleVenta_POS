/**
 * Política de emisión DOSA — lo que el adaptador se NIEGA a automatizar.
 *
 * Dos reglas se codifican aquí porque son las que más daño fiscal pueden hacer
 * si se dejan "a la interpretación":
 *
 * 1. **Ningún nuevo despacho automático** de un resultado incierto. La
 *    recuperación idéntica dentro del despacho vivo tiene un contrato separado
 *    en `dosa-same-request-recovery.ts`; esta política no la autoriza.
 * 2. **La identidad fiscal pertenece a la empresa.** En TEST, el RNC emisor
 *    coincide con el de la empresa cuyas credenciales se usan; no es global.
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
 * Decisión genérica de un nuevo despacho automático: **siempre no**.
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

/** Política de tentativas lógicas; no cuenta las llamadas del replay auditado. */
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
 * En `test` el emisor debe ser el RNC de **la empresa que emite**, que es a
 * quien pertenece la API Key de prueba. El valor llega resuelto por el
 * llamador (`input.rnc` de la petición, ya acotado a la empresa autenticada):
 * **no hay ningún RNC global** que configurar, así que una empresa nueva
 * funciona sin editar variables de entorno.
 *
 * Lo que se impide sigue siendo lo importante: una emisión de prueba que declare
 * un RNC distinto del de la empresa cuyas credenciales se están usando.
 */
export function verifyFiscalIdentity(input: {
  environment: DosaFiscalEnvironment;
  senderTaxId: string | null | undefined;
  /** RNC esperado en TEST: el de la empresa, resuelto por el llamador. */
  expectedTestRnc: string | null | undefined;
}): { ok: true } | { ok: false; reason: DosaIdentityRejection } {
  const sender = normalize(input.senderTaxId);
  if (sender === null) return { ok: false, reason: "SENDER_RNC_MISSING" };

  if (input.environment === "production") return { ok: true };

  const expected = normalize(input.expectedTestRnc);
  if (expected === null) return { ok: false, reason: "TEST_RNC_NOT_CONFIGURED" };
  if (sender !== expected) return { ok: false, reason: "TEST_RNC_MISMATCH" };
  return { ok: true };
}

function normalize(value: string | null | undefined): string | null {
  if (typeof value !== "string") return null;
  const cleaned = value.replace(/[^0-9A-Za-z]/g, "").toUpperCase();
  return cleaned.length > 0 ? cleaned : null;
}
