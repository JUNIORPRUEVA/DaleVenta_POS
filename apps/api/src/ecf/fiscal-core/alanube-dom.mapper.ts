import type { EcfFiscalDocument, EcfLine, EcfTaxCategory } from "./ecf-fiscal-document";
import { alanubeKindFor, type AlanubeBillingIndicator, type AlanubeDomMapping,
  type AlanubeDomPayloadDraft, type EcfIssuanceMetadata, validateAlanubeRequestConformance } from "./alanube-dom.contract";
import { dec, money, moneyNumber, sumMoney } from "./ecf-money";
import { validateEcfDocument } from "./ecf-validator";
import { ALANUBE_OFFICIAL_REQUIRED_FIELDS } from "../alanube/alanube-official-required-fields";

export function mapEcfToAlanubeDom(document: EcfFiscalDocument, metadata?: EcfIssuanceMetadata): AlanubeDomMapping {
  const validation = validateEcfDocument(document);
  if (!validation.ok) throw new Error(`Documento e-CF inválido: ${validation.errors.map((e) => e.code).join(", ")}`);
  if (document.currency !== "DOP" || document.lines.some((line) => line.taxCategory === "NON_BILLABLE")) {
    throw new Error("ECF_ALANUBE_UNSUPPORTED_CURRENCY_OR_NON_BILLABLE");
  }
  if (metadata?.encf && !new RegExp(`^${document.type}\\d{10}$`).test(metadata.encf)) {
    throw new Error("ECF_ALANUBE_ENCF_TYPE_MISMATCH");
  }
  const payload: AlanubeDomPayloadDraft = {
    ...(metadata?.alanubeCompanyId !== undefined ? { company: { id: metadata.alanubeCompanyId } } : {}),
    idDoc: {
      ...(metadata ? { encf: metadata.encf, paymentType: metadata.paymentType } : {}),
      ...(document.type === "E31" && metadata?.sequenceDueDate !== undefined ? { sequenceDueDate: metadata.sequenceDueDate } : {}),
      ...(metadata?.incomeType !== undefined ? { incomeType: metadata.incomeType } : {}),
      ...(document.type === "E34" && metadata?.creditNoteIndicator !== undefined ? { creditNoteIndicator: metadata.creditNoteIndicator } : {}),
      ...(metadata?.paymentDeadline !== undefined ? { paymentDeadline: metadata.paymentDeadline } : {}),
    },
    sender: {
      rnc: document.sender.taxId, companyName: document.sender.legalName,
      stampDate: document.issueDate,
      ...(document.sender.address !== undefined ? { address: document.sender.address } : {}),
      ...(document.sender.tradeName !== undefined ? { tradename: document.sender.tradeName } : {}),
      ...(document.sender.email !== undefined ? { mail: document.sender.email } : {}),
    },
    ...(document.buyer ? { buyer: {
      ...(document.buyer.taxId !== undefined ? { rnc: document.buyer.taxId } : {}),
      ...(document.buyer.legalName !== undefined ? { companyName: document.buyer.legalName } : {}),
      ...(document.buyer.address !== undefined ? { address: document.buyer.address } : {}),
      ...(document.buyer.email !== undefined ? { mail: document.buyer.email } : {}),
    } } : {}),
    totals: mapTotals(document),
    itemDetails: document.lines.map(mapLine),
    ...(document.type === "E34" ? { informationReference: {
      ncfModified: document.reference?.originalENcf,
      ncfModifiedDate: document.reference?.originalIssueDate,
      ...(metadata?.modificationCode !== undefined ? { modificationCode: metadata.modificationCode } : {}),
      reasonForModification: document.reference?.modificationReason,
    } } : {}),
  };
  const schemaValidation = validateAlanubeRequestConformance(document.type, payload);
  const pendingFields = schemaValidation.errors.map((error) => `${error.path}: ${error.keyword}`);
  // Fields may be structurally valid while provider guarantees and legal rules
  // remain incomplete. Neither this status nor metadata authorizes emission.
  return { kind: alanubeKindFor(document.type), payload,
    contractStatus: schemaValidation.ok ? "CONFIRMED_PARTIAL" : "BLOCKED_PENDING_SCHEMA",
    confirmedFields: [...ALANUBE_OFFICIAL_REQUIRED_FIELDS[document.type]],
    pendingFields, warnings: ["Conformidad estructural local; no acredita aceptación Alanube/DGII ni autoriza emisión."],
    schemaValidation };
}

function mapLine(line: EcfLine) {
  const discount = money(line.discountAmount ?? 0);
  return {
    lineNumber: line.lineNumber, billingIndicator: billingIndicator(line.taxCategory),
    itemName: line.name, goodServiceIndicator: (line.goodServiceIndicator === "GOOD" ? 1 : 2) as 1 | 2,
    ...(line.description !== undefined ? { itemDescription: line.description } : {}),
    quantityItem: Number(line.quantity), unitPriceItem: moneyNumber(line.unitPrice),
    ...(discount.gt(0) ? { discountAmount: moneyNumber(discount),
      subDiscounts: [{ subDiscountRate: "$" as const, subDiscountAmount: moneyNumber(discount) }] } : {}),
    itemAmount: moneyNumber(money(dec(line.quantity).mul(line.unitPrice).minus(discount))),
  };
}

function mapTotals(document: EcfFiscalDocument): AlanubeDomPayloadDraft["totals"] {
  const result: AlanubeDomPayloadDraft["totals"] = { totalAmount: moneyNumber(document.totals.total) };
  const rates = [["ITBIS_18", 1, 18], ["ITBIS_16", 2, 16], ["ITBIS_0", 3, 0]] as const;
  let hasTaxed = false;
  for (const [category, index, rate] of rates) {
    const lines = document.lines.filter((line) => line.taxCategory === category);
    if (!lines.length) continue;
    hasTaxed = true;
    const base = sumMoney(lines.map((line) => money(dec(line.quantity).mul(line.unitPrice).minus(line.discountAmount ?? 0))));
    const tax = sumMoney(lines.map((line) => money(money(dec(line.quantity).mul(line.unitPrice).minus(line.discountAmount ?? 0)).mul(line.taxRate))));
    result[`i${index}AmountTaxed`] = moneyNumber(base);
    result[`itbisS${index}`] = rate;
    result[`itbis${index}Total`] = moneyNumber(tax);
  }
  if (hasTaxed) {
    result.totalTaxedAmount = moneyNumber(document.totals.taxableBase);
    result.itbisTotal = moneyNumber(document.totals.itbisAmount);
  }
  if (document.lines.some((line) => line.taxCategory === "EXEMPT")) result.exemptAmount = moneyNumber(document.totals.exemptAmount);
  return result;
}

function billingIndicator(category: EcfTaxCategory): AlanubeBillingIndicator {
  return category === "ITBIS_18" ? 1 : category === "ITBIS_16" ? 2 : category === "ITBIS_0" ? 3 : 4;
}
