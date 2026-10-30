import {
  TOTALS_TOLERANCE_CENTS,
  assertBuyerForDocumentType,
  assertIssuerComplete,
  assertSaleEligible,
  goodServiceFor,
  reconcileSaleTotals,
  taxCategoryFor,
} from "./ecf-sale-fiscal.policy";

// Política fiscal del adaptador venta → e-CF. Pruebas puras: fijan exactamente
// qué se acepta, qué se rechaza y qué NO se inventa jamás.
describe("ecf-sale-fiscal.policy", () => {
  describe("taxCategoryFor", () => {
    it("marca EXEMPT cuando la partida está exenta, sin mirar la tasa", () => {
      const result = taxCategoryFor({ taxExempt: true, taxRate: "0.1800" });
      expect(result).toEqual({ ok: true, value: "EXEMPT" });
    });

    it.each([
      ["0.1800", "ITBIS_18"],
      ["0.16", "ITBIS_16"],
      ["0.0000", "ITBIS_0"],
      [0.18, "ITBIS_18"],
      ["0.180000", "ITBIS_18"],
    ])("acepta la tasa soportada %p como %p", (taxRate, category) => {
      const result = taxCategoryFor({ taxExempt: false, taxRate });
      expect(result).toEqual({ ok: true, value: category });
    });

    it.each(["0.19", "0.15", "0.05", "0.1000", "not-a-number"])(
      "rechaza la tasa no soportada %p en lugar de aproximarla",
      (taxRate) => {
        const result = taxCategoryFor({ taxExempt: false, taxRate });
        expect(result.ok).toBe(false);
        if (result.ok) return;
        expect(result.code).toBe("ECF_UNSUPPORTED_TAX_RATE");
      },
    );
  });

  describe("goodServiceFor", () => {
    it("clasifica desde Product.itemType, la única fuente declarada", () => {
      expect(goodServiceFor("PRODUCT")).toEqual({ ok: true, value: "GOOD" });
      expect(goodServiceFor("SERVICE")).toEqual({ ok: true, value: "SERVICE" });
    });

    it("bloquea cuando no hay clasificación (no la deduce del nombre)", () => {
      for (const value of [null, undefined, "", "OTRO", "producto"]) {
        const result = goodServiceFor(value);
        expect(result.ok).toBe(false);
        if (result.ok) continue;
        expect(result.code).toBe("ECF_LINE_CLASSIFICATION_REQUIRED");
      }
    });
  });

  describe("reconcileSaleTotals", () => {
    const lines = [
      { grossAmount: "59.00", lineDiscountAmount: "0.00", taxableBase: "50.00", exemptAmount: "0.00", taxAmount: "9.00" },
      { grossAmount: "11.80", lineDiscountAmount: "1.00", taxableBase: "10.00", exemptAmount: "0.00", taxAmount: "1.80" },
    ];
    const totals = {
      taxableBase: "60.00",
      exemptAmount: "0.00",
      discountAmount: "1.00",
      taxAmount: "10.80",
      total: "70.80",
    };

    it("acepta totales coherentes con las partidas", () => {
      const result = reconcileSaleTotals({ lines, totals });
      expect(result.ok).toBe(true);
      if (!result.ok) return;
      expect(result.value.totals).toEqual({
        subtotal: "60.00",
        taxableBase: "60.00",
        exemptAmount: "0.00",
        discountAmount: "1.00",
        itbisAmount: "10.80",
        total: "70.80",
      });
      expect(result.value.linesSum.itbisAmount).toBe("10.80");
    });

    it("acepta exactamente un céntimo de divergencia (límite de redondeo)", () => {
      expect(TOTALS_TOLERANCE_CENTS).toBe(1);
      const result = reconcileSaleTotals({
        lines,
        totals: { ...totals, total: "70.81" },
      });
      expect(result.ok).toBe(true);
    });

    it("rechaza dos céntimos de divergencia", () => {
      const result = reconcileSaleTotals({
        lines,
        totals: { ...totals, total: "70.82" },
      });
      expect(result.ok).toBe(false);
    });

    it.each([
      ["taxableBase", { taxableBase: "59.00" }],
      ["exemptAmount", { exemptAmount: "5.00" }],
      ["discountAmount", { discountAmount: "0.00" }],
      ["itbisAmount", { taxAmount: "9.00" }],
      ["total", { total: "99.99" }],
    ])("rechaza incoherencia en %s y la nombra", (field, override) => {
      const result = reconcileSaleTotals({
        lines,
        totals: { ...totals, ...override },
      });
      expect(result.ok).toBe(false);
      if (result.ok) return;
      expect(result.code).toBe("ECF_SALE_TOTALS_MISMATCH");
      expect(result.safeMessage).toContain(field);
    });

    it("rechaza una venta sin partidas", () => {
      const result = reconcileSaleTotals({ lines: [], totals });
      expect(result.ok).toBe(false);
    });
  });

  describe("assertSaleEligible", () => {
    const eligible = { isDeleted: false, cancelledAt: null, refundedSaleId: null, itemCount: 1 };

    it("acepta una venta vigente con partidas", () => {
      expect(assertSaleEligible(eligible)).toEqual({ ok: true, value: true });
    });

    it.each([
      ["ECF_SALE_DELETED", { ...eligible, isDeleted: true }],
      ["ECF_SALE_CANCELLED", { ...eligible, cancelledAt: new Date() }],
      ["ECF_SALE_IS_REFUND", { ...eligible, refundedSaleId: "original" }],
      ["ECF_SALE_HAS_NO_ITEMS", { ...eligible, itemCount: 0 }],
    ])("bloquea con %s", (code, sale) => {
      const result = assertSaleEligible(sale);
      expect(result.ok).toBe(false);
      if (result.ok) return;
      expect(result.code).toBe(code);
    });
  });

  describe("assertIssuerComplete", () => {
    it("exige nombre, RNC y dirección y los enumera", () => {
      const result = assertIssuerComplete({
        legalName: " ",
        taxId: null,
        address: "Av. Principal",
      });
      expect(result.ok).toBe(false);
      if (result.ok) return;
      expect(result.code).toBe("ECF_ISSUER_DATA_INCOMPLETE");
      expect(result.safeMessage).toContain("nombre");
      expect(result.safeMessage).toContain("RNC");
      expect(result.safeMessage).not.toContain("dirección");
    });
  });

  describe("assertBuyerForDocumentType", () => {
    it("E32 (consumidor final) no exige receptor identificado", () => {
      expect(assertBuyerForDocumentType("E32", {})).toEqual({
        ok: true,
        value: true,
      });
    });

    it("E31 exige RNC y razón social del receptor", () => {
      const result = assertBuyerForDocumentType("E31", { taxId: "", legalName: "" });
      expect(result.ok).toBe(false);
      if (result.ok) return;
      expect(result.code).toBe("ECF_BUYER_DATA_REQUIRED");
      expect(result.safeMessage).toContain("RNC");
      expect(result.safeMessage).toContain("razón social");
    });

    it("E31 acepta un receptor completo", () => {
      expect(
        assertBuyerForDocumentType("E31", { taxId: "101000001", legalName: "Cliente SA" }),
      ).toEqual({ ok: true, value: true });
    });
  });
});
