import type {
  EcfFiscalDocument,
  EcfLine,
  EcfTaxCategory,
} from "../../fiscal-core/ecf-fiscal-document";
import type { EcfIssuanceMetadata } from "../../fiscal-core/alanube-dom.contract";
import { DOSA_MAPPER_BLOCKED, mapEcfToDosaDraft } from "./dosa-ecf.mapper";

/**
 * Catálogos fiscales corregidos (DGII, noviembre 2026).
 *
 * Cada prueba construye un documento **coherente**: los totales se calculan de
 * las líneas, porque el mapeador ahora los verifica y bloquea si no cuadran.
 * Datos sintéticos: no se emite nada ni se toca ninguna secuencia real.
 */

const metadata: EcfIssuanceMetadata = { encf: "E310000000001" };

const RATES: Record<EcfTaxCategory, number> = {
  ITBIS_18: 0.18,
  ITBIS_16: 0.16,
  ITBIS_0: 0,
  EXEMPT: 0,
  NON_BILLABLE: 0,
};

type LineSpec = {
  name: string;
  good?: "GOOD" | "SERVICE";
  quantity?: string;
  unitPrice?: string;
  discount?: string;
  taxCategory: EcfTaxCategory;
  unitOfMeasure?: string;
};

function line(spec: LineSpec, index: number): EcfLine {
  return {
    lineNumber: index + 1,
    name: spec.name,
    goodServiceIndicator: spec.good ?? "GOOD",
    quantity: spec.quantity ?? "1",
    unitPrice: spec.unitPrice ?? "100.00",
    discountAmount: spec.discount ?? "0.00",
    taxCategory: spec.taxCategory,
    taxRate: String(RATES[spec.taxCategory]),
    unitOfMeasure: spec.unitOfMeasure ?? "UNIT",
  };
}

function amountOf(item: EcfLine): number {
  const gross = Number(item.quantity) * Number(item.unitPrice);
  const net = gross - Number(item.discountAmount ?? 0);
  return Math.round(net * 100) / 100;
}

/** Documento con totales derivados de las líneas, para que sean coherentes. */
function document(specs: LineSpec[], type: "E31" | "E32" = "E31"): EcfFiscalDocument {
  const lines = specs.map(line);
  const byCategory = (category: EcfTaxCategory) =>
    lines
      .filter((item) => item.taxCategory === category)
      .reduce((total, item) => total + amountOf(item), 0);

  const base18 = byCategory("ITBIS_18");
  const base16 = byCategory("ITBIS_16");
  const base0 = byCategory("ITBIS_0");
  const exempt = byCategory("EXEMPT");
  const itbis18 = Math.round(base18 * 0.18 * 100) / 100;
  const itbis16 = Math.round(base16 * 0.16 * 100) / 100;
  const itbis = Math.round((itbis18 + itbis16) * 100) / 100;
  const taxable = Math.round((base18 + base16 + base0) * 100) / 100;

  return {
    type,
    issueDate: "2026-11-04",
    currency: "DOP",
    sender: { legalName: "FULLTECH, SRL", taxId: "133080206" },
    buyer: { legalName: "Cliente Prueba", taxId: "131000001" },
    lines,
    totals: {
      subtotal: taxable.toFixed(2),
      taxableBase: taxable.toFixed(2),
      exemptAmount: exempt.toFixed(2),
      discountAmount: "0.00",
      itbisAmount: itbis.toFixed(2),
      total: (taxable + exempt + itbis).toFixed(2),
    },
  };
}

describe("mapeador DOSA — catálogos fiscales corregidos", () => {
  it("bien gravado al 18 %: indicador 1 y naturaleza 1", () => {
    const result = mapEcfToDosaDraft(
      document([{ name: "Monitor", taxCategory: "ITBIS_18" }]),
      metadata,
    );

    expect(result.ok).toBe(true);
    if (!result.ok) return;
    const item = result.draft.body.detallesItems[0];
    expect(item.indicadorFacturacion).toBe(1);
    expect(item.indicadorBienoServicio).toBe(1);
    expect(item.unidadMedida).toBe(43);
    const totales = result.draft.body.encabezado.totales;
    expect(totales.MontoGravadoI1).toBe("100.00");
    expect(totales.ITBIS1).toBe(18);
    expect(totales.TotalITBIS1).toBe("18.00");
  });

  it("servicio gravado al 18 %: misma tasa, naturaleza de servicio", () => {
    const result = mapEcfToDosaDraft(
      document([
        { name: "Instalación", good: "SERVICE", taxCategory: "ITBIS_18" },
      ]),
      metadata,
    );

    expect(result.ok).toBe(true);
    if (!result.ok) return;
    const item = result.draft.body.detallesItems[0];
    // El indicador fiscal NO cambia por ser servicio; la naturaleza sí.
    expect(item.indicadorFacturacion).toBe(1);
    expect(item.indicadorBienoServicio).toBe(2);
  });

  it("línea al 16 % usa el indicador 2 y MontoGravadoI2", () => {
    const result = mapEcfToDosaDraft(
      document([{ name: "Producto 16", taxCategory: "ITBIS_16" }]),
      metadata,
    );

    expect(result.ok).toBe(true);
    if (!result.ok) return;
    const item = result.draft.body.detallesItems[0];
    expect(item.indicadorFacturacion).toBe(2);
    const totales = result.draft.body.encabezado.totales;
    expect(totales.MontoGravadoI2).toBe("100.00");
    expect(totales.ITBIS2).toBe(16);
    expect(totales.TotalITBIS2).toBe("16.00");
    expect(totales.MontoGravadoI1).toBe("0.00");
  });

  it("línea a tasa 0 % va a MontoGravadoI3, no a exento", () => {
    const result = mapEcfToDosaDraft(
      document([{ name: "Canasta básica", taxCategory: "ITBIS_0" }]),
      metadata,
    );

    expect(result.ok).toBe(true);
    if (!result.ok) return;
    const item = result.draft.body.detallesItems[0];
    expect(item.indicadorFacturacion).toBe(3);
    const totales = result.draft.body.encabezado.totales;
    expect(totales.MontoGravadoI3).toBe("100.00");
    expect(totales.MontoExento).toBe("0.00");
    expect(totales.TotalITBIS3).toBe("0.00");
  });

  it("línea exenta va a MontoExento con indicador 4", () => {
    const result = mapEcfToDosaDraft(
      document([{ name: "Medicamento", taxCategory: "EXEMPT" }]),
      metadata,
    );

    expect(result.ok).toBe(true);
    if (!result.ok) return;
    const item = result.draft.body.detallesItems[0];
    expect(item.indicadorFacturacion).toBe(4);
    const totales = result.draft.body.encabezado.totales;
    expect(totales.MontoExento).toBe("100.00");
    expect(totales.MontoGravadoTotal).toBe("0.00");
    expect(totales.TotalITBIS).toBe("0.00");
  });

  it("factura mixta: reparte cada línea en su casilla de totales", () => {
    const result = mapEcfToDosaDraft(
      document([
        { name: "Bien 18", taxCategory: "ITBIS_18", unitPrice: "100.00" },
        { name: "Bien 16", taxCategory: "ITBIS_16", unitPrice: "50.00" },
        { name: "Tasa 0", taxCategory: "ITBIS_0", unitPrice: "30.00" },
        { name: "Exento", taxCategory: "EXEMPT", unitPrice: "20.00" },
      ]),
      metadata,
    );

    expect(result.ok).toBe(true);
    if (!result.ok) return;
    const totales = result.draft.body.encabezado.totales;
    expect(result.draft.body.detallesItems.map((i) => i.indicadorFacturacion)).toEqual([
      1, 2, 3, 4,
    ]);
    expect(totales.MontoGravadoI1).toBe("100.00");
    expect(totales.MontoGravadoI2).toBe("50.00");
    expect(totales.MontoGravadoI3).toBe("30.00");
    expect(totales.MontoExento).toBe("20.00");
    expect(totales.MontoGravadoTotal).toBe("180.00");
    expect(totales.TotalITBIS).toBe("26.00");
    expect(totales.MontoTotal).toBe("226.00");
  });

  it("aplica el descuento de línea al monto y a la base", () => {
    const result = mapEcfToDosaDraft(
      document([
        { name: "Con descuento", taxCategory: "ITBIS_18", discount: "10.00" },
      ]),
      metadata,
    );

    expect(result.ok).toBe(true);
    if (!result.ok) return;
    const item = result.draft.body.detallesItems[0];
    expect(item.montoItem).toBe("90.00");
    expect(result.draft.body.encabezado.totales.MontoGravadoI1).toBe("90.00");
    expect(result.draft.body.encabezado.totales.TotalITBIS).toBe("16.20");
  });

  it("E32 pequeño se mapea igual y no inventa trackId", () => {
    const result = mapEcfToDosaDraft(
      document([{ name: "Consumo", taxCategory: "ITBIS_18" }], "E32"),
      { encf: "E320000000001" },
    );

    expect(result.ok).toBe(true);
    if (!result.ok) return;
    expect(result.draft.body.encabezado.idDoc.tipoeCF).toBe("32");
    expect(JSON.stringify(result.draft.body)).not.toContain("trackId");
  });

  it("bloquea si la base gravada declarada no coincide con las líneas", () => {
    const doc = document([{ name: "Bien 18", taxCategory: "ITBIS_18" }]);
    doc.totals.taxableBase = "50.00";

    const result = mapEcfToDosaDraft(doc, metadata);

    expect(result.ok).toBe(false);
    if (result.ok) return;
    expect(result.blockedReason).toContain(DOSA_MAPPER_BLOCKED.taxableBaseMismatch);
  });

  it("bloquea si el ITBIS declarado no coincide con las líneas", () => {
    const doc = document([{ name: "Bien 18", taxCategory: "ITBIS_18" }]);
    doc.totals.itbisAmount = "10.00";

    const result = mapEcfToDosaDraft(doc, metadata);

    expect(result.ok).toBe(false);
    if (result.ok) return;
    expect(result.blockedReason).toContain(DOSA_MAPPER_BLOCKED.itbisTotalsMismatch);
  });

  it("bloquea si el exento declarado no coincide con las líneas", () => {
    const doc = document([{ name: "Exento", taxCategory: "EXEMPT" }]);
    doc.totals.exemptAmount = "50.00";

    const result = mapEcfToDosaDraft(doc, metadata);

    expect(result.ok).toBe(false);
    if (result.ok) return;
    expect(result.blockedReason).toContain(DOSA_MAPPER_BLOCKED.taxableBaseMismatch);
  });

  it.each(["43", "6", "21", "17", "23", "41", "57"])(
    "acepta el código de unidad numérico %s del catálogo de la DGII",
    (code) => {
      const result = mapEcfToDosaDraft(
        document([
          { name: "Item", taxCategory: "ITBIS_18", unitOfMeasure: code },
        ]),
        metadata,
      );

      expect(result.ok).toBe(true);
      if (!result.ok) return;
      expect(result.draft.body.detallesItems[0].unidadMedida).toBe(Number(code));
    },
  );

  it("rechaza un código numérico fuera del catálogo (58)", () => {
    const result = mapEcfToDosaDraft(
      document([
        { name: "Item", taxCategory: "ITBIS_18", unitOfMeasure: "58" },
      ]),
      metadata,
    );

    expect(result.ok).toBe(false);
    if (result.ok) return;
    expect(result.blockedReason).toContain(
      DOSA_MAPPER_BLOCKED.unitOfMeasureUnmapped,
    );
  });

  it("no confunde el indicador fiscal con la naturaleza del ítem", () => {
    // Un servicio exento: indicador 4 (exento) y naturaleza 2 (servicio).
    const result = mapEcfToDosaDraft(
      document([
        { name: "Servicio exento", good: "SERVICE", taxCategory: "EXEMPT" },
      ]),
      metadata,
    );

    expect(result.ok).toBe(true);
    if (!result.ok) return;
    const item = result.draft.body.detallesItems[0];
    expect(item.indicadorFacturacion).toBe(4);
    expect(item.indicadorBienoServicio).toBe(2);
  });
});
