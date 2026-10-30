import type {
  EcfFiscalDocument,
  EcfLine,
  EcfTotals,
} from "../fiscal-core/ecf-fiscal-document";
import { validateEcfDocument } from "../fiscal-core/ecf-validator";
import type { EcfSaleSnapshotLine } from "../pos/ecf-sale-adapter";
import { buildCreditLines, originalNetTotal, totalsForLines } from "./ecf-credit-note.policy";

// Notas de crédito: además de las reglas propias, TODA nota construida debe
// pasar el validador fiscal real. Ese es el contrato que estas pruebas fijan.
const gravada = (over: Partial<EcfSaleSnapshotLine> = {}): EcfSaleSnapshotLine => ({
  name: "Producto gravado",
  quantity: "3",
  unitPrice: "50.00",
  discountAmount: "0.00",
  taxCategory: "ITBIS_18",
  goodServiceIndicator: "GOOD",
  ...over,
});

const exenta = (over: Partial<EcfSaleSnapshotLine> = {}): EcfSaleSnapshotLine => ({
  name: "Producto exento",
  quantity: "2",
  unitPrice: "30.00",
  discountAmount: "0.00",
  taxCategory: "EXEMPT",
  goodServiceIndicator: "GOOD",
  ...over,
});

function documentFrom(lines: EcfLine[], totals: EcfTotals): EcfFiscalDocument {
  return {
    type: "E34",
    issueDate: "2026-10-15",
    currency: "DOP",
    sender: { legalName: "Emisor SRL", taxId: "101000001", address: "Av. Principal 1" },
    buyer: { legalName: "Cliente SA", taxId: "130000000" },
    lines,
    totals,
    reference: {
      originalType: "E31",
      originalENcf: "E310000000001",
      originalIssueDate: "2026-10-01",
      modificationReason: "Devolución parcial",
      refundKind: "PARTIAL",
    },
  };
}

describe("ecf-credit-note.policy", () => {
  describe("nota total", () => {
    it("acredita todas las líneas y pasa el validador fiscal", () => {
      const result = buildCreditLines({
        originalLines: [gravada(), exenta()],
        refundKind: "TOTAL",
      });

      expect(result.ok).toBe(true);
      if (!result.ok) return;
      expect(result.value.lines).toHaveLength(2);
      // 3×50 = 150 (base 18%) + 2×30 = 60 (exento) → ITBIS 27 → total 237
      expect(result.value.totals).toEqual({
        subtotal: "210.00",
        taxableBase: "150.00",
        exemptAmount: "60.00",
        discountAmount: "0.00",
        itbisAmount: "27.00",
        total: "237.00",
      });
      expect(validateEcfDocument(documentFrom(result.value.lines, result.value.totals)).ok).toBe(true);
    });

    it("preserva el descuento del original", () => {
      const result = buildCreditLines({
        originalLines: [gravada({ discountAmount: "15.00" })],
        refundKind: "TOTAL",
      });

      expect(result.ok).toBe(true);
      if (!result.ok) return;
      // 3×50 − 15 = 135 → ITBIS 24,30 → total 159,30
      expect(result.value.totals).toEqual({
        subtotal: "135.00",
        taxableBase: "135.00",
        exemptAmount: "0.00",
        discountAmount: "15.00",
        itbisAmount: "24.30",
        total: "159.30",
      });
      expect(validateEcfDocument(documentFrom(result.value.lines, result.value.totals)).ok).toBe(true);
    });
  });

  describe("nota parcial", () => {
    it("acredita una parte exacta de una línea y pasa el validador", () => {
      const result = buildCreditLines({
        originalLines: [gravada()],
        refundKind: "PARTIAL",
        requested: [{ lineNumber: 1, quantity: "1" }],
      });

      expect(result.ok).toBe(true);
      if (!result.ok) return;
      // 1 de 3 unidades de 50 → 50 + ITBIS 9 = 59
      expect(result.value.totals.total).toBe("59.00");
      expect(result.value.totals.itbisAmount).toBe("9.00");
      expect(validateEcfDocument(documentFrom(result.value.lines, result.value.totals)).ok).toBe(true);
    });

    it("reparte el descuento de forma proporcional y sigue siendo válida", () => {
      // 4 unidades a 50 con 20 de descuento: neto 180. Se acredita 1 unidad.
      const result = buildCreditLines({
        originalLines: [gravada({ quantity: "4", discountAmount: "20.00" })],
        refundKind: "PARTIAL",
        requested: [{ lineNumber: 1, quantity: "1" }],
      });

      expect(result.ok).toBe(true);
      if (!result.ok) return;
      // neto original 180 → 1/4 = 45; ITBIS 8,10 → total 53,10
      expect(result.value.totals.subtotal).toBe("45.00");
      expect(result.value.totals.total).toBe("53.10");
      expect(validateEcfDocument(documentFrom(result.value.lines, result.value.totals)).ok).toBe(true);
    });

    it("combina una línea gravada parcial con una exenta completa", () => {
      const result = buildCreditLines({
        originalLines: [gravada(), exenta()],
        refundKind: "PARTIAL",
        requested: [
          { lineNumber: 1, quantity: "1" },
          { lineNumber: 2, quantity: "2" },
        ],
      });

      expect(result.ok).toBe(true);
      if (!result.ok) return;
      expect(result.value.totals).toEqual({
        subtotal: "110.00",
        taxableBase: "50.00",
        exemptAmount: "60.00",
        discountAmount: "0.00",
        itbisAmount: "9.00",
        total: "119.00",
      });
      expect(validateEcfDocument(documentFrom(result.value.lines, result.value.totals)).ok).toBe(true);
    });

    it("nunca deja que el cliente elija la clasificación fiscal", () => {
      const result = buildCreditLines({
        originalLines: [exenta()],
        refundKind: "PARTIAL",
        requested: [{ lineNumber: 1, quantity: "1" }],
      });

      expect(result.ok).toBe(true);
      if (!result.ok) return;
      // La categoría viene del original, no de la petición.
      expect(result.value.lines[0].taxCategory).toBe("EXEMPT");
      expect(result.value.lines[0].goodServiceIndicator).toBe("GOOD");
    });
  });

  describe("bloqueos", () => {
    it.each([
      ["ECF_CREDIT_LINES_REQUIRED", { refundKind: "PARTIAL" as const, requested: [] }],
      ["ECF_CREDIT_LINE_NOT_FOUND", { refundKind: "PARTIAL" as const, requested: [{ lineNumber: 9, quantity: "1" }] }],
      ["ECF_CREDIT_QUANTITY_INVALID", { refundKind: "PARTIAL" as const, requested: [{ lineNumber: 1, quantity: "4" }] }],
      ["ECF_CREDIT_QUANTITY_INVALID", { refundKind: "PARTIAL" as const, requested: [{ lineNumber: 1, quantity: "0" }] }],
      ["ECF_CREDIT_QUANTITY_INVALID", { refundKind: "PARTIAL" as const, requested: [{ lineNumber: 1, quantity: "-1" }] }],
    ])("bloquea con %s", (code, input) => {
      const result = buildCreditLines({
        originalLines: [gravada()],
        ...(input as { refundKind: "PARTIAL"; requested: Array<{ lineNumber: number; quantity: string }> }),
      });

      expect(result.ok).toBe(false);
      if (result.ok) return;
      expect(result.code).toBe(code);
    });

    it("bloquea una línea repetida", () => {
      const result = buildCreditLines({
        originalLines: [gravada()],
        refundKind: "PARTIAL",
        requested: [
          { lineNumber: 1, quantity: "1" },
          { lineNumber: 1, quantity: "1" },
        ],
      });

      expect(result.ok).toBe(false);
      if (result.ok) return;
      expect(result.code).toBe("ECF_CREDIT_LINE_DUPLICATED");
    });

    it("bloquea un original sin líneas", () => {
      const result = buildCreditLines({ originalLines: [], refundKind: "TOTAL" });

      expect(result.ok).toBe(false);
      if (result.ok) return;
      expect(result.code).toBe("ECF_CREDIT_ORIGINAL_HAS_NO_LINES");
    });

    it("bloquea una nota que acreditaría cero", () => {
      // Línea con descuento igual al importe bruto: acreditar todo da 0.
      const result = buildCreditLines({
        originalLines: [gravada({ quantity: "1", unitPrice: "50.00", discountAmount: "50.00" })],
        refundKind: "PARTIAL",
        requested: [{ lineNumber: 1, quantity: "1" }],
      });

      expect(result.ok).toBe(false);
      if (result.ok) return;
      expect(result.code).toBe("ECF_CREDIT_TOTAL_MUST_BE_POSITIVE");
    });
  });

  describe("totales del original", () => {
    it("no supera nunca el total facturado al acreditar todo", () => {
      const total = originalNetTotal({
        type: "E31",
        issueDate: "2026-10-01",
        currency: "DOP",
        seller: { legalName: "Emisor SRL", taxId: "101000001" },
        lines: [gravada(), exenta()],
        totals: totalsForLines([]),
      });
      expect(total).toBe("237.00");
    });
  });
});
