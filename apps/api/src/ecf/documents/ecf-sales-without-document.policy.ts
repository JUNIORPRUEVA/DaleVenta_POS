/**
 * Reglas de la venta SIN comprobante electrónico.
 *
 * Por qué existe este módulo
 * --------------------------
 * La DGII exige un comprobante por cada venta. Hay operaciones que la normativa
 * permite documentar de otra forma, así que el sistema necesita una válvula de
 * escape — pero una válvula **declarada**, no un descuido: la empresa la habilita,
 * el vendedor escribe por qué, y cada uso queda registrado con su venta, su
 * usuario y su fecha.
 *
 * Este archivo es **puro**: no lee entorno, no accede a base de datos y no hace
 * red. Toda la decisión se toma con lo que recibe, para que pueda probarse sin
 * infraestructura.
 */

/**
 * Aviso que la empresa debe leer antes de habilitar la opción. Vive aquí, en el
 * servidor, y viaja al cliente en la respuesta de capacidades: así el texto que
 * se muestra y el que el servidor declara son literalmente el mismo, y no puede
 * aparecer una versión suavizada en la interfaz.
 */
export const ECF_WITHOUT_DOCUMENT_WARNING =
  "Advertencia fiscal: esta opción permite registrar ventas sin emitir un " +
  "comprobante fiscal electrónico. Estos documentos no sustituyen los e-CF " +
  "exigidos por la DGII. La empresa es responsable de utilizar esta función " +
  "únicamente en operaciones permitidas por la normativa vigente. FullPOS " +
  "conservará un registro de estas operaciones para control y auditoría.";

/** Un motivo vacío o de una palabra no es una justificación. */
export const ECF_WITHOUT_DOCUMENT_REASON_MIN_LENGTH = 10;
export const ECF_WITHOUT_DOCUMENT_REASON_MAX_LENGTH = 500;

export const ECF_WITHOUT_DOCUMENT_ERRORS = {
  /** La empresa no habilitó la excepción. Es el bloqueo real de la opción «Normal». */
  notAllowed: "ECF_SALES_WITHOUT_DOCUMENT_NOT_ALLOWED",
  /** La empresa tiene la facturación electrónica apagada: todo el flujo sobra. */
  ecfDisabled: "ECF_COMPANY_DISABLED",
  reasonRequired: "ECF_WITHOUT_DOCUMENT_REASON_REQUIRED",
  /** La venta ya tiene un e-CF: registrarla como «sin comprobante» sería falso. */
  saleHasDocument: "ECF_SALES_WITHOUT_DOCUMENT_HAS_ECF",
  saleAlreadyRegistered: "ECF_SALES_WITHOUT_DOCUMENT_ALREADY_REGISTERED",
  saleNotFound: "ECF_SALES_WITHOUT_DOCUMENT_SALE_NOT_FOUND",
  expectedTypeInvalid: "ECF_WITHOUT_DOCUMENT_EXPECTED_TYPE_INVALID",
} as const;

export type WithoutDocumentReasonResult =
  | { ok: true; reason: string }
  | { ok: false; code: string; message: string };

/** Normaliza y valida el motivo que el vendedor escribe. */
export function validateWithoutDocumentReason(
  input: unknown,
): WithoutDocumentReasonResult {
  const reason = `${typeof input === "string" ? input : ""}`
    .trim()
    .replace(/\s+/g, " ");
  if (reason.length < ECF_WITHOUT_DOCUMENT_REASON_MIN_LENGTH) {
    return {
      ok: false,
      code: ECF_WITHOUT_DOCUMENT_ERRORS.reasonRequired,
      message:
        `Escribe el motivo de la venta sin comprobante (al menos ` +
        `${ECF_WITHOUT_DOCUMENT_REASON_MIN_LENGTH} caracteres).`,
    };
  }
  if (reason.length > ECF_WITHOUT_DOCUMENT_REASON_MAX_LENGTH) {
    return {
      ok: false,
      code: ECF_WITHOUT_DOCUMENT_ERRORS.reasonRequired,
      message:
        `El motivo no puede superar ${ECF_WITHOUT_DOCUMENT_REASON_MAX_LENGTH} caracteres.`,
    };
  }
  return { ok: true, reason };
}

/**
 * ¿Puede esta empresa registrar una venta sin comprobante?
 *
 * Se exigen las DOS condiciones: la facturación electrónica activa y la excepción
 * habilitada. Con la e-CF apagada no se registra nada aquí porque no hay
 * comprobante del que prescindir.
 */
export function canRegisterSaleWithoutDocument(config: {
  enabled?: boolean | null;
  allowSalesWithoutEcf?: boolean | null;
} | null): { ok: true } | { ok: false; code: string; message: string } {
  if (!config?.enabled) {
    return {
      ok: false,
      code: ECF_WITHOUT_DOCUMENT_ERRORS.ecfDisabled,
      message: "La facturación electrónica está apagada para esta empresa.",
    };
  }
  if (config.allowSalesWithoutEcf !== true) {
    return {
      ok: false,
      code: ECF_WITHOUT_DOCUMENT_ERRORS.notAllowed,
      message:
        "Esta empresa no permite registrar ventas sin comprobante electrónico. " +
        "Actívalo en Configuración de e-CF antes de usar la opción Normal.",
    };
  }
  return { ok: true };
}

/**
 * Tipo de comprobante que corresponde a una venta, según si identificó o no al
 * receptor.
 *
 * Regla de producto: un cliente con RNC o cédula y razón social exige **E31**
 * (crédito fiscal); una venta a consumidor final, sin esos datos, corresponde a
 * **E32**. No se deduce nada más: si falta el dato del receptor se elige E32, no
 * se inventa un RNC.
 */
export function expectedDocumentTypeForSale(hasBuyerTaxId: boolean): "E31" | "E32" {
  return hasBuyerTaxId ? "E31" : "E32";
}

/** Tipos que pueden quedar como «pendiente de emitir» en el registro. */
export function normalizeExpectedDocumentType(
  input: unknown,
): { ok: true; value: "E31" | "E32" | null } | { ok: false; code: string } {
  if (input === undefined || input === null || `${input}`.trim() === "") {
    return { ok: true, value: null };
  }
  const normalized = `${input}`.trim().toUpperCase();
  if (normalized !== "E31" && normalized !== "E32") {
    return { ok: false, code: ECF_WITHOUT_DOCUMENT_ERRORS.expectedTypeInvalid };
  }
  return { ok: true, value: normalized };
}
