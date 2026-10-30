import {
  type EcfFiscalDocument,
  type EcfLine,
  type EcfValidationError,
  type EcfValidationResult,
} from "./ecf-fiscal-document";
import { Prisma } from "@prisma/client";
import { dec, isSameMoney, money, sumMoney } from "./ecf-money";

const RNC_OR_CEDULA = /^\d{9,11}$/;
const ISO_DATE = /^\d{4}-\d{2}-\d{2}$/;

export function validateEcfDocument(document: EcfFiscalDocument): EcfValidationResult {
  const errors: EcfValidationError[] = [];
  const add = (error: EcfValidationError) => errors.push(error);

  if (document.unsupportedFields && Object.keys(document.unsupportedFields).length) {
    add({
      code: "ECF_UNSUPPORTED_DOCUMENT_FIELDS",
      field: "unsupportedFields",
      category: "UNSUPPORTED",
      message: "El documento contiene campos no soportados por el núcleo fiscal local.",
    });
  }

  if (!["E31", "E32", "E34"].includes(document.type)) {
    add({
      code: "ECF_UNSUPPORTED_TYPE",
      field: "type",
      category: "UNSUPPORTED",
      message: "Tipo e-CF no soportado por el núcleo local.",
    });
  }
  if (!ISO_DATE.test(document.issueDate)) {
    add({
      code: "ECF_INVALID_ISSUE_DATE",
      field: "issueDate",
      category: "STRUCTURE",
      message: "La fecha de emisión debe estar en formato YYYY-MM-DD.",
    });
  }
  validateSender(document, add);
  validateBuyer(document, add);
  validateLines(document.lines, add);
  validateTotals(document, add);
  validateReference(document, add);

  return { ok: errors.length === 0, errors };
}

function validateSender(
  document: EcfFiscalDocument,
  add: (error: EcfValidationError) => void,
) {
  if (!document.sender?.legalName?.trim()) {
    add({
      code: "ECF_SENDER_NAME_REQUIRED",
      field: "sender.legalName",
      category: "MISSING_FIELD",
      message: "El emisor requiere razón social.",
    });
  }
  if (!RNC_OR_CEDULA.test(document.sender?.taxId ?? "")) {
    add({
      code: "ECF_SENDER_TAX_ID_INVALID",
      field: "sender.taxId",
      category: "FISCAL_RULE",
      message: "El RNC/cédula del emisor debe contener entre 9 y 11 dígitos.",
    });
  }
}

function validateBuyer(
  document: EcfFiscalDocument,
  add: (error: EcfValidationError) => void,
) {
  const buyer = document.buyer;
  if (document.type === "E31") {
    if (!buyer?.legalName?.trim()) {
      add({
        code: "ECF_BUYER_NAME_REQUIRED_E31",
        field: "buyer.legalName",
        category: "MISSING_FIELD",
        message: "E31 requiere receptor identificado.",
      });
    }
    if (!RNC_OR_CEDULA.test(buyer?.taxId ?? "")) {
      add({
        code: "ECF_BUYER_TAX_ID_REQUIRED_E31",
        field: "buyer.taxId",
        category: "FISCAL_RULE",
        message: "E31 requiere RNC/cédula del receptor.",
      });
    }
  }
  if (document.type === "E32" && money(document.totals.total).gte(250000)) {
    if (!buyer?.legalName?.trim() || !RNC_OR_CEDULA.test(buyer?.taxId ?? "")) {
      add({
        code: "ECF_BUYER_REQUIRED_E32_THRESHOLD",
        field: "buyer",
        category: "FISCAL_RULE",
        message: "E32 con total mayor o igual a DOP 250,000 requiere comprador.",
      });
    }
  }
  if (buyer?.taxId && !RNC_OR_CEDULA.test(buyer.taxId)) {
    add({
      code: "ECF_BUYER_TAX_ID_INVALID",
      field: "buyer.taxId",
      category: "FISCAL_RULE",
      message: "El RNC/cédula del comprador debe contener entre 9 y 11 dígitos.",
    });
  }
}

function validateLines(lines: EcfLine[], add: (error: EcfValidationError) => void) {
  if (!Array.isArray(lines) || lines.length === 0) {
    add({
      code: "ECF_LINES_REQUIRED",
      field: "lines",
      category: "MISSING_FIELD",
      message: "El documento requiere al menos una línea.",
    });
    return;
  }
  lines.forEach((line, index) => {
    const prefix = `lines.${index}`;
    if (line.unsupportedFields && Object.keys(line.unsupportedFields).length) {
      add({
        code: "ECF_UNSUPPORTED_LINE_FIELDS",
        field: `${prefix}.unsupportedFields`,
        category: "UNSUPPORTED",
        message: "La línea contiene campos no soportados por el núcleo fiscal local.",
      });
    }
    if (!Number.isInteger(line.lineNumber) || line.lineNumber < 1) {
      add({
        code: "ECF_LINE_NUMBER_INVALID",
        field: `${prefix}.lineNumber`,
        category: "STRUCTURE",
        message: "El número de línea debe ser entero positivo.",
      });
    }
    if (!line.name?.trim() || line.name.length > 80) {
      add({
        code: "ECF_LINE_NAME_INVALID",
        field: `${prefix}.name`,
        category: "STRUCTURE",
        message: "El nombre del ítem es requerido y no debe superar 80 caracteres.",
      });
    }
    if (dec(line.quantity).lte(0)) {
      add({
        code: "ECF_LINE_QUANTITY_INVALID",
        field: `${prefix}.quantity`,
        category: "STRUCTURE",
        message: "La cantidad debe ser mayor que cero.",
      });
    }
    if (money(line.unitPrice).lt(0)) {
      add({
        code: "ECF_LINE_UNIT_PRICE_INVALID",
        field: `${prefix}.unitPrice`,
        category: "STRUCTURE",
        message: "El precio unitario no puede ser negativo.",
      });
    }
    const gross = money(dec(line.quantity).mul(line.unitPrice));
    const discount = money(line.discountAmount ?? 0);
    if (discount.lt(0) || discount.gt(gross)) {
      add({
        code: "ECF_LINE_DISCOUNT_INVALID",
        field: `${prefix}.discountAmount`,
        category: "MONEY_CONSISTENCY",
        message: "El descuento de línea no puede ser negativo ni superar el bruto.",
      });
    }
    if (line.taxCategory === "EXEMPT" && !dec(line.taxRate).isZero()) {
      add({
        code: "ECF_EXEMPT_TAX_RATE_INVALID",
        field: `${prefix}.taxRate`,
        category: "FISCAL_RULE",
        message: "Una línea exenta debe tener tasa de ITBIS cero.",
      });
    }
  });
}

function validateTotals(
  document: EcfFiscalDocument,
  add: (error: EcfValidationError) => void,
) {
  const lineNet = document.lines.map((line) =>
    money(dec(line.quantity).mul(line.unitPrice).minus(line.discountAmount ?? 0)),
  );
  const subtotal = sumMoney(lineNet);
  const taxableBase = sumMoney(
    document.lines.map((line, index) =>
      line.taxCategory === "EXEMPT" || line.taxCategory === "NON_BILLABLE"
        ? 0
        : lineNet[index],
    ),
  );
  const exemptAmount = sumMoney(
    document.lines.map((line, index) => (line.taxCategory === "EXEMPT" ? lineNet[index] : 0)),
  );
  const discountAmount = sumMoney(document.lines.map((line) => line.discountAmount ?? 0));
  const itbisAmount = sumMoney(
    document.lines.map((line, index) => money(lineNet[index].mul(line.taxRate))),
  );
  const total = money(subtotal.plus(itbisAmount));
  const checks: Array<[keyof EcfFiscalDocument["totals"], Prisma.Decimal, string]> = [
    ["subtotal", subtotal, "ECF_TOTAL_SUBTOTAL_MISMATCH"],
    ["taxableBase", taxableBase, "ECF_TOTAL_TAXABLE_BASE_MISMATCH"],
    ["exemptAmount", exemptAmount, "ECF_TOTAL_EXEMPT_MISMATCH"],
    ["discountAmount", discountAmount, "ECF_TOTAL_DISCOUNT_MISMATCH"],
    ["itbisAmount", itbisAmount, "ECF_TOTAL_ITBIS_MISMATCH"],
    ["total", total, "ECF_TOTAL_AMOUNT_MISMATCH"],
  ];
  for (const [field, expected, code] of checks) {
    if (!isSameMoney(document.totals[field], expected)) {
      add({
        code,
        field: `totals.${field}`,
        category: "MONEY_CONSISTENCY",
        message: `Total inconsistente. Esperado ${expected.toFixed(2)}.`,
      });
    }
  }
}

function validateReference(
  document: EcfFiscalDocument,
  add: (error: EcfValidationError) => void,
) {
  if (document.type !== "E34") return;
  if (!document.reference?.originalENcf?.trim()) {
    add({
      code: "ECF_CREDIT_NOTE_REFERENCE_REQUIRED",
      field: "reference.originalENcf",
      category: "MISSING_FIELD",
      message: "E34 requiere referencia al comprobante original.",
    });
  }
  if (!document.reference?.modificationReason?.trim()) {
    add({
      code: "ECF_CREDIT_NOTE_REASON_REQUIRED",
      field: "reference.modificationReason",
      category: "MISSING_FIELD",
      message: "E34 requiere motivo de modificación.",
    });
  }
}
