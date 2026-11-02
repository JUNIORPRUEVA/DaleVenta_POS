import {
  ECF_POSTULATION_XML_ERRORS,
  inspectPostulationXml,
} from "./ecf-postulation-xml.policy";

const valid = (extra = "") =>
  Buffer.from(
    `<?xml version="1.0" encoding="UTF-8"?>\n<PostulacionEmisor>${extra}</PostulacionEmisor>`,
    "utf8",
  );

function inspect(bytes: Buffer, taxId?: string, fileName = "postulacion.xml") {
  return inspectPostulationXml({
    bytes,
    sizeBytes: bytes.length,
    expectedTaxId: taxId ?? null,
    fileName,
  });
}

describe("XML de postulación — acepta lo que corresponde", () => {
  it("acepta un XML UTF-8 de datos con raíz de postulación", () => {
    const result = inspect(valid("<RNC>133020232</RNC>"), "133020232");
    expect(result.ok).toBe(true);
    if (!result.ok) return;
    expect(result.inspection.rootElement).toBe("PostulacionEmisor");
    expect(result.inspection.taxIdFound).toBe("133020232");
    expect(result.notes.join(" ")).toContain("no es una aprobación de la DGII");
  });

  it("no invalida un documento que no declara RNC (persona física)", () => {
    const result = inspect(valid("<Nombre>MANOLO LIO</Nombre>"), "133020232");
    expect(result.ok).toBe(true);
    if (!result.ok) return;
    expect(result.inspection.taxIdFound).toBeNull();
    expect(result.notes.join(" ")).toContain("no declara el RNC");
  });

  it("no confunde un número suelto con el RNC de la empresa", () => {
    // Una fecha o un serial no puede provocar un rechazo por RNC.
    const result = inspect(valid("<Fecha>2026-11-01</Fecha><Serie>123456789</Serie>"), "133020232");
    expect(result.ok).toBe(true);
  });

  it("acepta un RNC con guiones declarado en un atributo", () => {
    const bytes = Buffer.from(
      '<?xml version="1.0" encoding="utf-8"?><Postulacion RNC="1-33-02023-2"/>',
      "utf8",
    );
    const result = inspect(bytes, "133020232");
    expect(result.ok).toBe(true);
    if (result.ok) expect(result.inspection.taxIdFound).toBe("133020232");
  });
});

describe("XML de postulación — rechaza lo peligroso o lo que no corresponde", () => {
  it("rechaza DOCTYPE (XXE)", () => {
    const bytes = Buffer.from(
      '<?xml version="1.0"?><!DOCTYPE foo [<!ENTITY xxe SYSTEM "file:///etc/passwd">]><Postulacion>&xxe;</Postulacion>',
      "utf8",
    );
    const result = inspect(bytes);
    expect(result.ok).toBe(false);
    if (!result.ok) expect(result.code).toBe(ECF_POSTULATION_XML_ERRORS.DOCTYPE);
  });

  it("rechaza entidades y referencias externas por separado", () => {
    const entity = Buffer.from(
      '<?xml version="1.0"?><!ENTITY x "y"><A/>',
      "utf8",
    );
    const entityResult = inspect(entity);
    expect(entityResult.ok).toBe(false);
    if (!entityResult.ok) {
      expect(entityResult.code).toBe(ECF_POSTULATION_XML_ERRORS.ENTITY);
    }
    const external = Buffer.from(
      '<?xml version="1.0"?><?xml-stylesheet type="text/xsl" href="http://x/y.xsl"?><A/>',
      "utf8",
    );
    const externalResult = inspect(external);
    expect(externalResult.ok).toBe(false);
    if (!externalResult.ok) {
      expect(externalResult.code).toBe(ECF_POSTULATION_XML_ERRORS.EXTERNAL_REF);
    }
  });

  it("rechaza UTF-16 y contenido que no es XML", () => {
    const utf16 = Buffer.from([0xff, 0xfe, 0x3c, 0x00]);
    const enc = inspect(utf16);
    expect(enc.ok).toBe(false);
    if (!enc.ok) expect(enc.code).toBe(ECF_POSTULATION_XML_ERRORS.ENCODING);

    const pdf = Buffer.from("%PDF-1.4 contenido", "utf8");
    const notXml = inspect(pdf);
    expect(notXml.ok).toBe(false);
    if (!notXml.ok) expect(notXml.code).toBe(ECF_POSTULATION_XML_ERRORS.NOT_XML);
  });

  it("rechaza un comprobante electrónico (otra etapa)", () => {
    const ecf = Buffer.from(
      '<?xml version="1.0"?><ECF><Encabezado/></ECF>',
      "utf8",
    );
    const result = inspect(ecf);
    expect(result.ok).toBe(false);
    if (!result.ok) expect(result.code).toBe(ECF_POSTULATION_XML_ERRORS.WRONG_STAGE);

    const e32 = Buffer.from('<?xml version="1.0"?><E32/>', "utf8");
    const e32Result = inspect(e32);
    expect(e32Result.ok).toBe(false);
    if (!e32Result.ok) {
      expect(e32Result.code).toBe(ECF_POSTULATION_XML_ERRORS.WRONG_STAGE);
    }
  });

  it("rechaza el documento de otra empresa", () => {
    const result = inspect(valid("<RNC>101010101</RNC>"), "133020232");
    expect(result.ok).toBe(false);
    if (!result.ok) expect(result.code).toBe(ECF_POSTULATION_XML_ERRORS.RNC_MISMATCH);
  });

  it("rechaza extensiones que no son .xml y archivos enormes", () => {
    const wrongExtension = inspect(valid(), undefined, "postulacion.pdf");
    expect(wrongExtension.ok).toBe(false);
    if (!wrongExtension.ok) {
      expect(wrongExtension.code).toBe(ECF_POSTULATION_XML_ERRORS.NOT_XML);
    }
    const large = inspectPostulationXml({
      bytes: Buffer.alloc(10),
      sizeBytes: 2 * 1024 * 1024,
      fileName: "postulacion.xml",
    });
    expect(large.ok).toBe(false);
    if (!large.ok) expect(large.code).toBe(ECF_POSTULATION_XML_ERRORS.TOO_LARGE);
  });

  it("rechaza un archivo vacío y uno sin raíz", () => {
    const empty = inspect(Buffer.alloc(0));
    expect(empty.ok).toBe(false);
    if (!empty.ok) expect(empty.code).toBe(ECF_POSTULATION_XML_ERRORS.REQUIRED);

    const noRoot = inspect(Buffer.from('<?xml version="1.0"?>', "utf8"));
    expect(noRoot.ok).toBe(false);
    if (!noRoot.ok) expect(noRoot.code).toBe(ECF_POSTULATION_XML_ERRORS.NO_ROOT);
  });
});
