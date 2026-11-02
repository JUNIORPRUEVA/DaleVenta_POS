import type { EcfIssuanceMetadata } from "../../fiscal-core/alanube-dom.contract";
import {
  validE31Mixed,
  validE31WithDiscount,
  validE31WithItbis,
  validE32Simple,
  validE34Partial,
} from "../../fiscal-core/ecf-fixtures";
import type { DosaEcfRequestBody } from "./dosa-ecf.contract";
import {
  DOSA_BARRIER_BLOCKED,
  assessDosaDocumentBarrier,
} from "./dosa-emission.barrier";
import { mapEcfToDosaDraft } from "./dosa-ecf.mapper";
import { DosaEmissionService } from "./dosa-emission.service";
import type { DosaCredentialService } from "./dosa-credential.service";
import type {
  DosaEmissionConfig,
  DosaHttpResponse,
  DosaHttpTransport,
} from "./dosa-emission.client";

/**
 * Pruebas de la barrera del punto de envío.
 *
 * El objetivo concreto: **un borrador no se convierte en comprobante
 * transmisible por extraer su JSON**, y la barrera sigue decidiendo aunque la
 * configuración esté encendida. Todo es sintético: no hay red, ni base de datos,
 * ni secretos.
 */

const SENDER_RNC = "101000001";

const metadata: EcfIssuanceMetadata = {
  encf: "E310000000001",
  paymentType: 1,
  sequenceDueDate: "2027-12-31",
  incomeType: 1,
};

function bodyOf(document: Parameters<typeof mapEcfToDosaDraft>[0], meta = metadata): DosaEcfRequestBody {
  const mapped = mapEcfToDosaDraft(document, meta);
  if (!mapped.ok) {
    throw new Error(`fixture no mapeable: ${mapped.blockedReason}`);
  }
  return mapped.draft.body;
}

function clone<T>(value: T): T {
  return JSON.parse(JSON.stringify(value)) as T;
}

const ctx = { documentType: "E31" as const, companyRnc: SENDER_RNC };

describe("barrera DOSA — cuerpos válidos del mapeador", () => {
  it("acepta un E31 gravado generado por el mapeador", () => {
    const decision = assessDosaDocumentBarrier(bodyOf(validE31WithItbis), ctx);
    expect(decision.blockingReasons).toEqual([]);
    expect(decision.allowed).toBe(true);
  });

  it("acepta un E31 mixto (bien y servicio) y uno con descuento", () => {
    expect(
      assessDosaDocumentBarrier(bodyOf(validE31Mixed), ctx).allowed,
    ).toBe(true);
    expect(
      assessDosaDocumentBarrier(bodyOf(validE31WithDiscount), ctx).allowed,
    ).toBe(true);
  });

  it("acepta un E32 y un E34 con su referencia", () => {
    const e32 = bodyOf(validE32Simple, { ...metadata, encf: "E320000000001" });
    expect(
      assessDosaDocumentBarrier(e32, { documentType: "E32", companyRnc: SENDER_RNC })
        .allowed,
    ).toBe(true);

    const e34 = bodyOf(validE34Partial, { ...metadata, encf: "E340000000001" });
    expect(
      assessDosaDocumentBarrier(e34, { documentType: "E34", companyRnc: SENDER_RNC })
        .allowed,
    ).toBe(true);
  });
});

describe("barrera DOSA — un borrador no es transmisible", () => {
  it("rechaza el borrador completo en lugar del cuerpo", () => {
    const mapped = mapEcfToDosaDraft(validE31WithItbis, metadata);
    expect(mapped.ok).toBe(true);
    if (!mapped.ok) return;

    // El objeto que devuelve el mapeador (y que expone el puerto del proveedor
    // como `payload`) NO es el cuerpo: enviarlo así debe bloquearse.
    const decision = assessDosaDocumentBarrier(mapped.draft, ctx);
    expect(decision.allowed).toBe(false);
    expect(decision.blockingReasons).toContain(
      `${DOSA_BARRIER_BLOCKED.unexpectedShape}:status`,
    );
  });

  it("rechaza un cuerpo envuelto en `body`/`payload`", () => {
    const inner = bodyOf(validE31WithItbis);
    expect(
      assessDosaDocumentBarrier({ body: inner }, ctx).allowed,
    ).toBe(false);
    expect(
      assessDosaDocumentBarrier({ payload: inner }, ctx).allowed,
    ).toBe(false);
    expect(
      assessDosaDocumentBarrier({ ok: true, payload: inner }, ctx).allowed,
    ).toBe(false);
  });

  it("rechaza cualquier cuerpo distinto del borrador declarado por el llamador", () => {
    const draft = bodyOf(validE31WithItbis);
    const rebuilt = clone(draft);
    const decision = assessDosaDocumentBarrier(rebuilt, {
      ...ctx,
      draftBody: draft,
    });
    expect(decision.allowed).toBe(false);
    expect(decision.blockingReasons).toContain(
      `${DOSA_BARRIER_BLOCKED.unexpectedShape}:DRAFT_BODY_REPLACED`,
    );
  });

  it("acepta cuando el cuerpo ES el borrador declarado", () => {
    const draft = bodyOf(validE31WithItbis);
    expect(assessDosaDocumentBarrier(draft, { ...ctx, draftBody: draft }).allowed).toBe(
      true,
    );
  });
});

describe("barrera DOSA — datos fiscales obligatorios", () => {
  it("rechaza la línea sin unidad de medida", () => {
    const body = clone(bodyOf(validE31WithItbis));
    delete (body.detallesItems[0] as Partial<DosaEcfRequestBody["detallesItems"][number]>)
      .unidadMedida;

    const decision = assessDosaDocumentBarrier(body, ctx);
    expect(decision.allowed).toBe(false);
    expect(decision.blockingReasons).toContain(
      `${DOSA_BARRIER_BLOCKED.itemUnitMissing}:#1`,
    );
  });

  it("rechaza una unidad de medida en blanco", () => {
    const body = clone(bodyOf(validE31WithItbis));
    body.detallesItems[0].unidadMedida = "   ";

    expect(
      assessDosaDocumentBarrier(body, ctx).blockingReasons,
    ).toContain(`${DOSA_BARRIER_BLOCKED.itemUnitMissing}:#1`);
  });

  it("rechaza indicadores fuera de catálogo", () => {
    const body = clone(bodyOf(validE31WithItbis));
    body.detallesItems[0].indicadorFacturacion = 9 as unknown as 1;
    body.detallesItems[0].indicadorBienoServicio = 0 as unknown as 2;

    const reasons = assessDosaDocumentBarrier(body, ctx).blockingReasons;
    expect(reasons).toContain(
      `${DOSA_BARRIER_BLOCKED.itemInvalid}:#1:INDICADOR_FACTURACION`,
    );
    expect(reasons).toContain(
      `${DOSA_BARRIER_BLOCKED.itemInvalid}:#1:INDICADOR_BIENO_SERVICIO`,
    );
  });

  it("rechaza cantidad cero o precio no numérico", () => {
    const body = clone(bodyOf(validE31WithItbis));
    body.detallesItems[0].cantidadItem = "0";
    body.detallesItems[0].precioUnitarioItem = "ciento";

    const reasons = assessDosaDocumentBarrier(body, ctx).blockingReasons;
    expect(reasons).toContain(`${DOSA_BARRIER_BLOCKED.itemInvalid}:#1:CANTIDAD`);
    expect(reasons).toContain(
      `${DOSA_BARRIER_BLOCKED.itemInvalid}:#1:PRECIO_UNITARIO`,
    );
  });

  it("rechaza un documento sin líneas", () => {
    const body = clone(bodyOf(validE31WithItbis));
    body.detallesItems = [];
    expect(assessDosaDocumentBarrier(body, ctx).blockingReasons).toContain(
      DOSA_BARRIER_BLOCKED.itemsEmpty,
    );
  });

  it("rechaza el número de línea repetido", () => {
    const body = clone(bodyOf(validE31Mixed));
    body.detallesItems[1].numeroLinea = body.detallesItems[0].numeroLinea;
    expect(assessDosaDocumentBarrier(body, ctx).blockingReasons).toContain(
      `${DOSA_BARRIER_BLOCKED.itemInvalid}:#2:NUMERO_LINEA`,
    );
  });
});

describe("barrera DOSA — identidad y tipo de documento", () => {
  it("rechaza el emisor de otra empresa", () => {
    const body = clone(bodyOf(validE31WithItbis));
    const decision = assessDosaDocumentBarrier(body, {
      ...ctx,
      companyRnc: "133306001",
    });
    expect(decision.allowed).toBe(false);
    expect(decision.blockingReasons).toContain(
      DOSA_BARRIER_BLOCKED.senderRncMismatch,
    );
  });

  it("rechaza el emisor vacío", () => {
    const body = clone(bodyOf(validE31WithItbis));
    body.encabezado.emisor.RNCEmisor = " ";
    expect(assessDosaDocumentBarrier(body, ctx).blockingReasons).toContain(
      DOSA_BARRIER_BLOCKED.senderRncMissing,
    );
  });

  it("rechaza un eNCF que no corresponde al tipo declarado", () => {
    const body = clone(bodyOf(validE31WithItbis));
    expect(
      assessDosaDocumentBarrier(body, { ...ctx, documentType: "E32" })
        .blockingReasons,
    ).toContain(
      `${DOSA_BARRIER_BLOCKED.documentTypeMismatch}:32/31`,
    );
  });

  it("rechaza un eNCF malformado", () => {
    const body = clone(bodyOf(validE31WithItbis));
    body.encabezado.idDoc.eNCF = "E31-1";
    expect(assessDosaDocumentBarrier(body, ctx).blockingReasons).toContain(
      DOSA_BARRIER_BLOCKED.encfMalformed,
    );
  });

  it("rechaza una fecha de emisión ausente", () => {
    const body = clone(bodyOf(validE31WithItbis));
    body.encabezado.idDoc.fechaEmision = "";
    expect(assessDosaDocumentBarrier(body, ctx).blockingReasons).toContain(
      DOSA_BARRIER_BLOCKED.issueDateMissing,
    );
  });
});

describe("barrera DOSA — totales", () => {
  it("rechaza totales que no cuadran con las líneas", () => {
    const body = clone(bodyOf(validE31WithItbis));
    body.encabezado.totales.MontoTotal = "1.00";

    expect(assessDosaDocumentBarrier(body, ctx).blockingReasons).toContain(
      `${DOSA_BARRIER_BLOCKED.totalsIncoherent}:MONTO_TOTAL`,
    );
  });

  it("rechaza una suma de líneas distinta del gravado más exento", () => {
    const body = clone(bodyOf(validE31WithItbis));
    body.encabezado.totales.MontoGravadoTotal = "0.01";
    body.encabezado.totales.MontoGravadoI1 = "0.01";
    body.encabezado.totales.MontoTotal = body.encabezado.totales.TotalITBIS;

    expect(assessDosaDocumentBarrier(body, ctx).blockingReasons).toContain(
      `${DOSA_BARRIER_BLOCKED.totalsIncoherent}:SUMA_LINEAS`,
    );
  });

  it("rechaza totales ausentes", () => {
    const body = clone(bodyOf(validE31WithItbis));
    const header = body.encabezado as Record<string, unknown>;
    delete header["totales"];
    expect(assessDosaDocumentBarrier(body, ctx).blockingReasons).toContain(
      DOSA_BARRIER_BLOCKED.totalsMissing,
    );
  });
});

describe("barrera DOSA — referencia del comprobante original", () => {
  it("rechaza un E34 sin referencia", () => {
    const body = clone(bodyOf(validE34Partial, { ...metadata, encf: "E340000000001" }));
    delete (body as Partial<DosaEcfRequestBody>).informacionReferencia;

    expect(
      assessDosaDocumentBarrier(body, { documentType: "E34", companyRnc: SENDER_RNC })
        .blockingReasons,
    ).toContain(DOSA_BARRIER_BLOCKED.referenceMissing);
  });

  it("rechaza un E31 que arrastra referencia", () => {
    const body = clone(bodyOf(validE31WithItbis));
    body.informacionReferencia = {
      NCFModificado: "E310000000000",
      codigoModificacion: "1",
    };
    expect(assessDosaDocumentBarrier(body, ctx).blockingReasons).toContain(
      DOSA_BARRIER_BLOCKED.referenceUnexpected,
    );
  });
});

describe("barrera DOSA — cuerpo que no es un objeto", () => {
  it.each([[null], [undefined], ["{json}"], [[{ encabezado: {} }]], [42]])(
    "rechaza %p",
    (value) => {
      expect(assessDosaDocumentBarrier(value, ctx).blockingReasons).toContain(
        DOSA_BARRIER_BLOCKED.bodyNotObject,
      );
    },
  );
});

// ---------------------------------------------------------------------------
// Integración con el servicio de emisión: el documento inválido no llega nunca
// al cliente HTTP, aunque TODA la configuración esté encendida.
// ---------------------------------------------------------------------------

class FakeTransport implements DosaHttpTransport {
  calls: string[] = [];
  async post(url: string): Promise<DosaHttpResponse> {
    this.calls.push(url);
    return {
      status: 200,
      body: JSON.stringify({ data: { codigo: 1 } }),
    };
  }
}

function emissionConfig(): DosaEmissionConfig {
  return {
    enabled: true,
    environment: "TEST",
    baseUrl: "https://sandbox.invalid",
    apiKey: "TEST-KEY-SINTETICA",
    apiKeyIsProduction: false,
    productionEnabled: false,
    testRnc: SENDER_RNC,
    timeoutMs: 50,
    breakerThreshold: 3,
    breakerCooldownMs: 60_000,
  };
}

function buildService(transport: FakeTransport) {
  const credentialCalls: string[] = [];
  const credentials = {
    async inspect() {
      credentialCalls.push("inspect");
      return {
        status: "ACTIVE",
        environment: "test",
        fingerprint: "fp-sintetica",
      };
    },
    async openForEmission() {
      credentialCalls.push("openForEmission");
      return { apiKeyTest: "TEST-KEY-SINTETICA" };
    },
  } as unknown as DosaCredentialService;

  const service = new DosaEmissionService({
    fiscalConfig: {
      async read() {
        credentialCalls.push("fiscalConfig");
        return { ecfEnabled: true, provider: "DOSA" };
      },
    },
    credentials,
    config: emissionConfig(),
    transport,
  });

  return { service, credentialCalls };
}

describe("DosaEmissionService — la barrera decide aunque la configuración esté encendida", () => {
  it("no abre credenciales ni hace red con un borrador como cuerpo", async () => {
    const transport = new FakeTransport();
    const { service, credentialCalls } = buildService(transport);

    const mapped = mapEcfToDosaDraft(validE31WithItbis, metadata);
    expect(mapped.ok).toBe(true);
    if (!mapped.ok) return;

    const result = await service.emit({
      companyId: "11111111-1111-4111-8111-111111111111",
      rnc: SENDER_RNC,
      documentType: "E31",
      senderTaxId: SENDER_RNC,
      sequenceAvailable: true,
      // Aunque todo lo demás está autorizado, esto no es el cuerpo:
      // es el borrador completo.
      body: mapped.draft as unknown as DosaEcfRequestBody,
    });

    expect(result.ok).toBe(false);
    if (result.ok) return;
    expect(result.code).toBe("ECF_DOSA_DOCUMENT_BLOCKED");
    expect(transport.calls).toHaveLength(0);
    expect(credentialCalls).toEqual([]);
  });

  it("no envía un cuerpo sin unidad de medida", async () => {
    const transport = new FakeTransport();
    const { service, credentialCalls } = buildService(transport);

    const body = clone(bodyOf(validE31WithItbis));
    delete (body.detallesItems[0] as Partial<DosaEcfRequestBody["detallesItems"][number]>)
      .unidadMedida;

    const result = await service.emit({
      companyId: "11111111-1111-4111-8111-111111111111",
      rnc: SENDER_RNC,
      documentType: "E31",
      senderTaxId: SENDER_RNC,
      sequenceAvailable: true,
      body,
    });

    expect(result.ok).toBe(false);
    if (result.ok) return;
    expect(result.code).toBe("ECF_DOSA_DOCUMENT_BLOCKED");
    expect(result.blockingReasons).toContain(
      `${DOSA_BARRIER_BLOCKED.itemUnitMissing}:#1`,
    );
    expect(transport.calls).toHaveLength(0);
    expect(credentialCalls).toEqual([]);
  });

  it("no envía el comprobante de otra empresa", async () => {
    const transport = new FakeTransport();
    const { service } = buildService(transport);

    const result = await service.emit({
      companyId: "11111111-1111-4111-8111-111111111111",
      rnc: "133306001",
      documentType: "E31",
      senderTaxId: "133306001",
      sequenceAvailable: true,
      body: clone(bodyOf(validE31WithItbis)),
    });

    expect(result.ok).toBe(false);
    if (result.ok) return;
    expect(result.blockingReasons).toContain(
      DOSA_BARRIER_BLOCKED.senderRncMismatch,
    );
    expect(transport.calls).toHaveLength(0);
  });

  it("con un cuerpo válido sí llega a la compuerta y, autorizado, envía", async () => {
    const transport = new FakeTransport();
    const { service, credentialCalls } = buildService(transport);

    const result = await service.emit({
      companyId: "11111111-1111-4111-8111-111111111111",
      rnc: SENDER_RNC,
      documentType: "E31",
      senderTaxId: SENDER_RNC,
      sequenceAvailable: true,
      body: bodyOf(validE31WithItbis),
    });

    expect(result.ok).toBe(true);
    expect(transport.calls).toHaveLength(1);
    expect(credentialCalls).toContain("openForEmission");
  });
});
