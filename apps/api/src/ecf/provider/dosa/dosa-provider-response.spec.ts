import { assessDosaProviderResponse } from "./dosa-provider-response";

/**
 * Correlación de la respuesta de DOSA.
 *
 * El defecto que este archivo protege: el evaluador común está modelado sobre
 * Alanube (`id` ULID, `documentNumber`, `legalStatus`) y una respuesta real de
 * DOSA (`trackId`, `encf`, `estado`) nunca correlacionaba, así que toda emisión
 * quedaba como «resultado desconocido» aunque el proveedor hubiera contestado.
 *
 * Se comprueba además que NINGUNA respuesta concede aceptación fiscal.
 */
const CONTEXT = {
  documentType: "E31" as const,
  expectedEncf: "E310000000042",
  expectedTaxId: "131000001",
};

function response(overrides: Record<string, unknown> = {}) {
  return {
    trackId: "4cdc9917-8008-4564-a85c-c3f13a4e0ec8",
    codigo: "4",
    estado: "Aceptado Condicional",
    rnc: "131000001",
    encf: "E310000000042",
    url: "https://ecf.dgii.gov.do/testecf/consulta",
    codigoSeguridad: "EAkbyR",
    fechaFirma: "15-11-2025 14:46:41",
    secuenciaUtilizada: true,
    fechaRecepcion: "2025-11-15T10:46:42",
    mensajes: [],
    ...overrides,
  };
}

describe("assessDosaProviderResponse", () => {
  it("correlaciona una respuesta conforme y NO la convierte en aceptación fiscal", () => {
    const result = assessDosaProviderResponse(200, response(), CONTEXT);

    expect(result.correlated).toBe(true);
    expect(result.observedOutcome).toBe("ACCEPTED");
    expect(result.observedLegalStatus).toBe("Aceptado Condicional");
    expect(result.remoteId).toBe("4cdc9917-8008-4564-a85c-c3f13a4e0ec8");
    // Invariante: desde aquí nunca se actualiza el estado fiscal.
    expect(result.canUpdateFiscalStatus).toBe(false);
    expect(result.canRetryPost).toBe(false);
    expect(JSON.stringify(result)).not.toContain("DGII_ACCEPTED");
  });

  it("un rechazo correlacionado se reporta como rechazo", () => {
    const result = assessDosaProviderResponse(
      200,
      response({ codigo: "2", estado: "Rechazado", secuenciaUtilizada: false }),
      CONTEXT,
    );
    expect(result.correlated).toBe(true);
    expect(result.observedOutcome).toBe("REJECTED");
    expect(result.sequenceConsumed).toBe(false);
  });

  it("202 Pendiente DGII correlaciona como pendiente", () => {
    const result = assessDosaProviderResponse(202, response({ codigo: "3", estado: "En Proceso" }), CONTEXT);
    expect(result.correlated).toBe(true);
    expect(result.observedOutcome).toBe("PENDING");
  });

  it("un e-NCF de otra operación NO correlaciona", () => {
    const result = assessDosaProviderResponse(200, response({ encf: "E310000000099" }), CONTEXT);
    expect(result.correlated).toBe(false);
    expect(result.reasons).toContain("ENCF_MATCH");
    expect(result.remoteId).toBeNull();
  });

  it("un RNC de otra empresa NO correlaciona", () => {
    const result = assessDosaProviderResponse(200, response({ rnc: "999999999" }), CONTEXT);
    expect(result.correlated).toBe(false);
    expect(result.reasons).toContain("RNC_MATCH");
  });

  it("una respuesta sin trackId no correlaciona", () => {
    const result = assessDosaProviderResponse(200, response({ trackId: undefined }), CONTEXT);
    expect(result.correlated).toBe(false);
    expect(result.reasons).toContain("TRACK_ID_PRESENT");
  });

  it("un cuerpo ilegible no correlaciona", () => {
    const result = assessDosaProviderResponse(200, "<html>no es json</html>", CONTEXT);
    expect(result.correlated).toBe(false);
    expect(result.reasons).toContain("BODY_READABLE");
  });

  it("un HTTP 500 no correlaciona aunque el cuerpo parezca válido", () => {
    const result = assessDosaProviderResponse(500, response(), CONTEXT);
    expect(result.correlated).toBe(false);
    expect(result.reasons).toContain("HTTP_ACCEPTABLE");
  });

  it("un aceptado sin secuencia consumida es incoherente y no correlaciona", () => {
    const result = assessDosaProviderResponse(
      200,
      response({ secuenciaUtilizada: undefined }),
      CONTEXT,
    );
    expect(result.correlated).toBe(false);
    expect(result.reasons).toContain("SEQUENCE_CONSISTENT");
  });
});
