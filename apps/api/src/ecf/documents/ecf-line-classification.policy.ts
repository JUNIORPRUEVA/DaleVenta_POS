import { ECF_LINE_CLASSIFICATION_MESSAGES } from "./ecf-line-classification.messages";

/**
 * Clasificación fiscal SUPERVISADA de una partida (F1) — política pura.
 *
 * Gobierna una única decisión: si un usuario autorizado puede dejar constancia
 * de si una partida sin producto es un BIEN o un SERVICIO, para que una venta que
 * hoy es imposible de facturar electrónicamente pueda serlo.
 *
 * Tres invariantes que esta política existe para proteger:
 *
 *  1. **No se adivina.** Solo `PRODUCT` o `SERVICE`; nunca se infiere del nombre.
 *  2. **No se reescribe nada.** La decisión es un hecho nuevo y fechado; la venta
 *     y su `SaleItem` no se tocan.
 *  3. **Después de salir del equipo, no se clasifica.** Si el comprobante ya se
 *     envió o está en revisión humana, admitir una clasificación nueva cambiaría
 *     el significado de algo que ya está fuera: se rechaza.
 */

export const ECF_LINE_CLASSIFICATIONS = ["PRODUCT", "SERVICE"] as const;
export type EcfLineClassificationDecision =
  (typeof ECF_LINE_CLASSIFICATIONS)[number];

/**
 * Estados en los que el comprobante YA salió del equipo o está resuelto.
 *
 * Se enumeran los estados FISCALES, no los locales: `LOCAL_DRAFT`,
 * `LOCAL_VALIDATION_PENDING`, `LOCAL_VALIDATED` y `CANCELLED` quedan fuera a
 * propósito, porque en ellos el comprobante todavía no ha salido y corregir la
 * clasificación es legítimo.
 */
export const ECF_FISCALLY_FROZEN_STATUSES = [
  "READY_TO_SEND",
  "SEND_PENDING",
  "SEND_IN_PROGRESS",
  "UNKNOWN_RESULT",
  "PROVIDER_ACCEPTED",
  "PROVIDER_REJECTED",
  "DGII_STATUS_PENDING",
  "DGII_ACCEPTED",
  "DGII_REJECTED",
  "HUMAN_REVIEW_REQUIRED",
] as const;

export type EcfLineClassificationRefusal = {
  code: string;
  message: string;
};

/** `true` si algún comprobante de la venta ya salió del equipo. */
export function isFiscallyFrozen(statuses: readonly string[]): boolean {
  return statuses.some((status) =>
    (ECF_FISCALLY_FROZEN_STATUSES as readonly string[]).includes(status),
  );
}

export function lineClassificationRefusal(input: {
  classification: string;
  reason: string;
  documentStatuses: readonly string[];
  /** Valor confirmado más reciente para esta partida, si existe. */
  currentClassification?: string | null;
}): EcfLineClassificationRefusal | null {
  const classification = input.classification?.trim().toUpperCase() ?? "";
  if (!(ECF_LINE_CLASSIFICATIONS as readonly string[]).includes(classification)) {
    return {
      code: "ECF_LINE_CLASSIFICATION_UNKNOWN",
      message: ECF_LINE_CLASSIFICATION_MESSAGES.unknown,
    };
  }

  const reason = input.reason?.trim() ?? "";
  if (reason.length < 3 || reason.length > 300) {
    return {
      code: "ECF_LINE_CLASSIFICATION_REASON_REQUIRED",
      message: ECF_LINE_CLASSIFICATION_MESSAGES.reasonRequired,
    };
  }

  // El orden importa: primero lo irreversible. Un comprobante que ya salió no
  // admite clasificación nueva ni aunque coincida con la anterior.
  if (isFiscallyFrozen(input.documentStatuses)) {
    return {
      code: "ECF_LINE_CLASSIFICATION_FISCALLY_FROZEN",
      message: ECF_LINE_CLASSIFICATION_MESSAGES.fiscallyFrozen,
    };
  }

  if (
    input.currentClassification != null &&
    input.currentClassification === classification
  ) {
    return {
      code: "ECF_LINE_CLASSIFICATION_UNCHANGED",
      message: ECF_LINE_CLASSIFICATION_MESSAGES.unchanged,
    };
  }

  return null;
}

/**
 * La clasificación congelada en la venta manda SIEMPRE.
 *
 * Si `SaleItem.item_type_snapshot` tiene valor, es la evidencia histórica de cómo
 * se emitió esa venta y una clasificación supervisada posterior no puede
 * cambiarla. Esta función hace explícita esa precedencia para que ningún camino
 * pueda invertirla por descuido.
 */
export function effectiveLineClassification(input: {
  frozenSnapshot: string | null;
  supervised: string | null;
}): string | null {
  if (input.frozenSnapshot !== null && input.frozenSnapshot !== "") {
    return input.frozenSnapshot;
  }
  return input.supervised ?? null;
}
