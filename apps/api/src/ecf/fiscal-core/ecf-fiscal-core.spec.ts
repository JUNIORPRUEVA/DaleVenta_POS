import { EcfAlanubeClient } from "../ecf-alanube.client";
import {
  invalidFixtures,
  validE31Mixed,
  validE31WithDiscount,
  validE31WithItbis,
  validE32Discount,
  validE32Multiple,
  validE32Simple,
  validE34Partial,
  validE34Total,
} from "./ecf-fixtures";
import { mapEcfToAlanubeDom } from "./alanube-dom.mapper";
import { validateAlanubeDomDraftPayload } from "./alanube-dom.contract";
import { moneyString } from "./ecf-money";
import { validateEcfDocument } from "./ecf-validator";

describe("e-CF fiscal core", () => {
  const validFixtures = [
    validE31WithItbis,
    validE31Mixed,
    validE31WithDiscount,
    validE32Simple,
    validE32Multiple,
    validE32Discount,
    validE34Partial,
    validE34Total,
  ];

  it("validates local valid fixtures for E31, E32 and E34", () => {
    for (const fixture of validFixtures) {
      expect(validateEcfDocument(fixture)).toEqual({ ok: true, errors: [] });
    }
  });

  it("returns structured validation errors for invalid fixtures", () => {
    for (const fixture of Object.values(invalidFixtures)) {
      const result = validateEcfDocument(fixture);
      expect(result.ok).toBe(false);
      expect(result.errors[0]).toEqual(
        expect.objectContaining({
          code: expect.any(String),
          field: expect.any(String),
          category: expect.any(String),
          message: expect.any(String),
        }),
      );
    }
  });

  it("enforces E32 buyer requirement at the documented DOP 250,000 threshold", () => {
    const result = validateEcfDocument({
      ...validE32Simple,
      lines: [
        {
          ...validE32Simple.lines[0],
          quantity: "1",
          unitPrice: "250000.00",
        },
      ],
      totals: {
        subtotal: "250000.00",
        taxableBase: "250000.00",
        exemptAmount: "0.00",
        discountAmount: "0.00",
        itbisAmount: "45000.00",
        total: "295000.00",
      },
    });
    expect(result.errors.map((error) => error.code)).toContain(
      "ECF_BUYER_REQUIRED_E32_THRESHOLD",
    );
  });

  it("maps E31, E32 and E34 to their documented Alanube DOM resource kinds", () => {
    expect(mapEcfToAlanubeDom(validE31WithItbis).kind).toBe("fiscal-invoices");
    expect(mapEcfToAlanubeDom(validE32Simple).kind).toBe("invoices");
    expect(mapEcfToAlanubeDom(validE34Partial).kind).toBe("credit-notes");
  });

  it("maps confirmed line fields deterministically without mutating input", () => {
    const before = JSON.stringify(validE31WithItbis);
    const first = mapEcfToAlanubeDom(validE31WithItbis);
    const second = mapEcfToAlanubeDom(validE31WithItbis);

    expect(first).toEqual(second);
    expect(JSON.stringify(validE31WithItbis)).toBe(before);
    expect(first.payload.itemDetails[0]).toEqual(
      expect.objectContaining({
        lineNumber: 1,
        billingIndicator: 1,
        itemName: "Articulo de prueba",
        goodServiceIndicator: 1,
        quantityItem: 1,
        unitPriceItem: 100,
        itemAmount: 100,
      }),
    );
    expect(first.contractStatus).toBe("BLOCKED_PENDING_SCHEMA");
    expect(first.payload.sender).toMatchObject({ rnc: validE31WithItbis.sender.taxId, companyName: validE31WithItbis.sender.legalName });
    expect(first.payload.sender).not.toHaveProperty("taxId");
    expect(first.payload).not.toHaveProperty("config");
  });

  it("validates the documented Alanube DOM draft contract locally", () => {
    const mapped = mapEcfToAlanubeDom(validE31WithItbis, {
      encf: "E310000000001", sequenceDueDate: "2026-12-31", incomeType: 1, paymentType: 1,
    });
    expect(validateAlanubeDomDraftPayload("E31", mapped.payload)).toEqual([]);
    expect(
      validateAlanubeDomDraftPayload("E31", {
        ...mapped.payload,
        buyer: undefined,
      }).map((error) => error.code),
    ).toContain("ALANUBE_SCHEMA_REQUIRED");
  });

  it("uses decimal money rounding instead of binary float behavior", () => {
    expect(moneyString("10.005")).toBe("10.01");
    expect(moneyString("0.1")).toBe("0.10");
  });

  it("keeps the Alanube client without real transport methods", () => {
    const alanube = new EcfAlanubeClient({ get: jest.fn() } as any);
    expect(typeof (alanube as any).issueFiscalCreditInvoice31).toBe("undefined");
    expect(typeof (alanube as any).getFiscalCreditInvoice31Status).toBe("undefined");
    expect(JSON.stringify(alanube.getRuntimeState())).not.toContain("token");
  });
});
