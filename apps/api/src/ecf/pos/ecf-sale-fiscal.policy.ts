import type {
  EcfGoodServiceIndicator,
  EcfTaxCategory,
} from "../fiscal-core/ecf-fiscal-document";

// Una partida de venta solo puede caer en estas categorías: `NON_BILLABLE` no
// es un resultado posible aquí, así que se excluye del tipo para que el
// compilador impida asignarlo por descuido.
export type EcfSaleTaxCategory = Extract<
  EcfTaxCategory,
  "ITBIS_18" | "ITBIS_16" | "ITBIS_0" | "EXEMPT"
>;

/// Resultado explícito: un fallo se devuelve, nunca se sustituye por un valor
/// por defecto. Preparar un documento fiscal con datos inventados es peor que
/// bloquear la preparación.
export type EcfFiscalFailure = { ok: false; code: string; safeMessage: string };
export type EcfFiscalResult<T> = { ok: true; value: T } | EcfFiscalFailure;

export function fiscalFailure(code: string, safeMessage: string): EcfFiscalFailure {
  return { ok: false, code, safeMessage };
}

// Tasas de ITBIS que la DGII reconoce hoy. Cualquier otra se rechaza en lugar
// de aproximarse: una categoría fiscal incorrecta produce un comprobante
// fiscalmente inválido.
const RATE_TO_CATEGORY: ReadonlyArray<{ key: string; category: EcfSaleTaxCategory }> = [
  { key: "0.1800", category: "ITBIS_18" },
  { key: "0.1600", category: "ITBIS_16" },
  { key: "0.0000", category: "ITBIS_0" },
];

/// Tolerancia de conciliación entre partidas y totales, EN CÉNTIMOS.
///
/// Se compara con enteros de céntimos en lugar de flotantes: en coma flotante
/// `70.81 - 70.80` da 0.010000000000005116, que rompería una comparación exacta
/// justo en el límite. Un céntimo de diferencia es ruido de redondeo; dos ya
/// son un dato incoherente.
export const TOTALS_TOLERANCE_CENTS = 1;

export function toCents(value: string | number): number {
  const parsed = typeof value === "number" ? value : Number(value);
  if (!Number.isFinite(parsed)) return Number.NaN;
  return Math.round(parsed * 100);
}

const money = (cents: number) =>
  Number.isFinite(cents) ? (cents / 100).toFixed(2) : "NaN";

function rateKey(value: string | number): string {
  const parsed = typeof value === "number" ? value : Number(value);
  if (!Number.isFinite(parsed)) return "NaN";
  return parsed.toFixed(4);
}

/**
 * Categoría fiscal de una partida a partir de lo PERSISTIDO en la venta.
 * No se infiere nada del nombre del producto ni del precio.
 */
export function taxCategoryFor(input: {
  taxExempt: boolean;
  taxRate: string | number;
}): EcfFiscalResult<EcfSaleTaxCategory> {
  if (input.taxExempt) return { ok: true, value: "EXEMPT" };
  const key = rateKey(input.taxRate);
  const match = RATE_TO_CATEGORY.find((entry) => entry.key === key);
  if (!match) {
    return fiscalFailure(
      "ECF_UNSUPPORTED_TAX_RATE",
      `Tasa de ITBIS no soportada (${key}). Configure una tasa soportada antes de facturar electrónicamente.`,
    );
  }
  return { ok: true, value: match.category };
}

/**
 * Bien o servicio a partir de la clasificación persistida del producto.
 *
 * `Product.itemType` es la única fuente declarada. Si no se puede resolver se
 * bloquea: no se deduce por el nombre, el precio ni el inventario.
 */
export function goodServiceFor(
  itemType: string | null | undefined,
): EcfFiscalResult<EcfGoodServiceIndicator> {
  if (itemType === "PRODUCT") return { ok: true, value: "GOOD" };
  if (itemType === "SERVICE") return { ok: true, value: "SERVICE" };
  return fiscalFailure(
    "ECF_LINE_CLASSIFICATION_REQUIRED",
    "Una partida no tiene clasificación de bien o servicio. Asígnela al producto antes de facturar electrónicamente.",
  );
}

export type EcfTotalsReconciliation = {
  totals: { subtotal: string; taxableBase: string; exemptAmount: string; discountAmount: string; itbisAmount: string; total: string };
  linesSum: { taxableBase: string; exemptAmount: string; discountAmount: string; itbisAmount: string; grossAmount: string };
};

/**
 * Verifica que las partidas y los totales de la venta sean coherentes entre sí.
 *
 * Los totales autoritativos son los de la venta (los calculó el flujo de ventas).
 * Aquí NO se recalculan impuestos: solo se comprueba que no se contradigan.
 */
export function reconcileSaleTotals(input: {
  lines: ReadonlyArray<{
    grossAmount: string | number;
    lineDiscountAmount: string | number;
    taxableBase: string | number;
    exemptAmount: string | number;
    taxAmount: string | number;
  }>;
  totals: {
    taxableBase: string | number;
    exemptAmount: string | number;
    discountAmount: string | number;
    taxAmount: string | number;
    total: string | number;
  };
}): EcfFiscalResult<EcfTotalsReconciliation> {
  const sumCents = (
    pick: (line: (typeof input.lines)[number]) => string | number,
  ) => input.lines.reduce((acc, line) => acc + toCents(pick(line)), 0);

  const linesSumCents = {
    grossAmount: sumCents((line) => line.grossAmount),
    discountAmount: sumCents((line) => line.lineDiscountAmount),
    taxableBase: sumCents((line) => line.taxableBase),
    exemptAmount: sumCents((line) => line.exemptAmount),
    itbisAmount: sumCents((line) => line.taxAmount),
  };
  const taxableBaseCents = toCents(input.totals.taxableBase);
  const exemptAmountCents = toCents(input.totals.exemptAmount);
  const discountAmountCents = toCents(input.totals.discountAmount);
  const itbisCents = toCents(input.totals.taxAmount);
  const totalCents = toCents(input.totals.total);
  const expectedTotalCents =
    linesSumCents.taxableBase +
    linesSumCents.exemptAmount +
    linesSumCents.itbisAmount;

  const divergences: string[] = [];
  const close = (a: number, b: number) =>
    Math.abs(a - b) <= TOTALS_TOLERANCE_CENTS;
  if (!close(linesSumCents.taxableBase, taxableBaseCents)) divergences.push("taxableBase");
  if (!close(linesSumCents.exemptAmount, exemptAmountCents)) divergences.push("exemptAmount");
  if (!close(linesSumCents.discountAmount, discountAmountCents)) divergences.push("discountAmount");
  if (!close(linesSumCents.itbisAmount, itbisCents)) divergences.push("itbisAmount");
  if (!close(expectedTotalCents, totalCents)) divergences.push("total");

  if (divergences.length > 0) {
    return fiscalFailure(
      "ECF_SALE_TOTALS_MISMATCH",
      `Las partidas y los totales de la venta no son coherentes (${divergences.join(", ")}).`,
    );
  }

  return {
    ok: true,
    value: {
      totals: {
        subtotal: money(taxableBaseCents + exemptAmountCents),
        taxableBase: money(taxableBaseCents),
        exemptAmount: money(exemptAmountCents),
        discountAmount: money(discountAmountCents),
        itbisAmount: money(itbisCents),
        total: money(totalCents),
      },
      linesSum: {
        grossAmount: money(linesSumCents.grossAmount),
        discountAmount: money(linesSumCents.discountAmount),
        taxableBase: money(linesSumCents.taxableBase),
        exemptAmount: money(linesSumCents.exemptAmount),
        itbisAmount: money(linesSumCents.itbisAmount),
      },
    },
  };
}

export type EcfSaleEligibility = {
  isDeleted: boolean;
  cancelledAt: Date | string | null;
  refundedSaleId: string | null;
  itemCount: number;
};

/** Elegibilidad de una venta para convertirse en comprobante electrónico. */
export function assertSaleEligible(
  sale: EcfSaleEligibility,
): EcfFiscalResult<true> {
  if (sale.isDeleted) {
    return fiscalFailure("ECF_SALE_DELETED", "La venta está eliminada.");
  }
  if (sale.cancelledAt) {
    return fiscalFailure("ECF_SALE_CANCELLED", "La venta está anulada.");
  }
  if (sale.refundedSaleId) {
    // Las devoluciones se documentan como nota de crédito (E34) sobre su
    // comprobante original, no como comprobante nuevo.
    return fiscalFailure(
      "ECF_SALE_IS_REFUND",
      "La venta es una devolución: debe documentarse como nota de crédito sobre el comprobante original.",
    );
  }
  if (sale.itemCount <= 0) {
    return fiscalFailure("ECF_SALE_HAS_NO_ITEMS", "La venta no tiene partidas.");
  }
  return { ok: true, value: true };
}

/** Datos fiscales obligatorios del emisor (instantáneas persistidas en la venta). */
export function assertIssuerComplete(input: {
  legalName?: string | null;
  taxId?: string | null;
  address?: string | null;
}): EcfFiscalResult<true> {
  const missing: string[] = [];
  if (!input.legalName?.trim()) missing.push("nombre");
  if (!input.taxId?.trim()) missing.push("RNC");
  if (!input.address?.trim()) missing.push("dirección");
  if (missing.length > 0) {
    return fiscalFailure(
      "ECF_ISSUER_DATA_INCOMPLETE",
      `Faltan datos fiscales del emisor: ${missing.join(", ")}.`,
    );
  }
  return { ok: true, value: true };
}

/**
 * Datos fiscales del receptor.
 *
 * E31 (crédito fiscal) EXIGE identificar al receptor. E32 (consumidor final)
 * puede emitirse sin RNC.
 */
export function assertBuyerForDocumentType(
  documentType: "E31" | "E32",
  buyer: { taxId?: string | null; legalName?: string | null },
): EcfFiscalResult<true> {
  if (documentType === "E32") return { ok: true, value: true };
  const missing: string[] = [];
  if (!buyer.taxId?.trim()) missing.push("RNC o cédula del cliente");
  if (!buyer.legalName?.trim()) missing.push("razón social del cliente");
  if (missing.length > 0) {
    return fiscalFailure(
      "ECF_BUYER_DATA_REQUIRED",
      `E31 exige identificar al receptor. Falta: ${missing.join(", ")}.`,
    );
  }
  return { ok: true, value: true };
}
