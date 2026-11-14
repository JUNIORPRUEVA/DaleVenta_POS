import { assessDosaProviderResponse } from "./dosa-provider-response";
import { classifyDosaResponse } from "./dosa-response.mapper";

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
  const consumerContext = { ...CONTEXT, documentType: "E32" as const, expectedEncf: "E320000000042" };
  function consumerResponse() {
    return {
      trackId: null, codigo: "1", estado: "Aceptado", secuenciaUtilizada: true,
      eNCF: "E320000000042", rncEmisor: "131000001", montoTotal: 118,
      codigoSeguridad: "TEST42", fechaFirma: "12-11-2026 22:33:58",
      urlQR: "https://fc.dgii.gov.do/testecf/consultatimbrefc?RNCEmisor=131000001&ENCF=E320000000042&MontoTotal=118.00",
    };
  }

  it("correlates the observed consumer receipt format without inventing a TrackId or fiscal acceptance", () => {
    const result = assessDosaProviderResponse(200, consumerResponse(), consumerContext);
    expect(result.correlated).toBe(true);
    // This is a local receipt identity, never a fabricated DGII TrackId.
    expect(result.remoteId).toBe("RFCE:SANDBOX:131000001:E320000000042");
    expect(consumerResponse().trackId).toBeNull();
    expect(result.providerOutcome).toBe("ACCEPTED");
    expect(result.canUpdateFiscalStatus).toBe(false);
    expect(result.canRetryPost).toBe(false);
  });

  it.each([
    { rncEmisor: "999999999" },
    { rnc: "999999999" },
    { montoTotal: 250000 },
    { montoTotal: 119 },
    { secuenciaUtilizada: false },
    { urlQR: "https://fc.dgii.gov.do.attacker.invalid/testecf/consultatimbrefc" },
    { urlQR: "https://fc.dgii.gov.do/testecf/consultatimbrefc?RNCEmisor=999999999&ENCF=E320000000042&MontoTotal=118" },
    { urlQR: null },
  ])("rejects incomplete or conflicting RFCE evidence: %j", changes => {
    expect(assessDosaProviderResponse(200, { ...consumerResponse(), ...changes }, consumerContext).correlated).toBe(false);
  });

  it("keeps the TrackId requirement for E31", () => {
    expect(assessDosaProviderResponse(200, consumerResponse(), CONTEXT).correlated).toBe(false);
  });

  it("encodes a literal plus in the observed DGII QR security code without changing its value", () => {
    const result = classifyDosaResponse({ ...consumerResponse(), codigoSeguridad: "Ab+c12",
      urlQR: consumerResponse().urlQR + "&CodigoSeguridad=Ab+c12" });
    const url = new URL(result.qr!.consultaUrl!);
    expect(url.searchParams.get("CodigoSeguridad")).toBe("Ab+c12");
    expect(url.search).toContain("Ab%2Bc12");
    expect(result.qr?.complete).toBe(true);
  });

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
  it("RFCE E32 acceptance without trackId binds a stable receipt identity, never one for E31", () => {
    const encf="E320000000001",rnc="101000001";
    const body={codigo:"1",estado:"Aceptado",rnc,encf,secuenciaUtilizada:true,montoTotal:118,
      url: `https://fc.dgii.gov.do/testecf/ConsultaTimbreFC?RncEmisor=${rnc}&ENCF=${encf}&MontoTotal=118&CodigoSeguridad=ABC123`,
      codigoSeguridad:"ABC123",fechaFirma:"13-11-2026 12:00:00"};
    const observation=assessDosaProviderResponse(200,body,{documentType:"E32",expectedEncf:encf,expectedTaxId:rnc});
    expect(observation.correlated).toBe(true);
    expect(observation.remoteId).toBe(`RFCE:SANDBOX:${rnc}:${encf}`);
    expect(assessDosaProviderResponse(200,body,{documentType:"E31",expectedEncf:encf,expectedTaxId:rnc}).correlated).toBe(false);
  });

});
