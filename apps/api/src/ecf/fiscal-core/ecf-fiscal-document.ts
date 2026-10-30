import type { EcfDecimalInput } from "./ecf-money";

export type EcfDocumentType = "E31" | "E32" | "E34";
export type EcfGoodServiceIndicator = "GOOD" | "SERVICE";
export type EcfTaxCategory = "ITBIS_18" | "ITBIS_16" | "ITBIS_0" | "EXEMPT" | "NON_BILLABLE";
export type EcfCurrency = "DOP" | "USD" | "EUR";

export type EcfParty = {
  legalName: string;
  taxId: string;
  tradeName?: string;
  address?: string;
  phone?: string;
  email?: string;
};

export type EcfBuyer = {
  legalName?: string;
  taxId?: string;
  address?: string;
  phone?: string;
  email?: string;
};

export type EcfLine = {
  lineNumber: number;
  name: string;
  description?: string;
  goodServiceIndicator: EcfGoodServiceIndicator;
  quantity: EcfDecimalInput;
  unitPrice: EcfDecimalInput;
  discountAmount?: EcfDecimalInput;
  taxCategory: EcfTaxCategory;
  taxRate: EcfDecimalInput;
  expectedItemAmount?: EcfDecimalInput;
  unsupportedFields?: Record<string, unknown>;
};

export type EcfTotals = {
  subtotal: EcfDecimalInput;
  taxableBase: EcfDecimalInput;
  exemptAmount: EcfDecimalInput;
  discountAmount: EcfDecimalInput;
  itbisAmount: EcfDecimalInput;
  total: EcfDecimalInput;
};

export type EcfReference = {
  originalType?: EcfDocumentType;
  originalENcf?: string;
  originalIssueDate?: string;
  modificationReason?: string;
  refundKind?: "PARTIAL" | "TOTAL";
};

export type EcfFiscalDocument = {
  type: EcfDocumentType;
  issueDate: string;
  currency: EcfCurrency;
  sender: EcfParty;
  buyer?: EcfBuyer;
  lines: EcfLine[];
  totals: EcfTotals;
  reference?: EcfReference;
  notes?: string;
  unsupportedFields?: Record<string, unknown>;
};

export type EcfValidationCategory =
  | "STRUCTURE"
  | "FISCAL_RULE"
  | "MONEY_CONSISTENCY"
  | "MISSING_FIELD"
  | "UNSUPPORTED"
  | "NOT_IMPLEMENTED";

export type EcfValidationError = {
  code: string;
  field: string;
  category: EcfValidationCategory;
  message: string;
};

export type EcfValidationResult = {
  ok: boolean;
  errors: EcfValidationError[];
};

