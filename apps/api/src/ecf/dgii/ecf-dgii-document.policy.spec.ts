import { createHash } from "node:crypto";
import {
  ECF_DGII_MAX_DOCUMENT_BYTES,
  detectDocumentType,
  sanitizeFileName,
  validateDocument,
} from "./ecf-dgii-document.policy";

const pdf = Buffer.concat([
  Buffer.from("%PDF-1.7\n", "latin1"),
  Buffer.from("contenido", "latin1"),
]);
const png = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0x00, 0x01]);
const jpeg = Buffer.from([0xff, 0xd8, 0xff, 0xe0, 0x00, 0x10]);
const xml = Buffer.from('<?xml version="1.0"?><Postulacion/>', "utf8");
const texto = Buffer.from("esto no es un documento fiscal", "utf8");

describe("documento DGII — detección por contenido", () => {
  it("detecta PDF, PNG, JPEG y XML por sus primeros bytes", () => {
    expect(detectDocumentType(pdf)).toBe("pdf");
    expect(detectDocumentType(png)).toBe("png");
    expect(detectDocumentType(jpeg)).toBe("jpeg");
    expect(detectDocumentType(xml)).toBe("xml");
  });

  it("no acepta un archivo de texto plano aunque se llame .pdf", () => {
    expect(detectDocumentType(texto)).toBeNull();
  });
});

describe("documento DGII — validación", () => {
  it("acepta un PDF y deriva extensión y MIME del contenido", () => {
    const result = validateDocument({
      buffer: pdf,
      fileName: "documento.pdf",
      declaredMime: "application/pdf",
    });
    expect(result.ok).toBe(true);
    if (!result.ok) return;
    expect(result.type).toBe("pdf");
    expect(result.extension).toBe("pdf");
    expect(result.mimeType).toBe("application/pdf");
    expect(result.sha256).toBe(
      createHash("sha256").update(pdf).digest("hex"),
    );
    expect(result.size).toBe(pdf.length);
  });

  it("rechaza un MIME declarado que no corresponde al contenido", () => {
    const result = validateDocument({
      buffer: pdf,
      declaredMime: "image/png",
      fileName: "documento.pdf",
    });
    expect(result.ok).toBe(false);
    if (result.ok) return;
    expect(result.code).toBe("ECF_DGII_DOCUMENT_MIME_MISMATCH");
  });

  it("rechaza un archivo vacío", () => {
    const result = validateDocument({ buffer: Buffer.alloc(0) });
    expect(result.ok).toBe(false);
    if (result.ok) return;
    expect(result.code).toBe("ECF_DGII_DOCUMENT_EMPTY");
  });

  it("rechaza un archivo que supera el máximo", () => {
    const big = Buffer.alloc(ECF_DGII_MAX_DOCUMENT_BYTES + 1, 0x25);
    big.write("%PDF-1.7", 0, "latin1");
    const result = validateDocument({ buffer: big });
    expect(result.ok).toBe(false);
    if (result.ok) return;
    expect(result.code).toBe("ECF_DGII_DOCUMENT_TOO_LARGE");
  });

  it("rechaza un tipo no admitido", () => {
    const result = validateDocument({ buffer: texto, fileName: "nota.txt" });
    expect(result.ok).toBe(false);
    if (result.ok) return;
    expect(result.code).toBe("ECF_DGII_DOCUMENT_TYPE_NOT_ALLOWED");
  });
});

describe("documento DGII — nombre de archivo", () => {
  it("se queda con el basename y elimina rutas", () => {
    expect(sanitizeFileName("../../etc/passwd")).toBe("passwd");
    expect(sanitizeFileName("C:\\windows\\system32\\config.sys")).toBe(
      "config.sys",
    );
    expect(sanitizeFileName("..\\..\\secreto.pdf")).toBe("secreto.pdf");
  });

  it("elimina caracteres de control y acota la longitud", () => {
    expect(sanitizeFileName("doc\u0000u\u0001mento.pdf")).toBe("documento.pdf");
    expect(sanitizeFileName("a".repeat(500))).toHaveLength(180);
  });

  it("usa un nombre por defecto si no hay nombre útil", () => {
    expect(sanitizeFileName("")).toBe("documento");
    expect(sanitizeFileName(undefined)).toBe("documento");
    expect(sanitizeFileName("...")).toBe("documento");
  });
});
