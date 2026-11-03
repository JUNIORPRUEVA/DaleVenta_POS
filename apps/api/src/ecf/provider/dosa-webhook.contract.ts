/**
 * Contrato del webhook de DOSA.
 *
 * ESTADO: **BLOQUEADO**. El proveedor confirmó que existe una cabecera
 * `X-Dosa-Signature` y entregó un secreto, pero **no** la fórmula de
 * validación: ni algoritmo, ni qué bytes se firman, ni si hay marca de tiempo,
 * ni codificación del valor.
 *
 * Por eso este módulo NO valida autenticidad. Solo describe la forma mínima que
 * se puede comprobar sin inventar nada y deja constancia explícita de lo que
 * falta. Cualquier intento de "resolverlo" con un HMAC supuesto sería peor que
 * no tener webhook: daría una falsa sensación de autenticidad.
 */

/** Interruptor único de autenticidad del webhook. */
export type DosaWebhookContractStatus =
  | "BLOCKED_PENDING_OFFICIAL_SIGNATURE_CONTRACT"
  | "READY";

export const DOSA_WEBHOOK_CONTRACT_STATUS: DosaWebhookContractStatus =
  "BLOCKED_PENDING_OFFICIAL_SIGNATURE_CONTRACT";

/** Cabecera que el proveedor nombró. No se asume nada más sobre ella. */
export const DOSA_SIGNATURE_HEADER = "x-dosa-signature";

/**
 * Lo que el contrato debe responder ANTES de escribir una sola línea de
 * verificación real. Se deja aquí, en código, para que el bloqueo sea visible y
 * no se pierda en una conversación.
 */
export const DOSA_SIGNATURE_CONTRACT_PENDING = [
  "Algoritmo exacto (HMAC-SHA256 y variantes NO se asumen).",
  "Qué se firma exactamente: cuerpo crudo, cuerpo normalizado o un resumen.",
  "Si la marca de tiempo entra en el cálculo y con qué formato.",
  "Codificación del valor de la cabecera (hex, base64, prefijo de versión).",
  "Ventana de tolerancia anti-replay aceptada por el proveedor.",
  "Si el secreto es por empresa, por entorno o compartido por partner.",
] as const;

/**
 * Forma mínima y NO autenticada de un evento.
 *
 * `payload` se conserva como `unknown`: no se modela el cuerpo del proveedor
 * porque todavía no hay contrato escrito, y modelarlo mal sería inventar.
 */
export type DosaWebhookEnvelope = {
  /** Identificador del evento, si el proveedor lo envía. Sirve para deduplicar. */
  eventId: string | null;
  /** Tipo declarado del evento, si viene. */
  eventType: string | null;
  /** Cuerpo original sin interpretar. */
  payload: unknown;
};

export type DosaWebhookEnvelopeResult =
  | { ok: true; envelope: DosaWebhookEnvelope }
  | { ok: false; reason: string };

/**
 * Validación ESTRUCTURAL del sobre. Deliberadamente débil: no dice si el evento
 * es auténtico, solo si tiene forma de objeto JSON.
 */
export function readDosaWebhookEnvelope(value: unknown): DosaWebhookEnvelopeResult {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    return { ok: false, reason: "INVALID_OBJECT" };
  }
  const record = value as Record<string, unknown>;
  return {
    ok: true,
    envelope: {
      eventId: asNonEmptyString(record.eventId ?? record.event_id),
      eventType: asNonEmptyString(record.eventType ?? record.event_type ?? record.type),
      payload: value,
    },
  };
}

function asNonEmptyString(value: unknown): string | null {
  return typeof value === "string" && value.trim().length > 0 ? value.trim() : null;
}
