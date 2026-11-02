import {
  DOSA_SIGNATURE_CONTRACT_PENDING,
  DOSA_SIGNATURE_HEADER,
  DOSA_WEBHOOK_CONTRACT_STATUS,
} from "./dosa-webhook.contract";

/**
 * Resultado de verificar la autenticidad de un evento.
 *
 * No existe un caso "válido" mientras el contrato esté bloqueado: el tipo sí lo
 * admite para no reescribir la interfaz cuando DOSA entregue la fórmula, pero la
 * implementación actual NUNCA puede producir `ok: true`.
 */
export type DosaSignatureVerdict =
  | { ok: true }
  | { ok: false; reason: DosaSignatureRejection };

export type DosaSignatureRejection =
  | "SIGNATURE_HEADER_MISSING"
  | "SIGNATURE_CONTRACT_UNRESOLVED"
  | "RAW_BODY_UNAVAILABLE";

/**
 * Verificación de `X-Dosa-Signature`.
 *
 * Falla SIEMPRE cerrado por diseño: mientras
 * `DOSA_WEBHOOK_CONTRACT_STATUS` no sea `READY` no hay algoritmo que aplicar, y
 * aplicar uno inventado convertiría un evento no verificado en uno "auténtico".
 *
 * No se implementa HMAC, ni comparación de tiempos, ni normalización del cuerpo:
 * nada de eso está especificado por el proveedor todavía.
 */
export function verifyDosaSignature(input: {
  headers: Record<string, string | string[] | undefined>;
  rawBody: Buffer | string | undefined;
}): DosaSignatureVerdict {
  if (headerValue(input.headers, DOSA_SIGNATURE_HEADER) === null) {
    return { ok: false, reason: "SIGNATURE_HEADER_MISSING" };
  }
  if (input.rawBody === undefined) {
    return { ok: false, reason: "RAW_BODY_UNAVAILABLE" };
  }
  if (DOSA_WEBHOOK_CONTRACT_STATUS !== "READY") {
    return { ok: false, reason: "SIGNATURE_CONTRACT_UNRESOLVED" };
  }
  // Contrato resuelto en el futuro: aquí irá el algoritmo EXACTO que entregue
  // DOSA. Hasta entonces no se escribe ninguna suposición.
  return { ok: false, reason: "SIGNATURE_CONTRACT_UNRESOLVED" };
}

/** Lo que sigue pendiente de DOSA, en el orden en que hay que pedirlo. */
export function dosaSignatureContractPending(): readonly string[] {
  return DOSA_SIGNATURE_CONTRACT_PENDING;
}

function headerValue(
  headers: Record<string, string | string[] | undefined>,
  name: string,
): string | null {
  for (const [key, value] of Object.entries(headers)) {
    if (key.toLowerCase() !== name) continue;
    if (typeof value === "string") return value.trim().length > 0 ? value.trim() : null;
    if (Array.isArray(value)) {
      const first = value.find((item) => typeof item === "string" && item.trim().length > 0);
      return first ? first.trim() : null;
    }
    return null;
  }
  return null;
}
