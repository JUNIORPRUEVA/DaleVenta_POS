import type {
  EcfLine,
  EcfTaxCategory,
  EcfTotals,
} from "../fiscal-core/ecf-fiscal-document";
import { dec, money, sumMoney, type EcfDecimalInput } from "../fiscal-core/ecf-money";
import type { EcfSaleSnapshot, EcfSaleSnapshotLine } from "../pos/ecf-sale-adapter";
import { fiscalFailure, type EcfFiscalResult } from "../pos/ecf-sale-fiscal.policy";

export type EcfRefundKind = "TOTAL" | "PARTIAL";

export type EcfCreditLineRequest = {
  /** 1-based, igual que en el comprobante original. */
  lineNumber: number;
  quantity: string | number;
};

/** Tasa del contrato por categoría; idéntica a la del mapeador de ventas. */
function rateFor(category: EcfTaxCategory) {
  if (category === "ITBIS_18") return 0.18;
  if (category === "ITBIS_16") return 0.16;
  return 0;
}

/**
 * Importe neto de una línea, con la MISMA aritmética que el validador fiscal
 * (`cantidad × unitPrice − descuento`, redondeado a 2 decimales). Reproducirla
 * aquí garantiza que el documento generado pase la validación sin duplicar la
 * regla: el validador sigue siendo la autoridad.
 */
function lineNet(line: {
  quantity: EcfDecimalInput;
  unitPrice: EcfDecimalInput;
  discountAmount?: EcfDecimalInput;
}) {
  return money(
    dec(line.quantity).mul(line.unitPrice).minus(line.discountAmount ?? 0),
  );
}

/** Totales calculados exactamente como los comprueba el validador. */
export function totalsForLines(lines: EcfLine[]): EcfTotals {
  const net = lines.map(lineNet);
  const subtotal = sumMoney(net);
  const taxableBase = sumMoney(
    lines.map((line, index) =>
      line.taxCategory === "EXEMPT" || line.taxCategory === "NON_BILLABLE"
        ? 0
        : net[index],
    ),
  );
  const exemptAmount = sumMoney(
    lines.map((line, index) => (line.taxCategory === "EXEMPT" ? net[index] : 0)),
  );
  const discountAmount = sumMoney(lines.map((line) => line.discountAmount ?? 0));
  const itbisAmount = sumMoney(
    lines.map((line, index) => money(net[index].mul(line.taxRate))),
  );
  return {
    subtotal: subtotal.toFixed(2),
    taxableBase: taxableBase.toFixed(2),
    exemptAmount: exemptAmount.toFixed(2),
    discountAmount: discountAmount.toFixed(2),
    itbisAmount: itbisAmount.toFixed(2),
    total: subtotal.plus(itbisAmount).toFixed(2),
  };
}

/**
 * Construye las líneas de una nota de crédito a partir de las líneas
 * AUTORITATIVAS del comprobante original.
 *
 * La clasificación fiscal (bien/servicio, categoría de impuesto) NUNCA la elige
 * el cliente: se copia del original. El cliente solo decide QUÉ se acredita.
 */
export function buildCreditLines(input: {
  originalLines: EcfSaleSnapshotLine[];
  refundKind: EcfRefundKind;
  requested?: EcfCreditLineRequest[];
}): EcfFiscalResult<{ lines: EcfLine[]; totals: EcfTotals }> {
  if (input.originalLines.length === 0) {
    return fiscalFailure(
      "ECF_CREDIT_ORIGINAL_HAS_NO_LINES",
      "El comprobante original no tiene líneas acreditables.",
    );
  }

  if (input.refundKind === "TOTAL") {
    // Nota total: se acredita íntegramente lo facturado, línea por línea.
    const lines: EcfLine[] = input.originalLines.map((line, index) => ({
      lineNumber: index + 1,
      name: line.name,
      goodServiceIndicator: line.goodServiceIndicator,
      quantity: line.quantity,
      unitPrice: line.unitPrice,
      discountAmount: line.discountAmount ?? 0,
      taxCategory: line.taxCategory,
      taxRate: rateFor(line.taxCategory),
    }));
    return { ok: true, value: { lines, totals: totalsForLines(lines) } };
  }

  const requested = input.requested ?? [];
  if (requested.length === 0) {
    return fiscalFailure(
      "ECF_CREDIT_LINES_REQUIRED",
      "Una nota parcial debe indicar qué líneas y cantidades se acreditan.",
    );
  }

  const seen = new Set<number>();
  const lines: EcfLine[] = [];
  for (const request of requested) {
    const original = input.originalLines[request.lineNumber - 1];
    if (!original) {
      return fiscalFailure(
        "ECF_CREDIT_LINE_NOT_FOUND",
        `La línea ${request.lineNumber} no existe en el comprobante original.`,
      );
    }
    if (seen.has(request.lineNumber)) {
      return fiscalFailure(
        "ECF_CREDIT_LINE_DUPLICATED",
        `La línea ${request.lineNumber} aparece más de una vez.`,
      );
    }
    seen.add(request.lineNumber);

    const originalQty = dec(original.quantity);
    const requestedQty = dec(request.quantity);
    if (requestedQty.lte(0) || requestedQty.gt(originalQty)) {
      return fiscalFailure(
        "ECF_CREDIT_QUANTITY_INVALID",
        `La cantidad de la línea ${request.lineNumber} debe ser mayor que 0 y no superar la facturada (${originalQty.toFixed()}).`,
      );
    }

    // Se mantiene el precio unitario del original y se ajusta el descuento para
    // que `cantidad × unitPrice − descuento` reproduzca exactamente la parte
    // proporcional del importe facturado. Sin impuestos recalculados.
    const originalNet = lineNet(original);
    const ratio = requestedQty.div(originalQty);
    const scaledNet = originalNet.mul(ratio);
    const grossRequested = requestedQty.mul(original.unitPrice);
    const scaledDiscount = money(grossRequested.minus(scaledNet));

    lines.push({
      lineNumber: request.lineNumber,
      name: original.name,
      goodServiceIndicator: original.goodServiceIndicator,
      quantity: requestedQty.toString(),
      unitPrice: original.unitPrice,
      discountAmount: scaledDiscount.toFixed(2),
      taxCategory: original.taxCategory,
      taxRate: rateFor(original.taxCategory),
    });
  }

  const totals = totalsForLines(lines);
  if (dec(totals.total).lte(0)) {
    return fiscalFailure(
      "ECF_CREDIT_TOTAL_MUST_BE_POSITIVE",
      "El importe a acreditar debe ser mayor que cero.",
    );
  }
  return { ok: true, value: { lines, totals } };
}

/** Importe total del original, según sus líneas autoritativas. */
export function originalNetTotal(original: EcfSaleSnapshot): string {
  const asLines = original.lines.map((line, index) => ({
    lineNumber: index + 1,
    name: line.name,
    goodServiceIndicator: line.goodServiceIndicator,
    quantity: line.quantity,
    unitPrice: line.unitPrice,
    discountAmount: line.discountAmount ?? 0,
    taxCategory: line.taxCategory,
    taxRate: rateFor(line.taxCategory),
  }));
  return String(totalsForLines(asLines).total);
}
