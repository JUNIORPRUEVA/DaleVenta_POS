import { BadRequestException } from "@nestjs/common";
import { TaxCalculationService } from "./tax-calculation.service";

describe("TaxCalculationService", () => {
  const service = new TaxCalculationService();
  const n = (value: { toFixed(scale?: number): string }) => value.toFixed(2);

  it("case 1 - keeps totals unchanged when taxes are disabled", () => {
    const result = service.calculate({
      taxEnabled: false,
      lines: [{ description: "Producto", quantity: 1, unitPrice: 100 }],
    });

    expect(n(result.total)).toBe("100.00");
    expect(n(result.taxAmount)).toBe("0.00");
    expect(n(result.taxableBase)).toBe("0.00");
    expect(n(result.exemptAmount)).toBe("100.00");
  });

  it("case 2 - calculates added ITBIS", () => {
    const result = service.calculate({
      taxEnabled: true,
      defaultTaxRate: 0.18,
      defaultPriceMode: "TAX_ADDED",
      lines: [{ description: "Producto", quantity: 1, unitPrice: 100 }],
    });

    expect(n(result.taxableBase)).toBe("100.00");
    expect(n(result.taxAmount)).toBe("18.00");
    expect(n(result.total)).toBe("118.00");
  });

  it("case 3 - extracts included ITBIS", () => {
    const result = service.calculate({
      taxEnabled: true,
      defaultTaxRate: 0.18,
      defaultPriceMode: "TAX_INCLUDED",
      lines: [{ description: "Producto", quantity: 1, unitPrice: 118 }],
    });

    expect(n(result.taxableBase)).toBe("100.00");
    expect(n(result.taxAmount)).toBe("18.00");
    expect(n(result.total)).toBe("118.00");
  });

  it("case 4 - supports exempt products", () => {
    const result = service.calculate({
      taxEnabled: true,
      defaultTaxRate: 0.18,
      defaultPriceMode: "TAX_INCLUDED",
      lines: [
        {
          description: "Exento",
          quantity: 1,
          unitPrice: 500,
          taxTreatment: "EXEMPT",
        },
      ],
    });

    expect(n(result.taxAmount)).toBe("0.00");
    expect(n(result.exemptAmount)).toBe("500.00");
    expect(n(result.total)).toBe("500.00");
  });

  it("case 5 - supports a mixed taxable and exempt invoice", () => {
    const result = service.calculate({
      taxEnabled: true,
      defaultTaxRate: 0.18,
      defaultPriceMode: "TAX_INCLUDED",
      lines: [
        { description: "Gravado", quantity: 1, unitPrice: 1180 },
        {
          description: "Exento",
          quantity: 1,
          unitPrice: 500,
          taxTreatment: "EXEMPT",
        },
      ],
    });

    expect(n(result.taxableBase)).toBe("1000.00");
    expect(n(result.taxAmount)).toBe("180.00");
    expect(n(result.exemptAmount)).toBe("500.00");
    expect(n(result.total)).toBe("1680.00");
  });

  it("regression lock - included 18% keeps 1180 => base 1000 / tax 180 / total 1180", () => {
    const result = service.calculate({
      taxEnabled: true,
      defaultTaxRate: 0.18,
      defaultPriceMode: "TAX_INCLUDED",
      lines: [{ description: "Included", quantity: 1, unitPrice: 1180 }],
    });

    expect(n(result.taxableBase)).toBe("1000.00");
    expect(n(result.taxAmount)).toBe("180.00");
    expect(n(result.total)).toBe("1180.00");
  });

  it("regression lock - added 18% keeps 1000 => base 1000 / tax 180 / total 1180", () => {
    const result = service.calculate({
      taxEnabled: true,
      defaultTaxRate: 0.18,
      defaultPriceMode: "TAX_ADDED",
      lines: [{ description: "Added", quantity: 1, unitPrice: 1000 }],
    });

    expect(n(result.taxableBase)).toBe("1000.00");
    expect(n(result.taxAmount)).toBe("180.00");
    expect(n(result.total)).toBe("1180.00");
  });

  it("regression lock - exempt keeps 500 => tax 0 / total 500", () => {
    const result = service.calculate({
      taxEnabled: true,
      defaultTaxRate: 0.18,
      defaultPriceMode: "TAX_INCLUDED",
      lines: [
        {
          description: "Exempt",
          quantity: 1,
          unitPrice: 500,
          taxTreatment: "EXEMPT",
        },
      ],
    });

    expect(n(result.taxableBase)).toBe("0.00");
    expect(n(result.taxAmount)).toBe("0.00");
    expect(n(result.exemptAmount)).toBe("500.00");
    expect(n(result.total)).toBe("500.00");
  });

  it("regression lock - mixed keeps 1180 included + 500 exempt => total 1680", () => {
    const result = service.calculate({
      taxEnabled: true,
      defaultTaxRate: 0.18,
      defaultPriceMode: "TAX_INCLUDED",
      lines: [
        { description: "Included", quantity: 1, unitPrice: 1180 },
        {
          description: "Exempt",
          quantity: 1,
          unitPrice: 500,
          taxTreatment: "EXEMPT",
        },
      ],
    });

    expect(n(result.taxableBase)).toBe("1000.00");
    expect(n(result.taxAmount)).toBe("180.00");
    expect(n(result.exemptAmount)).toBe("500.00");
    expect(n(result.total)).toBe("1680.00");
  });

  it("multi-company fixture - A no tax, B included and C added stay isolated by settings input", () => {
    const companyA = service.calculate({
      taxEnabled: false,
      lines: [{ description: "A", quantity: 1, unitPrice: 1180 }],
    });
    const companyB = service.calculate({
      taxEnabled: true,
      defaultTaxRate: 0.18,
      defaultPriceMode: "TAX_INCLUDED",
      lines: [{ description: "B", quantity: 1, unitPrice: 1180 }],
    });
    const companyC = service.calculate({
      taxEnabled: true,
      defaultTaxRate: 0.18,
      defaultPriceMode: "TAX_ADDED",
      lines: [{ description: "C", quantity: 1, unitPrice: 1000 }],
    });

    expect(n(companyA.total)).toBe("1180.00");
    expect(n(companyA.taxAmount)).toBe("0.00");
    expect(n(companyA.exemptAmount)).toBe("1180.00");
    expect(n(companyB.taxableBase)).toBe("1000.00");
    expect(n(companyB.taxAmount)).toBe("180.00");
    expect(n(companyB.total)).toBe("1180.00");
    expect(n(companyC.taxableBase)).toBe("1000.00");
    expect(n(companyC.taxAmount)).toBe("180.00");
    expect(n(companyC.total)).toBe("1180.00");
  });

  it("case 6 - handles quantity greater than 1", () => {
    const result = service.calculate({
      taxEnabled: true,
      defaultTaxRate: 0.18,
      defaultPriceMode: "TAX_ADDED",
      lines: [{ description: "Producto", quantity: 2, unitPrice: 100 }],
    });

    expect(n(result.taxableBase)).toBe("200.00");
    expect(n(result.taxAmount)).toBe("36.00");
    expect(n(result.total)).toBe("236.00");
  });

  it("case 7 - applies discounts before taxes", () => {
    const result = service.calculate({
      taxEnabled: true,
      defaultTaxRate: 0.18,
      defaultPriceMode: "TAX_ADDED",
      lines: [
        {
          description: "Producto",
          quantity: 1,
          unitPrice: 100,
          discountAmount: 10,
        },
      ],
    });

    expect(n(result.taxableBase)).toBe("90.00");
    expect(n(result.taxAmount)).toBe("16.20");
    expect(n(result.total)).toBe("106.20");
  });

  it("case 8 - applies discounts with included ITBIS", () => {
    const result = service.calculate({
      taxEnabled: true,
      defaultTaxRate: 0.18,
      defaultPriceMode: "TAX_INCLUDED",
      lines: [
        {
          description: "Producto",
          quantity: 1,
          unitPrice: 118,
          discountAmount: 18,
        },
      ],
    });

    expect(n(result.taxableBase)).toBe("84.75");
    expect(n(result.taxAmount)).toBe("15.25");
    expect(n(result.total)).toBe("100.00");
  });

  it("case 9 - applies discounts with added ITBIS", () => {
    const result = service.calculate({
      taxEnabled: true,
      defaultTaxRate: 0.18,
      defaultPriceMode: "TAX_ADDED",
      lines: [
        {
          description: "Producto",
          quantity: 1,
          unitPrice: 118,
          discountAmount: 18,
        },
      ],
    });

    expect(n(result.taxableBase)).toBe("100.00");
    expect(n(result.taxAmount)).toBe("18.00");
    expect(n(result.total)).toBe("118.00");
  });

  it("case 10 - handles complex rounding for RD$99.99", () => {
    const result = service.calculate({
      taxEnabled: true,
      defaultTaxRate: 0.18,
      defaultPriceMode: "TAX_INCLUDED",
      lines: [{ description: "Producto", quantity: 1, unitPrice: 99.99 }],
    });

    expect(n(result.taxableBase)).toBe("84.74");
    expect(n(result.taxAmount)).toBe("15.25");
    expect(n(result.total)).toBe("99.99");
  });

  it("case 11 - keeps cent totals consistent across several products", () => {
    const result = service.calculate({
      taxEnabled: true,
      defaultTaxRate: 0.18,
      defaultPriceMode: "TAX_INCLUDED",
      lines: [
        { description: "A", quantity: 1, unitPrice: 99.99 },
        { description: "B", quantity: 1, unitPrice: 33.33 },
        { description: "C", quantity: 1, unitPrice: 12.34 },
      ],
    });

    expect(n(result.total)).toBe("145.66");
    expect(n(result.taxableBase.plus(result.taxAmount))).toBe("145.66");
    expect(
      n(result.lines.reduce((sum, line) => sum.plus(line.lineTotal), result.total.minus(result.total))),
    ).toBe("145.66");
  });

  it("case 12 - rejects B01 without fiscal customer data", () => {
    expect(() =>
      service.validateFiscalCustomer({
        voucherType: "B01",
        customerTaxId: "",
        customerBusinessName: "CANATECH SRL",
      }),
    ).toThrow(BadRequestException);
  });

  it("case 13 - rejects duplicated NCF for the same company", () => {
    const used = new Set(["company-a:B0100000014"]);

    expect(() =>
      service.assertNcfNotDuplicated(used, "company-a", "B0100000014"),
    ).toThrow(BadRequestException);
  });

  it("case 14 - allows same NCF in a different company scope", () => {
    const used = new Set(["company-a:B0100000014"]);

    expect(service.assertNcfNotDuplicated(used, "company-b", "B0100000014")).toBe(
      "company-b:B0100000014",
    );
  });

  it("case 16 - matches FULLTECH/CANATECH included ITBIS regression", () => {
    const result = service.calculate({
      taxEnabled: true,
      defaultTaxRate: 0.18,
      defaultPriceMode: "TAX_INCLUDED",
      lines: [
        { description: "FOTOCELDA PARA MOTOR", quantity: 1, unitPrice: 1200 },
        { description: "MOTOR WIFI 800KG", quantity: 1, unitPrice: 13000 },
        { description: "SERVICIO EXTRA", quantity: 1, unitPrice: 4000 },
        { description: "SERVICIO REEMPLAZO", quantity: 1, unitPrice: 6000 },
        { description: "LAMPARA PARA MOTOR", quantity: 1, unitPrice: 1500 },
      ],
    });

    expect(n(result.taxableBase)).toBe("21779.66");
    expect(n(result.taxAmount)).toBe("3920.34");
    expect(n(result.total)).toBe("25700.00");
    expect(n(result.taxableBase.plus(result.taxAmount))).toBe("25700.00");
    expect(result.lines.some((line) => !line.roundingAdjustment.eq(0))).toBe(true);
  });
});
