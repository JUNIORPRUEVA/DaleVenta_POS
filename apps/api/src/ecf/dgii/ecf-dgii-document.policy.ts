import { createHash } from "node:crypto";

/**
 * Validación de documentos del expediente DGII.
 *
 * Reglas de diseño:
 *
 * - El tipo se decide por **contenido** (magic bytes), nunca por la extensión ni
 *   por el `Content-Type` que declara el cliente. Una extensión es una promesa;
 *   los primeros bytes son un hecho.
 * - La extensión y el MIME que se guardan los deriva el servidor del tipo
 *   detectado, no del nombre del archivo.
 * - El nombre original se sanea: solo se conserva el basename y se recortan
 *   caracteres de control. Nunca se usa para construir rutas.
 */

export const ECF_DGII_MAX_DOCUMENT_BYTES = 5 * 1024 * 1024;

/** Tipos de documento admitidos en el expediente. */
export const ECF_DGII_DOCUMENT_KINDS = [
  "REPRESENTATIVE_ID",
  "COMPANY_DOCUMENT",
  "AUTHORIZATION",
  "POSTULATION_XML",
  "DGII_RECEIPT",
  "OTHER",
] as const;

export type EcfDgiiDocumentKind = (typeof ECF_DGII_DOCUMENT_KINDS)[number];

export type DetectedDocumentType = "pdf" | "png" | "jpeg" | "xml";

const EXTENSION_BY_TYPE: Record<DetectedDocumentType, string> = {
  pdf: "pdf",
  png: "png",
  jpeg: "jpg",
  xml: "xml",
};

const MIME_BY_TYPE: Record<DetectedDocumentType, string> = {
  pdf: "application/pdf",
  png: "image/png",
  jpeg: "image/jpeg",
  xml: "application/xml",
};

/** MIME aceptados por tipo detectado. El XML admite sus dos variantes. */
const ACCEPTED_MIMES: Record<DetectedDocumentType, readonly string[]> = {
  pdf: ["application/pdf"],
  png: ["image/png"],
  jpeg: ["image/jpeg", "image/jpg"],
  xml: ["application/xml", "text/xml"],
};

export type DocumentValidation =
  | {
      ok: true;
      type: DetectedDocumentType;
      extension: string;
      mimeType: string;
      sha256: string;
      size: number;
      safeFileName: string;
    }
  | { ok: false; code: string; message: string };

/** Detecta el tipo real por los primeros bytes. `null` si no está admitido. */
export function detectDocumentType(buffer: Buffer): DetectedDocumentType | null {
  if (!buffer || buffer.length === 0) return null;

  if (
    buffer.length >= 5 &&
    buffer.subarray(0, 5).toString("latin1") === "%PDF-"
  ) {
    return "pdf";
  }

  const pngSignature = [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a];
  if (
    buffer.length >= pngSignature.length &&
    pngSignature.every((byte, index) => buffer[index] === byte)
  ) {
    return "png";
  }

  if (buffer.length >= 3 && buffer[0] === 0xff && buffer[1] === 0xd8 && buffer[2] === 0xff) {
    return "jpeg";
  }

  // XML: BOM opcional, espacios y luego '<'. Se mira solo una cabecera corta
  // para no interpretar binarios como texto.
  const head = buffer.subarray(0, Math.min(buffer.length, 64)).toString("utf8");
  if (/^\uFEFF?\s*</.test(head)) return "xml";

  return null;
}

/** Sanea el nombre original: basename, sin controles, longitud acotada. */
export function sanitizeFileName(raw: string | undefined | null): string {
  const base = (raw ?? "").split(/[\\/]/).pop() ?? "";
  const cleaned = base
    .replace(/[\u0000-\u001f\u007f]/g, "")
    .replace(/^\.+/, "")
    .trim();
  if (!cleaned) return "documento";
  return cleaned.slice(0, 180);
}

/**
 * Valida un documento y devuelve lo que hay que persistir.
 *
 * `declaredMime` es opcional: si llega y no corresponde al tipo real, se
 * rechaza. No se confía en él para decidir el tipo.
 */
export function validateDocument(input: {
  buffer: Buffer;
  size?: number;
  declaredMime?: string | null;
  fileName?: string | null;
}): DocumentValidation {
  const buffer = input.buffer;
  if (!buffer || buffer.length === 0) {
    return {
      ok: false,
      code: "ECF_DGII_DOCUMENT_EMPTY",
      message: "El archivo está vacío.",
    };
  }

  const size = input.size ?? buffer.length;
  if (size > ECF_DGII_MAX_DOCUMENT_BYTES) {
    return {
      ok: false,
      code: "ECF_DGII_DOCUMENT_TOO_LARGE",
      message: "El archivo supera el tamaño máximo permitido (5 MB).",
    };
  }

  const type = detectDocumentType(buffer);
  if (!type) {
    return {
      ok: false,
      code: "ECF_DGII_DOCUMENT_TYPE_NOT_ALLOWED",
      message: "Solo se admiten documentos PDF, PNG, JPG o XML.",
    };
  }

  const declared = (input.declaredMime ?? "").trim().toLowerCase();
  // `application/octet-stream` es el comodín que envía un cliente cuando no
  // conoce el tipo (o cuando sube bytes crudos): no aporta información, así que
  // no se usa para rechazar. Lo que decide el tipo es el contenido.
  const isGeneric =
    declared.length === 0 || declared === "application/octet-stream";
  if (!isGeneric && !ACCEPTED_MIMES[type].includes(declared)) {
    return {
      ok: false,
      code: "ECF_DGII_DOCUMENT_MIME_MISMATCH",
      message: "El tipo declarado no coincide con el contenido real del archivo.",
    };
  }

  return {
    ok: true,
    type,
    extension: EXTENSION_BY_TYPE[type],
    mimeType: MIME_BY_TYPE[type],
    sha256: createHash("sha256").update(buffer).digest("hex"),
    size,
    safeFileName: sanitizeFileName(input.fileName),
  };
}
