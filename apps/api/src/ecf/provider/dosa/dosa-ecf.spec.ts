import type { EcfIssuanceMetadata } from "../../fiscal-core/alanube-dom.contract";
import {
  validE31WithItbis,
  validE32Simple,
  validE34Partial,
} from "../../fiscal-core/ecf-fixtures";
import type { EcfFiscalDocument, EcfLine } from "../../fiscal-core/ecf-fiscal-document";
import {
  DOSA_CONTRACT_GAPS,
  DOSA_ERROR_CODES,
  DOSA_STATUS_TABLE_CONFLICT,
  DOSA_TIPOS_ECF,
} from "./dosa-ecf.contract";
import { DOSA_MAPPER_BLOCKED, mapEcfToDosaDraft } from "./dosa-ecf.mapper";
import {
  DOSA_RETRY_POLICY,
  mayRetryAutomatically,
  verifyFiscalIdentity,
  type DosaEmissionOutcome,
} from "./dosa-emission.policy";

const metadata: EcfIssuanceMetadata = {
  encf: "E310000000001",
  paymentType: 1,
  sequenceDueDate: "2027-12-31",
  incomeType: 1,
};

function withLine(overrides: Partial<EcfLine>): EcfFiscalDocument {
  const base: EcfLine = {
    lineNumber: 1,
    name: "Articulo de prueba",
    goodServiceIndicator: "GOOD",
    quantity: "1",
    unitPrice: "100.00",
    discountAmount: "0.00",
    taxCategory: "ITBIS_18",
    taxRate: "0.18",
    unitOfMeasure: "43",
  };
  return { ...validE31WithItbis, lines: [{ ...base, ...overrides }] };
}

describe("contrato DOSA — estructura y brechas declaradas", () => {
  it("mapea los tipos internos a los tipoeCF del proveedor", () => {
    expect(DOSA_TIPOS_ECF).toEqual({ E31: "31", E32: "32", E34: "34" });
  });

  it("declara el conflicto del codigo 0 sin resolverlo", () => {
    expect(DOSA_STATUS_TABLE_CONFLICT.resolved).toBe(false);
    expect(DOSA_STATUS_TABLE_CONFLICT.tableSays).toBe("No encontrado");
    expect(DOSA_STATUS_TABLE_CONFLICT.exampleSays).toBe("Rechazado");
  });

  it("conserva el catálogo público de errores", () => {
    expect(DOSA_ERROR_CODES["1002"]).toMatch(/secuencia/i);
    expect(DOSA_ERROR_CODES["3002"]).toMatch(/nota de cr[eé]dito/i);
  });

  it("enumera los huecos que impiden transmitir", () => {
    expect(DOSA_CONTRACT_GAPS.length).toBeGreaterThan(0);
    expect(DOSA_CONTRACT_GAPS.join(" ")).toMatch(/fecha/i);
    expect(DOSA_CONTRACT_GAPS.join(" ")).toMatch(/indicadorFacturacion/i);
  });
});

describe("mapeador DOSA — E31, E32 y E34", () => {
  it("E31 produce el cuerpo con emisor, comprador y totales", () => {
    const result = mapEcfToDosaDraft(validE31WithItbis, metadata);
    expect(result.ok).toBe(true);
    if (!result.ok) return;

    const body = result.draft.body;
    expect(result.draft.status).toBe("DRAFT_NOT_TRANSMITTABLE");
    expect(body.encabezado.idDoc.tipoeCF).toBe("31");
    expect(body.encabezado.idDoc.eNCF).toBe("E310000000001");
    expect(body.encabezado.idDoc.fechaEmision).toBe("14-10-2026");
    expect(body.encabezado.emisor).toEqual({
      RNCEmisor: "101000001",
      RazonSocialEmisor: "FULLPOS PRUEBAS SRL",
    });
    expect(body.encabezado.comprador?.RNCComprador).toBe("101000002");
    expect(body.encabezado.totales.MontoTotal).toBe("118.00");
    expect(body.encabezado.totales.TotalITBIS).toBe("18.00");
    expect(body.encabezado.totales.MontoGravadoI1).toBe("100.00");
    expect(body.informacionReferencia).toBeUndefined();
  });

  it("E32 usa tipoeCF 32", () => {
    const result = mapEcfToDosaDraft(validE32Simple, {
      ...metadata,
      encf: "E320000000001",
    });
    expect(result.ok).toBe(true);
    if (!result.ok) return;
    expect(result.draft.body.encabezado.idDoc.tipoeCF).toBe("32");
    expect(result.draft.documentType).toBe("E32");
  });

  it("E34 incluye la información de referencia del comprobante original", () => {
    const result = mapEcfToDosaDraft(validE34Partial, {
      ...metadata,
      encf: "E340000000001",
    });
    expect(result.ok).toBe(true);
    if (!result.ok) return;

    expect(result.draft.body.encabezado.idDoc.tipoeCF).toBe("34");
    expect(result.draft.body.informacionReferencia).toMatchObject({
      NCFModificado: "E310000000001",
      codigoModificacion: "1",
      RazonModificacion: "Devolucion parcial de prueba",
      FechaNCFModificado: "13-10-2026",
    });
  });

  it("el importe de la línea es cantidad x precio menos descuento", () => {
    const doc = withLine({ quantity: "3", unitPrice: "33.33", discountAmount: "9.99" });
    const result = mapEcfToDosaDraft(doc, metadata);
    expect(result.ok).toBe(true);
    if (!result.ok) return;

    const item = result.draft.body.detallesItems[0];
    expect(item.numeroLinea).toBe(1);
    expect(Number(item.cantidadItem)).toBe(3);
    expect(item.precioUnitarioItem).toBe("33.33");
    // 3 x 33.33 = 99.99 ; 99.99 - 9.99 = 90.00
    expect(item.montoItem).toBe("90.00");
  });

  it("usa la naturaleza del ítem para indicadorFacturacion y no la categoría de impuesto", () => {
    const productoGravado = mapEcfToDosaDraft(withLine({}), metadata);
    const productoServicioExento = mapEcfToDosaDraft(
      withLine({ taxCategory: "EXEMPT", taxRate: "0" }),
      metadata,
    );
    const servicioGravado = mapEcfToDosaDraft(
      withLine({ goodServiceIndicator: "SERVICE" }),
      metadata,
    );

    // 1 = Producto, 2 = Servicio. La categoría de impuesto NO cambia la naturaleza.
    expect(productoGravado.ok && productoGravado.draft.body.detallesItems[0].indicadorFacturacion).toBe(1);
    expect(productoServicioExento.ok && productoServicioExento.draft.body.detallesItems[0].indicadorFacturacion).toBe(1);
    expect(servicioGravado.ok && servicioGravado.draft.body.detallesItems[0].indicadorFacturacion).toBe(2);
  });

  it("distingue bien de servicio con los códigos de DOSA (1 = servicio, 2 = bien)", () => {
    const bien = mapEcfToDosaDraft(withLine({}), metadata);
    const servicio = mapEcfToDosaDraft(
      withLine({ goodServiceIndicator: "SERVICE" }),
      metadata,
    );

    expect(bien.ok && bien.draft.body.detallesItems[0].indicadorBienoServicio).toBe(2);
    expect(servicio.ok && servicio.draft.body.detallesItems[0].indicadorBienoServicio).toBe(1);
  });

  it("rechaza el documento cuando falta la unidad de medida", () => {
    const result = mapEcfToDosaDraft(
      withLine({ unitOfMeasure: undefined }),
      metadata,
    );
    expect(result.ok).toBe(false);
    if (result.ok) return;
    expect(result.blockedReason).toBe(
      `${DOSA_MAPPER_BLOCKED.unitOfMeasureRequired}:1`,
    );
  });

  it("rechaza la línea sin unidad aunque el resto del documento sea válido", () => {
    const result = mapEcfToDosaDraft(
      withLine({ lineNumber: 7, unitOfMeasure: "   " }),
      metadata,
    );
    expect(result.ok).toBe(false);
    if (result.ok) return;
    expect(result.blockedReason).toBe(
      `${DOSA_MAPPER_BLOCKED.unitOfMeasureRequired}:7`,
    );
  });

  it("transmite la unidad de medida tal como la informa el ítem", () => {
    const result = mapEcfToDosaDraft(
      withLine({ unitOfMeasure: " UND " }),
      metadata,
    );
    expect(result.ok).toBe(true);
    if (!result.ok) return;
    expect(result.draft.body.detallesItems[0].unidadMedida).toBe("UND");
  });

  it("marca el borrador como no verificado en los puntos dudosos", () => {
    const result = mapEcfToDosaDraft(validE31WithItbis, metadata);
    expect(result.ok).toBe(true);
    if (!result.ok) return;

    expect(result.draft.unverified.length).toBeGreaterThan(0);
    const joined = result.draft.unverified.join(" ");
    expect(joined).toMatch(/fecha/i);
    expect(joined).toMatch(/unidadMedida/i);
    expect(joined).toMatch(/paginacion/i);
  });
});

describe("mapeador DOSA — falla cerrado", () => {
  it("sin e-NCF válido no hay borrador", () => {
    expect(mapEcfToDosaDraft(validE31WithItbis, { ...metadata, encf: "" })).toEqual({
      ok: false,
      blockedReason: DOSA_MAPPER_BLOCKED.missingEncf,
    });
    expect(
      mapEcfToDosaDraft(validE31WithItbis, { ...metadata, encf: "E320000000001" }),
    ).toEqual({ ok: false, blockedReason: DOSA_MAPPER_BLOCKED.missingEncf });
  });

  it("una moneda distinta de DOP se bloquea", () => {
    expect(
      mapEcfToDosaDraft({ ...validE31WithItbis, currency: "USD" }, metadata),
    ).toEqual({ ok: false, blockedReason: DOSA_MAPPER_BLOCKED.unsupportedCurrency });
  });

  it("una nota de crédito sin referencia se bloquea", () => {
    const { reference: _removed, ...sinReferencia } = validE34Partial;
    expect(
      mapEcfToDosaDraft(sinReferencia as EcfFiscalDocument, {
        ...metadata,
        encf: "E340000000001",
      }),
    ).toEqual({ ok: false, blockedReason: DOSA_MAPPER_BLOCKED.referenceRequired });
  });

  it("campos no soportados bloquean en lugar de ignorarse", () => {
    expect(
      mapEcfToDosaDraft(
        { ...validE31WithItbis, unsupportedFields: { algo: true } },
        metadata,
      ),
    ).toEqual({ ok: false, blockedReason: DOSA_MAPPER_BLOCKED.unsupportedFields });
  });
});

describe("política DOSA — sin reintentos automáticos", () => {
  it("ningún desenlace permite reintento automático", () => {
    const outcomes: DosaEmissionOutcome[] = [
      { kind: "NOT_SENT" },
      { kind: "UNKNOWN" },
      { kind: "REJECTED", codes: ["1002"] },
      { kind: "IN_PROCESS" },
      { kind: "ACCEPTED" },
    ];
    for (const outcome of outcomes) {
      const decision = mayRetryAutomatically(outcome);
      expect(decision.allowed).toBe(false);
      expect(decision.reason).toMatch(/ECF_DOSA_NO_AUTOMATIC_RETRY/);
    }
  });

  it("el resultado incierto exige reconciliación humana", () => {
    expect(DOSA_RETRY_POLICY.maxAttemptsPerDocument).toBe(1);
    expect(DOSA_RETRY_POLICY.retryOnUnknown).toBe(false);
    expect(DOSA_RETRY_POLICY.retryOnTimeout).toBe(false);
    expect(DOSA_RETRY_POLICY.requiresHumanReconciliationOnUnknown).toBe(true);
  });
});

describe("política DOSA — identidad fiscal de prueba separada", () => {
  it("en TEST exige el RNC de prueba configurado", () => {
    expect(
      verifyFiscalIdentity({
        environment: "test",
        senderTaxId: "101000001",
        configuredTestRnc: null,
      }),
    ).toEqual({ ok: false, reason: "TEST_RNC_NOT_CONFIGURED" });
  });

  it("en TEST rechaza un RNC distinto del de prueba", () => {
    // Escenario real a evitar: usar el RNC real de la empresa en un flujo TEST.
    expect(
      verifyFiscalIdentity({
        environment: "test",
        senderTaxId: "130000000",
        configuredTestRnc: "101000001",
      }),
    ).toEqual({ ok: false, reason: "TEST_RNC_MISMATCH" });
  });

  it("en TEST acepta el RNC de prueba, con o sin separadores", () => {
    expect(
      verifyFiscalIdentity({
        environment: "test",
        // 1-01-00000-1 normaliza a 101000001.
        senderTaxId: "1-01-00000-1",
        configuredTestRnc: "101000001",
      }),
    ).toEqual({ ok: true });
  });

  it("en producción no impone el RNC de prueba, pero exige uno", () => {
    expect(
      verifyFiscalIdentity({
        environment: "production",
        senderTaxId: "101000001",
        configuredTestRnc: null,
      }),
    ).toEqual({ ok: true });
    expect(
      verifyFiscalIdentity({
        environment: "production",
        senderTaxId: "  ",
        configuredTestRnc: null,
      }),
    ).toEqual({ ok: false, reason: "SENDER_RNC_MISSING" });
  });
});
