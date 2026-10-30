import type { EcfFiscalDocument, EcfLine } from "./ecf-fiscal-document";

const sender = {
  legalName: "FULLPOS PRUEBAS SRL",
  taxId: "101000001",
  address: "Santo Domingo, RD",
};

const buyer = {
  legalName: "CLIENTE FISCAL PRUEBA SRL",
  taxId: "101000002",
};

function line(overrides: Partial<EcfLine> = {}): EcfLine {
  return {
    lineNumber: 1,
    name: "Articulo de prueba",
    goodServiceIndicator: "GOOD",
    quantity: "1",
    unitPrice: "100.00",
    discountAmount: "0.00",
    taxCategory: "ITBIS_18",
    taxRate: "0.18",
    ...overrides,
  };
}

export const validE31WithItbis: EcfFiscalDocument = {
  type: "E31",
  issueDate: "2026-10-14",
  currency: "DOP",
  sender,
  buyer,
  lines: [line()],
  totals: {
    subtotal: "100.00",
    taxableBase: "100.00",
    exemptAmount: "0.00",
    discountAmount: "0.00",
    itbisAmount: "18.00",
    total: "118.00",
  },
};

export const validE31Mixed: EcfFiscalDocument = {
  ...validE31WithItbis,
  lines: [
    line({ lineNumber: 1, quantity: "2", unitPrice: "100.00" }),
    line({
      lineNumber: 2,
      name: "Servicio exento",
      goodServiceIndicator: "SERVICE",
      unitPrice: "50.00",
      taxCategory: "EXEMPT",
      taxRate: "0",
    }),
  ],
  totals: {
    subtotal: "250.00",
    taxableBase: "200.00",
    exemptAmount: "50.00",
    discountAmount: "0.00",
    itbisAmount: "36.00",
    total: "286.00",
  },
};

export const validE31WithDiscount: EcfFiscalDocument = {
  ...validE31WithItbis,
  lines: [line({ unitPrice: "100.00", discountAmount: "10.00" })],
  totals: {
    subtotal: "90.00",
    taxableBase: "90.00",
    exemptAmount: "0.00",
    discountAmount: "10.00",
    itbisAmount: "16.20",
    total: "106.20",
  },
};

export const validE32Simple: EcfFiscalDocument = {
  type: "E32",
  issueDate: "2026-10-14",
  currency: "DOP",
  sender,
  lines: [line()],
  totals: validE31WithItbis.totals,
};

export const validE32Multiple: EcfFiscalDocument = {
  ...validE32Simple,
  lines: [line({ lineNumber: 1 }), line({ lineNumber: 2, name: "Servicio", goodServiceIndicator: "SERVICE" })],
  totals: {
    subtotal: "200.00",
    taxableBase: "200.00",
    exemptAmount: "0.00",
    discountAmount: "0.00",
    itbisAmount: "36.00",
    total: "236.00",
  },
};

export const validE32Discount: EcfFiscalDocument = {
  ...validE32Simple,
  lines: [line({ discountAmount: "5.00" })],
  totals: {
    subtotal: "95.00",
    taxableBase: "95.00",
    exemptAmount: "0.00",
    discountAmount: "5.00",
    itbisAmount: "17.10",
    total: "112.10",
  },
};

export const validE34Partial: EcfFiscalDocument = {
  ...validE31WithItbis,
  type: "E34",
  reference: {
    originalType: "E31",
    originalENcf: "E310000000001",
    originalIssueDate: "2026-10-13",
    modificationReason: "Devolucion parcial de prueba",
    refundKind: "PARTIAL",
  },
};

export const validE34Total: EcfFiscalDocument = {
  ...validE34Partial,
  reference: {
    ...validE34Partial.reference!,
    modificationReason: "Devolucion total de prueba",
    refundKind: "TOTAL",
  },
};

export const invalidFixtures = {
  buyerInvalid: { ...validE31WithItbis, buyer: { legalName: "Cliente", taxId: "ABC" } },
  withoutSender: { ...validE31WithItbis, sender: { legalName: "", taxId: "" } },
  itbisInconsistent: {
    ...validE31WithItbis,
    totals: { ...validE31WithItbis.totals, itbisAmount: "1.00" },
  },
  excessiveDiscount: {
    ...validE31WithItbis,
    lines: [line({ discountAmount: "101.00" })],
  },
  totalsInconsistent: {
    ...validE31WithItbis,
    totals: { ...validE31WithItbis.totals, total: "999.00" },
  },
  missingReference: { ...validE34Partial, reference: undefined },
  unsupportedFields: { ...validE31WithItbis, unsupportedFields: { unknown: true } },
  invalidQuantity: { ...validE31WithItbis, lines: [line({ quantity: "0" })] },
  negativeAmount: { ...validE31WithItbis, lines: [line({ unitPrice: "-1" })] },
} satisfies Record<string, EcfFiscalDocument>;
