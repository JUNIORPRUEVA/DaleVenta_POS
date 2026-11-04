import type { EcfIssuanceMetadata } from "../../fiscal-core/alanube-dom.contract";
import {
  validE31WithItbis,
  validE32Simple,
  validE34Partial,
} from "../../fiscal-core/ecf-fixtures";
import { mapEcfToDosaDraft } from "./dosa-ecf.mapper";
import { DOSA_STATUS_TABLE_CONFLICT } from "./dosa-ecf.contract";

/**
 * Alineación del mapeador con el contrato REAL entregado por el proveedor.
 *
 * La muestra de webhook confirma que el bloque de totales serializa **todas**
 * las claves con dos decimales, incluso cuando valen cero. Estas pruebas fijan
 * esa garantía y las reglas de aislamiento por tipo de comprobante.
 */

const metadataE31: EcfIssuanceMetadata = {
  encf: "E310000000001",
  incomeType: 1,
  paymentType: 1,
};

function totalsOf(document: Parameters<typeof mapEcfToDosaDraft>[0], metadata: EcfIssuanceMetadata) {
  const result = mapEcfToDosaDraft(document, metadata);
  if (!result.ok) throw new Error(`mapeo bloqueado: ${result.blockedReason}`);
  return result.draft.body.encabezado.totales;
}

describe("mapeador DOSA — serialización decimal", () => {
  it("todos los importes salen con dos decimales", () => {
    const totals = totalsOf(validE31WithItbis, metadataE31);
    for (const [key, value] of Object.entries(totals)) {
      if (key === "ITBIS1" || key === "ITBIS2" || key === "ITBIS3") continue;
      expect(value).toMatch(/^-?\d+\.\d{2}$/);
    }
  });

  it("los importes en cero se serializan como 0.00 y no se omiten", () => {
    const totals = totalsOf(validE32Simple, { encf: "E320000000001" });
    expect(Object.keys(totals).sort()).toEqual(
      [
        "ITBIS1",
        "MontoExento",
        "MontoGravadoI1",
        "MontoGravadoTotal",
        "MontoTotal",
        "TotalITBIS",
        "TotalITBIS1",
      ].sort(),
    );
    expect(totals.MontoExento).toBe("0.00");
  });

  it("el cuerpo es JSON-serializable sin perder los importes", () => {
    const result = mapEcfToDosaDraft(validE31WithItbis, metadataE31);
    if (!result.ok) throw new Error(result.blockedReason);
    const roundTrip = JSON.parse(JSON.stringify(result.draft.body)) as {
      encabezado: { totales: Record<string, string> };
    };
    expect(roundTrip.encabezado.totales).toEqual(
      result.draft.body.encabezado.totales,
    );
  });
});

describe("mapeador DOSA — aislamiento por tipo", () => {
  it("E32 (RFCE) no arrastra identificador de seguimiento", () => {
    const result = mapEcfToDosaDraft(validE32Simple, {
      encf: "E320000000001",
    });
    if (!result.ok) throw new Error(result.blockedReason);

    const serialized = JSON.stringify(result.draft.body).toLowerCase();
    expect(serialized).not.toContain("trackid");
    expect(result.draft.body.encabezado.idDoc.tipoeCF).toBe("32");
  });

  it("E34 conserva la integridad del comprobante original", () => {
    const result = mapEcfToDosaDraft(validE34Partial, {
      encf: "E340000000001",
      modificationCode: 3,
    });
    if (!result.ok) throw new Error(result.blockedReason);

    const reference = result.draft.body.informacionReferencia;
    expect(reference).toBeDefined();
    expect(reference?.NCFModificado).toBe(validE34Partial.reference?.originalENcf);
    expect(reference?.codigoModificacion).toBe("3");
    expect(result.draft.body.encabezado.idDoc.tipoeCF).toBe("34");
  });

  it("E34 sin referencia se bloquea (no se emite una nota huérfana)", () => {
    const withoutReference = { ...validE34Partial, reference: undefined };
    const result = mapEcfToDosaDraft(withoutReference, {
      encf: "E340000000001",
    });
    expect(result.ok).toBe(false);
  });

  it("el borrador nunca se declara transmisible", () => {
    const result = mapEcfToDosaDraft(validE31WithItbis, metadataE31);
    expect(result.ok).toBe(true);
    if (result.ok) {
      expect(result.draft.status).toBe("DRAFT_NOT_TRANSMITTABLE");
      expect(result.draft.unverified.length).toBeGreaterThan(0);
    }
  });
});

describe("contrato DOSA — conflicto de estado documentado", () => {
  it("el código 0 sigue marcado como no resuelto", () => {
    expect(DOSA_STATUS_TABLE_CONFLICT.code).toBe("0");
    expect(DOSA_STATUS_TABLE_CONFLICT.resolved).toBe(false);
  });
});
