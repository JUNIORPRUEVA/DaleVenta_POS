import { validE31WithItbis, validE32Simple, validE34Partial } from "../../fiscal-core/ecf-fixtures";
import { mapEcfToDosaDraft } from "./dosa-ecf.mapper";
import { toDosaOutboundRequest } from "./dosa-request.serializer";
import { emissionPathFor } from "./dosa-emission.client";

describe("Complete DOSA outbound fiscal metadata", () => {
  it("preserves credit terms, sequence expiry, issuer address and recorded payment forms", () => {
    const mapped = mapEcfToDosaDraft({ ...validE31WithItbis, paymentForms: [{ code: "4", amount: "118.00" }] }, {
      encf: "E310000000001", incomeType: 6, paymentType: 2,
      paymentDeadline: "2026-12-15", sequenceDueDate: "2028-12-31",
    });
    if (!mapped.ok) throw Error(mapped.blockedReason);
    const request = toDosaOutboundRequest(mapped.draft.body);
    expect(request.encabezado.idDoc).toMatchObject({
      tipoIngresos: "06", tipoPago: 2, indicadorMontoGravado: 0,
      fechaLimitePago: "15-12-2026", fechavencimientosecuencia: "31-12-2028",
      tablaFormasPago: { formaDePago: [{ formaPago: "4", montoPago: "118.00" }] },
    });
    expect(request.encabezado.emisor.direccionEmisor).toBe(validE31WithItbis.sender.address);
    expect(request.encabezado.emisor.fechaEmision).toBe("14-10-2026");
  });

  it("does not attach a sequence expiry to E32", () => {
    const mapped = mapEcfToDosaDraft(validE32Simple, {
      encf: "E320000000001", incomeType: 1, paymentType: 1, sequenceDueDate: "2028-12-31",
    });
    if (!mapped.ok) throw Error(mapped.blockedReason);
    expect(toDosaOutboundRequest(mapped.draft.body).encabezado.idDoc.fechavencimientosecuencia).toBeUndefined();
  });

  it("separates the new E34 number and date from the original invoice in NotaDesdeFactura", () => {
    const mapped = mapEcfToDosaDraft(validE34Partial, {
      encf: "E340000000002", incomeType: 1, paymentType: 1, modificationCode: 3,
    });
    if (!mapped.ok) throw Error(mapped.blockedReason);
    const path = new URL(emissionPathFor(mapped.draft.body), "https://dosa.invalid");
    const request = toDosaOutboundRequest(mapped.draft.body);
    expect(path.searchParams.get("nuevoENCF")).toBe("E340000000002");
    expect(path.searchParams.get("codigoModificacion")).toBe("3");
    expect(request.encabezado.idDoc.eNCF).toBe(validE34Partial.reference?.originalENcf);
    expect(request.encabezado.idDoc.tipoeCF).toBe("31");
    expect(request.encabezado.idDoc.tablaFormasPago).toBeUndefined();
    expect(request.encabezado.idDoc.fechavencimientosecuencia).toBeUndefined();
    expect(request.encabezado.emisor.fechaEmision).toBe(mapped.draft.body.informacionReferencia?.FechaNCFModificado);
  });
});
