/**
 * Validación ESTRUCTURAL del XML de postulación.
 *
 * Qué es este archivo: el XML que el Portal de Certificación de la DGII entrega
 * en la etapa de postulación, que después se firma con el certificado de la
 * empresa. El producto NO lo genera: lo recibe del contribuyente.
 *
 * Límites deliberados y honestos:
 *  - **No** se valida contra un XSD oficial porque el repositorio no contiene uno
 *    verificable. Validar contra un esquema inventado sería peor que no validar.
 *  - **No** se interpreta el documento: se inspecciona como texto con reglas
 *    cerradas. No hay parser que expanda entidades, así que XXE y mil cargas de
 *    entidad no son posibles por construcción.
 *  - **No** se acepta cualquier XML: se rechaza lo que pertenece a otra etapa y
 *    lo que no es un documento de datos.
 *
 * Estados que el producto distingue (nunca se mezclan):
 *   RECIBIDO → VALIDADO → (firma del proveedor) → FIRMADO → presentado por el cliente.
 */

/** Tope de tamaño del XML: son documentos de pocos KB, no adjuntos. */
export const ECF_POSTULATION_XML_MAX_BYTES = 1024 * 1024;

export const ECF_POSTULATION_XML_ERRORS = {
  REQUIRED: "ECF_POSTULATION_XML_REQUIRED",
  TOO_LARGE: "ECF_POSTULATION_XML_TOO_LARGE",
  NOT_XML: "ECF_POSTULATION_XML_NOT_XML",
  ENCODING: "ECF_POSTULATION_XML_ENCODING_UNSUPPORTED",
  DOCTYPE: "ECF_POSTULATION_XML_DOCTYPE_FORBIDDEN",
  ENTITY: "ECF_POSTULATION_XML_ENTITY_FORBIDDEN",
  EXTERNAL_REF: "ECF_POSTULATION_XML_EXTERNAL_REF_FORBIDDEN",
  NO_ROOT: "ECF_POSTULATION_XML_ROOT_MISSING",
  WRONG_STAGE: "ECF_POSTULATION_XML_WRONG_STAGE",
  RNC_MISMATCH: "ECF_POSTULATION_XML_RNC_MISMATCH",
} as const;

export type EcfPostulationXmlErrorCode =
  (typeof ECF_POSTULATION_XML_ERRORS)[keyof typeof ECF_POSTULATION_XML_ERRORS];

/** Mensajes para el usuario, sin jerga ni detalles internos. */
export const ECF_POSTULATION_XML_MESSAGES: Readonly<
  Record<EcfPostulationXmlErrorCode, string>
> = {
  [ECF_POSTULATION_XML_ERRORS.REQUIRED]: "Selecciona el archivo XML de postulación.",
  [ECF_POSTULATION_XML_ERRORS.TOO_LARGE]:
    "El archivo es demasiado grande. El máximo es 1 MB.",
  [ECF_POSTULATION_XML_ERRORS.NOT_XML]:
    "El archivo no es un documento XML.",
  [ECF_POSTULATION_XML_ERRORS.ENCODING]:
    "El XML debe estar codificado en UTF-8.",
  [ECF_POSTULATION_XML_ERRORS.DOCTYPE]:
    "El archivo contiene una declaración DOCTYPE, que no está permitida.",
  [ECF_POSTULATION_XML_ERRORS.ENTITY]:
    "El archivo define entidades XML, que no están permitidas.",
  [ECF_POSTULATION_XML_ERRORS.EXTERNAL_REF]:
    "El archivo referencia recursos externos, que no están permitidos.",
  [ECF_POSTULATION_XML_ERRORS.NO_ROOT]:
    "El archivo no contiene un elemento raíz válido.",
  [ECF_POSTULATION_XML_ERRORS.WRONG_STAGE]:
    "Este XML corresponde a un comprobante electrónico, no a la postulación.",
  [ECF_POSTULATION_XML_ERRORS.RNC_MISMATCH]:
    "El RNC del XML no corresponde a la empresa del expediente.",
};

export type EcfPostulationXmlInspection = {
  rootElement: string;
  declaredEncoding: string | null;
  /** RNC (u otro identificador) encontrado en el documento, si lo hay. */
  taxIdFound: string | null;
  sizeBytes: number;
};

export type EcfPostulationXmlResult =
  | { ok: true; inspection: EcfPostulationXmlInspection; notes: string[] }
  | { ok: false; code: EcfPostulationXmlErrorCode; detail: string };

/**
 * Raíces que pertenecen a la EMISIÓN (comprobantes), no a la postulación.
 *
 * Rechazarlas evita que alguien suba como «postulación» un e-CF real, que se
 * interpretaría como el documento equivocado en la etapa equivocada.
 */
const EMISSION_ROOT_PREFIXES = ["ECF", "E31", "E32", "E33", "E34", "E41", "E43", "E44", "E45", "E46", "E47"];

function fail(
  code: EcfPostulationXmlErrorCode,
  detail: string,
): EcfPostulationXmlResult {
  return { ok: false, code, detail };
}

function detectRoot(xml: string): string | null {
  // Se ignoran declaraciones, comentarios e instrucciones de proceso.
  const withoutHeader = xml
    .replace(/^\uFEFF/, "")
    .replace(/<\?[\s\S]*?\?>/g, "")
    .replace(/<!--[\s\S]*?-->/g, "")
    .trimStart();
  const match = /^<([A-Za-z_][\w.:-]*)/.exec(withoutHeader);
  return match ? match[1] : null;
}

function detectEncoding(xml: string): string | null {
  const declaration = /^<\?xml[^>]*encoding\s*=\s*["']([A-Za-z0-9._-]+)["']/i.exec(
    xml.replace(/^\uFEFF/, "").trimStart(),
  );
  return declaration ? declaration[1].toLowerCase() : null;
}

/**
 * Inspecciona el XML. `expectedTaxId` es el RNC canónico del expediente; si el
 * documento menciona un RNC, debe coincidir.
 */
export function inspectPostulationXml(input: {
  bytes: Buffer;
  sizeBytes: number;
  expectedTaxId?: string | null;
  /** Extensiones admitidas (por defecto, .xml). */
  fileName?: string;
}): EcfPostulationXmlResult {
  const size = input.sizeBytes;
  if (!input.bytes || size === 0) {
    return fail(ECF_POSTULATION_XML_ERRORS.REQUIRED, "No hay contenido.");
  }
  if (size > ECF_POSTULATION_XML_MAX_BYTES) {
    return fail(
      ECF_POSTULATION_XML_ERRORS.TOO_LARGE,
      `El archivo supera ${ECF_POSTULATION_XML_MAX_BYTES} bytes.`,
    );
  }
  if (input.fileName && !input.fileName.toLowerCase().endsWith(".xml")) {
    return fail(
      ECF_POSTULATION_XML_ERRORS.NOT_XML,
      "La extensión del archivo no es .xml.",
    );
  }

  // UTF-16 se detecta por los bytes nulos iniciales; no se acepta.
  if (input.bytes.length >= 2) {
    const b0 = input.bytes[0];
    const b1 = input.bytes[1];
    if ((b0 === 0xff && b1 === 0xfe) || (b0 === 0xfe && b1 === 0xff)) {
      return fail(
        ECF_POSTULATION_XML_ERRORS.ENCODING,
        "El archivo está en UTF-16.",
      );
    }
  }

  const xml = input.bytes.toString("utf8");
  if (xml.includes("\u0000")) {
    return fail(ECF_POSTULATION_XML_ERRORS.ENCODING, "Contiene bytes nulos.");
  }
  if (!/^\uFEFF?\s*</.test(xml)) {
    return fail(
      ECF_POSTULATION_XML_ERRORS.NOT_XML,
      "El contenido no empieza con una marca XML.",
    );
  }

  const encoding = detectEncoding(xml);
  if (encoding && encoding !== "utf-8" && encoding !== "utf8") {
    return fail(
      ECF_POSTULATION_XML_ERRORS.ENCODING,
      `Codificación declarada no admitida: ${encoding}.`,
    );
  }

  // Defensas explícitas: sin DTD, sin entidades, sin referencias externas.
  if (/<!DOCTYPE/i.test(xml)) {
    return fail(
      ECF_POSTULATION_XML_ERRORS.DOCTYPE,
      "El documento declara un DOCTYPE.",
    );
  }
  if (/<!ENTITY/i.test(xml)) {
    return fail(
      ECF_POSTULATION_XML_ERRORS.ENTITY,
      "El documento define entidades.",
    );
  }
  if (/\bSYSTEM\s+["']|\bPUBLIC\s+["']/i.test(xml) || /<\?xml-stylesheet/i.test(xml)) {
    return fail(
      ECF_POSTULATION_XML_ERRORS.EXTERNAL_REF,
      "El documento referencia recursos externos.",
    );
  }

  const root = detectRoot(xml);
  if (!root) {
    return fail(
      ECF_POSTULATION_XML_ERRORS.NO_ROOT,
      "No se pudo determinar el elemento raíz.",
    );
  }
  const normalizedRoot = root.toUpperCase().replace(/^[A-Z]+:/, "");
  if (
    normalizedRoot.startsWith("ECF") ||
    EMISSION_ROOT_PREFIXES.some((prefix) => normalizedRoot === prefix)
  ) {
    return fail(
      ECF_POSTULATION_XML_ERRORS.WRONG_STAGE,
      `La raíz ${root} corresponde a un comprobante electrónico.`,
    );
  }

  // RNC del expediente: se compara SOLO si el documento lo declara de forma
  // explícita (elemento o atributo RNC). Un número suelto en el texto no se
  // interpreta como RNC: fechas y series darían falsos negativos.
  const expected = digits(input.expectedTaxId ?? "");
  const declaredTaxId = findDeclaredTaxId(xml);
  if (
    expected.length >= 9 &&
    declaredTaxId !== null &&
    declaredTaxId !== expected
  ) {
    return fail(
      ECF_POSTULATION_XML_ERRORS.RNC_MISMATCH,
      "El RNC del documento no coincide con el de la empresa.",
    );
  }

  const notes = [
    "El archivo se validó como documento XML de datos y quedó asociado al expediente.",
    "Esta validación no es una aprobación de la DGII ni acredita la presentación del trámite.",
  ];
  if (expected.length >= 9 && declaredTaxId === null) {
    notes.push(
      "El XML no declara el RNC de la empresa: no se ha podido comprobar por esa vía.",
    );
  }

  return {
    ok: true,
    inspection: {
      rootElement: root,
      declaredEncoding: encoding,
      taxIdFound: declaredTaxId,
      sizeBytes: size,
    },
    notes,
  };
}

function digits(value: string): string {
  return value.replace(/\D/g, "");
}

/**
 * RNC declarado de forma explícita en el documento.
 *
 * Se mira un elemento `<RNC>…</RNC>` o un atributo `RNC="…"`. Si el documento
 * no lo declara así, devuelve `null` y NO se invalida por ello: hay trámites y
 * certificados de persona física que no llevan el RNC de la empresa.
 */
function findDeclaredTaxId(xml: string): string | null {
  const element = /<RNC\b[^>]*>\s*([0-9][0-9\s-]{7,15}[0-9])\s*<\/RNC>/i.exec(xml);
  const attribute = /\bRNC\s*=\s*["']([0-9][0-9\s-]{7,15}[0-9])["']/i.exec(xml);
  const raw = element?.[1] ?? attribute?.[1] ?? null;
  if (raw === null) return null;
  const value = digits(raw);
  return value.length === 9 || value.length === 11 ? value : null;
}
