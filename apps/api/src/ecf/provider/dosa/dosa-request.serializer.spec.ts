import type { DosaEcfRequestBody } from "./dosa-ecf.contract";
import { DosaEmissionClient, type DosaEmissionConfig } from "./dosa-emission.client";
import { toDosaOutboundRequest } from "./dosa-request.serializer";
import { fingerprint } from "../../documents/ecf-document-idempotency.service";

const draft: DosaEcfRequestBody = {
  encabezado: {
    version: "1.0",
    idDoc: { tipoeCF: "32", eNCF: "E320000000001", fechaEmision: "12-11-2026" },
    emisor: { RNCEmisor: "101000001", RazonSocialEmisor: "Empresa de prueba" },
    totales: {
      MontoGravadoTotal: "100.00", MontoGravadoI1: "100.00",
      MontoExento: "0.00", ITBIS1: 18, TotalITBIS: "18.00", MontoTotal: "118.00",
    },
  },
  detallesItems: [{
    numeroLinea: 1, indicadorFacturacion: 1, nombreItem: "Artículo de prueba",
    indicadorBienoServicio: 1, unidadMedida: 43, cantidadItem: "1.00",
    precioUnitarioItem: "100.00", montoItem: "100.00",
  }],
};

describe("DOSA HTTP request envelope regression", () => {
  const config: DosaEmissionConfig = {
    enabled: true, environment: "TEST", baseUrl: "https://dosa.invalid",
    apiKey: "synthetic-test-key", apiKeyIsProduction: false, productionEnabled: false,
    testRnc: "101000001", timeoutMs: 1000, breakerThreshold: 3, breakerCooldownMs: 1000,
  };

  it.each([false, true])("sends items as an object and preserves evidence (already serialized: %s)", async (serialized) => {
    const original = JSON.stringify(draft);
    const outbound = toDosaOutboundRequest(draft);
    const post = jest.fn().mockResolvedValue({ status: 200, body: '{"estado":"Recibido"}' });
    const client = new DosaEmissionClient({ post }, config);
    await client.sendEcf({ body: serialized ? outbound : draft, idempotencyKey: "one-attempt" });
    expect(post).toHaveBeenCalledTimes(1);
    const sent = JSON.parse(post.mock.calls[0][1].body);
    // Official contract: detallesItems is an object with an items array.
    expect(Array.isArray(sent.detallesItems)).toBe(false);
    expect(sent.detallesItems.items).toEqual(draft.detallesItems);
    expect(sent.encabezado.idDoc).toEqual(draft.encabezado.idDoc);
    expect(sent.encabezado.emisor.fechaEmision).toBe("12-11-2026");
    expect(fingerprint(sent)).toBe(fingerprint(outbound));
    expect(JSON.stringify(draft)).toBe(original);
    expect(post.mock.calls[0][1].headers["X-API-KEY"]).toBe(config.apiKey);
    await client.sendEcf({ body: draft, idempotencyKey: "one-attempt" });
    expect(post).toHaveBeenCalledTimes(1);
  });

  it("preserves the original invoice reference and E34 endpoint", async () => {
    const credit: DosaEcfRequestBody = {
      ...draft,
      encabezado: { ...draft.encabezado, idDoc: { ...draft.encabezado.idDoc, tipoeCF: "34", eNCF: "E340000000001" } },
      informacionReferencia: { NCFModificado: "E320000000001", codigoModificacion: "1", FechaNCFModificado: "10-11-2026" },
    };
    const post = jest.fn().mockResolvedValue({ status: 200, body: '{"estado":"Recibido"}' });
    await new DosaEmissionClient({ post }, config).sendEcf({ body: credit, idempotencyKey: "credit-attempt" });
    const url = new URL(post.mock.calls[0][0]);
    expect(url.pathname).toBe("/fe/api/emision/ecf/NotaDesdeFactura");
    expect(url.searchParams.get("nuevoENCF")).toBe("E340000000001");
    expect(url.searchParams.get("codigoModificacion")).toBe("1");
    expect(JSON.parse(post.mock.calls[0][1].body).encabezado.idDoc.eNCF).toBe("E320000000001");
    expect(JSON.parse(post.mock.calls[0][1].body).encabezado.emisor.fechaEmision).toBe("10-11-2026");
    expect(JSON.parse(post.mock.calls[0][1].body).informacionReferencia).toEqual(credit.informacionReferencia);
  });
});
