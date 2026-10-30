import type { EcfDocumentType } from "./ecf-fiscal-document";
import { validateAlanubeOfficialRequest, type AlanubeSchemaResult } from "../alanube/alanube-schema-validator";

export type AlanubeDomContractStatus = "CONFIRMED_OFFICIAL" | "CONFIRMED_PARTIAL" | "BLOCKED_PENDING_SCHEMA";
export type AlanubeDomDocumentKind = "fiscal-invoices" | "invoices" | "credit-notes";
export type AlanubeBillingIndicator = 0 | 1 | 2 | 3 | 4;
export type AlanubeGoodServiceIndicator = 1 | 2;

// Explicit fiscal metadata supplied by the caller. Never allocated/defaulted here.
export type EcfIssuanceMetadata = {
  alanubeCompanyId?: string;
  encf: string;
  sequenceDueDate?: string;
  incomeType?: 1 | 2 | 3 | 4 | 5 | 6;
  paymentType: 1 | 2 | 3;
  paymentDeadline?: string;
  creditNoteIndicator?: 0 | 1;
  modificationCode?: 1 | 2 | 3 | 4;
};

export type AlanubeDomPayloadDraft = {
  company?: { id: string };
  idDoc: Partial<Pick<EcfIssuanceMetadata, "encf" | "sequenceDueDate" | "incomeType" | "paymentType" | "paymentDeadline" | "creditNoteIndicator">>;
  sender: { companyName: string; rnc: string; tradename?: string; address?: string; stampDate: string; mail?: string };
  buyer?: { companyName?: string; rnc?: string; address?: string; mail?: string };
  totals: {
    totalTaxedAmount?: number; i1AmountTaxed?: number; i2AmountTaxed?: number; i3AmountTaxed?: number;
    exemptAmount?: number; itbisS1?: number; itbisS2?: number; itbisS3?: number;
    itbisTotal?: number; itbis1Total?: number; itbis2Total?: number; itbis3Total?: number;
    totalAmount: number;
  };
  itemDetails: Array<{
    lineNumber: number; billingIndicator: AlanubeBillingIndicator; itemName: string;
    goodServiceIndicator: AlanubeGoodServiceIndicator; itemDescription?: string;
    quantityItem: number; unitPriceItem: number; discountAmount?: number;
    subDiscounts?: Array<{ subDiscountRate: "$"; subDiscountAmount: number }>;
    itemAmount: number;
  }>;
  informationReference?: {
    ncfModified?: string; ncfModifiedDate?: string; modificationCode?: 1 | 2 | 3 | 4; reasonForModification?: string;
  };
};

export type AlanubeDomMapping = {
  kind: AlanubeDomDocumentKind;
  payload: AlanubeDomPayloadDraft;
  contractStatus: AlanubeDomContractStatus;
  confirmedFields: string[];
  pendingFields: string[];
  warnings: string[];
  schemaValidation?: AlanubeSchemaResult;
};

export type AlanubeContractError = { code: string; path: string; message: string };

export function alanubeKindFor(type: EcfDocumentType): AlanubeDomDocumentKind {
  if (type === "E31") return "fiscal-invoices";
  if (type === "E32") return "invoices";
  return "credit-notes";
}

export function alanubeTypeFor(kind: unknown): EcfDocumentType | undefined {
  return kind === "fiscal-invoices" ? "E31" : kind === "invoices" ? "E32" : kind === "credit-notes" ? "E34" : undefined;
}

export function documentTypeNumber(type: EcfDocumentType): 31 | 32 | 34 {
  return type === "E31" ? 31 : type === "E32" ? 32 : 34;
}

export function maxItemsForAlanubeDom(type: EcfDocumentType, totalAmount: number) {
  return type === "E32" && totalAmount < 250000 ? 10000 : 1000;
}

export function validateAlanubeDomDraftPayload(type: EcfDocumentType, payload: AlanubeDomPayloadDraft): AlanubeContractError[] {
  return validateAlanubeOfficialRequest(type, payload).errors.map((error) => ({
    code: `ALANUBE_SCHEMA_${error.keyword.toUpperCase()}`, path: error.path,
    message: "El payload no cumple el contrato DOM verificado.",
  }));
}

export function validateAlanubeRequestConformance(type: EcfDocumentType, payload: unknown): AlanubeSchemaResult {
  const structural = validateAlanubeOfficialRequest(type, payload);
  if (!structural.ok) return structural;
  const value = payload as AlanubeDomPayloadDraft;
  const errors: AlanubeSchemaResult["errors"] = [];
  const require = (ok: boolean, path: string, keyword: string) => { if (!ok) errors.push({ path, keyword }); };
  require(new RegExp(`^${type}\\d{10}$`).test(value.idDoc.encf ?? ""), "/idDoc/encf", "documentTypeMismatch");
  require(/^\d{9,11}$/.test(value.sender.rnc), "/sender/rnc", "localTaxIdentity");
  require(Boolean(value.sender.companyName.trim()) && Boolean(value.sender.address?.trim()), "/sender", "nonEmptyIdentity");
  if (type === "E31" || (type === "E32" && value.totals.totalAmount >= 250000)) {
    require(Boolean(value.buyer?.companyName?.trim()) && /^\d{9,11}$/.test(value.buyer?.rnc ?? ""), "/buyer", "identifiedBuyerRequired");
  }
  if (value.idDoc.paymentType === 2) require(Boolean(value.idDoc.paymentDeadline), "/idDoc/paymentDeadline", "creditPaymentDeadlineRequired");
  if (type === "E34") {
    require(Boolean(value.informationReference?.ncfModified?.trim()), "/informationReference/ncfModified", "referenceRequired");
    if (value.informationReference?.modificationCode === 2) {
      require(value.totals.totalAmount === 0, "/totals/totalAmount", "textModificationMustBeZero");
    }
  }
  require(value.itemDetails.length <= maxItemsForAlanubeDom(type, value.totals.totalAmount), "/itemDetails", "localItemLimit");
  return { ...structural, ok: errors.length === 0, errors };
}
