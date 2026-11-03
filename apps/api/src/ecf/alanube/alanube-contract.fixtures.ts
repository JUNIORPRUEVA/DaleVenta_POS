// Fictitious local validation only. Numbers are not allocated or sent anywhere.
import { validE31WithItbis, validE31Mixed, validE31WithDiscount, validE32Simple,
  validE34Partial, validE32Discount, validE34Total } from "../fiscal-core/ecf-fixtures";
import type { EcfIssuanceMetadata } from "../fiscal-core/alanube-dom.contract";

export const ALANUBE_CONTRACT_FIXTURES = [
  { name: "E31 ITBIS", document: validE31WithItbis, metadata: { encf: "E310000000001", sequenceDueDate: "2026-12-31", incomeType: 1, paymentType: 1 } },
  { name: "E31 mixed exempt", document: validE31Mixed, metadata: { encf: "E310000000002", sequenceDueDate: "2026-12-31", incomeType: 1, paymentType: 1 } },
  { name: "E31 discount", document: validE31WithDiscount, metadata: { encf: "E310000000003", sequenceDueDate: "2026-12-31", incomeType: 1, paymentType: 1 } },
  { name: "E32", document: validE32Simple, metadata: { encf: "E320000000001", incomeType: 1, paymentType: 1 } },
  { name: "E34", document: validE34Partial, metadata: { encf: "E340000000001", paymentType: 1, creditNoteIndicator: 0, modificationCode: 3 } },
  { name: "E32 discount", document: validE32Discount, metadata: { encf: "E320000000002", incomeType: 1, paymentType: 1 } },
  { name: "E34 total", document: validE34Total, metadata: { encf: "E340000000002", paymentType: 1, creditNoteIndicator: 0, modificationCode: 1 } },
] satisfies Array<{ name: string; document: typeof validE31WithItbis; metadata: EcfIssuanceMetadata }>;
