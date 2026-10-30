/**
 * Regla de motivo para las decisiones que devuelven el expediente al cliente.
 *
 * Una solicitud de corrección o un rechazo **sin motivo** no es auditable y deja
 * al cliente sin saber qué arreglar. Esta regla es pura para poder probarla sin
 * base de datos y aplicarla igual desde cualquier ruta.
 */
export const ECF_DGII_REASON_REQUIRED_STATES = [
  "REQUIRES_CORRECTION",
  "REJECTED",
] as const;

export type EcfDgiiReasonRequiredState =
  (typeof ECF_DGII_REASON_REQUIRED_STATES)[number];

export function requiresCorrectionReason(state?: string | null): boolean {
  if (!state) return false;
  return (ECF_DGII_REASON_REQUIRED_STATES as readonly string[]).includes(state);
}

/**
 * Devuelve el código de rechazo, o `null` si la operación es válida.
 *
 * Se acepta el motivo entrante **o** uno ya registrado en el expediente: no se
 * obliga a repetir una explicación que ya existe.
 */
export function correctionReasonRefusal(input: {
  nextState?: string | null;
  incomingReason?: string | null;
  existingReason?: string | null;
}): string | null {
  if (!requiresCorrectionReason(input.nextState)) return null;
  const incoming = input.incomingReason?.trim() ?? "";
  const existing = input.existingReason?.trim() ?? "";
  if (incoming.length === 0 && existing.length === 0) {
    return "ECF_DGII_CORRECTION_REASON_REQUIRED";
  }
  return null;
}
