import { createHash } from "crypto";

/**
 * Política del EXPEDIENTE de postulación (borrador, snapshot y consentimiento).
 *
 * Toda la política es pura y fail-closed: ante la duda, bloquea. Ninguna función
 * de este módulo autoriza nada ante la DGII ni toca configuración fiscal.
 */

/**
 * Versión del texto de consentimiento.
 *
 * Cambiar el texto exige cambiar la versión: el snapshot guarda la versión
 * aceptada, así que un consentimiento antiguo nunca se confunde con uno nuevo.
 */
export const ECF_DGII_CONSENT_VERSION = "2026-10-31.v2";

/**
 * Finalidad declarada del tratamiento documental.
 *
 * Es el texto que el cliente acepta. No es un poder de representación ante la
 * DGII: habilita el uso interno del expediente para gestionar la postulación.
 */
export const ECF_DGII_CONSENT_PURPOSE =
  "Autorizo expresamente a FullPOS Cloud y a su personal debidamente autorizado a utilizar, revisar y procesar los datos de mi empresa, los datos de su representante legal y la documentación que suministre, exclusivamente con la finalidad de preparar, organizar y gestionar internamente el expediente relacionado con la postulación a facturación electrónica. Declaro que la información y los documentos aportados son veraces, actualizados y proporcionados bajo mi responsabilidad, y que cuento con facultades suficientes para entregarlos o autorizar su tratamiento. Comprendo que este consentimiento no constituye representación legal ante la Dirección General de Impuestos Internos (DGII), ni sustituye poderes, autorizaciones formales, firmas o trámites oficiales que correspondan al contribuyente o a su representante autorizado.\n\n" +
  "Entiendo que la revisión interna realizada por FullPOS Cloud tiene fines de validación, organización y soporte operativo, y no equivale a una aprobación oficial, certificación, autorización para emitir comprobantes fiscales electrónicos ni confirmación de habilitación por parte de la DGII o proveedores externos. Reconozco que los resultados de cualquier trámite oficial dependen de la autoridad competente y de la información presentada. FullPOS Cloud no garantiza la aprobación de solicitudes ni los plazos de respuesta de terceros, y las incidencias derivadas de información incorrecta, incompleta o no autorizada suministrada por el usuario serán evaluadas conforme a las condiciones contractuales y a la legislación aplicable. Los datos serán tratados para las finalidades autorizadas y bajo controles de seguridad y confidencialidad.\n\n" +
  "Esta aceptación autoriza únicamente la revisión interna del expediente. No constituye presentación oficial ante la DGII ni habilitación para emitir comprobantes electrónicos.";

/** Campos mínimos del borrador: empresa y representante legal. */
export const ECF_DGII_DRAFT_REQUIRED_FIELDS = [
  "company.rnc",
  "company.legalName",
  "company.address",
  "representative.fullName",
  "representative.identification",
  "representative.email",
] as const;

export type EcfDgiiDraftField = (typeof ECF_DGII_DRAFT_REQUIRED_FIELDS)[number];

/** Motivo por el que NO se puede guardar el borrador, o `null`. */
export function draftSaveRefusal(input: {
  payload: unknown;
}): string | null {
  const payload = input.payload;
  if (payload === null || typeof payload !== "object" || Array.isArray(payload)) {
    return "ECF_DGII_DRAFT_INVALID";
  }
  // Un borrador puede estar incompleto a propósito: se guarda lo que haya.
  return null;
}

/**
 * Campos obligatorios que faltan en el borrador.
 *
 * Devuelve las claves ausentes (nunca inventa valores) para que la interfaz
 * pueda señalar exactamente qué falta antes de enviar.
 */
export function missingDraftFields(payload: unknown): EcfDgiiDraftField[] {
  const root =
    payload !== null && typeof payload === "object" && !Array.isArray(payload)
      ? (payload as Record<string, unknown>)
      : {};
  const company =
    root.company !== null &&
    typeof root.company === "object" &&
    !Array.isArray(root.company)
      ? (root.company as Record<string, unknown>)
      : {};
  const representative =
    root.representative !== null &&
    typeof root.representative === "object" &&
    !Array.isArray(root.representative)
      ? (root.representative as Record<string, unknown>)
      : {};

  const present = (value: unknown): boolean =>
    typeof value === "string" && value.trim().length > 0;

  const missing: EcfDgiiDraftField[] = [];
  const digits = (value: unknown): string =>
    typeof value === "string" ? value.replace(/\D/g, "") : "";
  const taxIdLength = digits(company.rnc).length;
  const representativeIdLength = digits(representative.identification).length;
  const email = typeof representative.email === "string" ? representative.email.trim() : "";

  if (taxIdLength !== 9 && taxIdLength !== 11) missing.push("company.rnc");
  if (!present(company.legalName)) missing.push("company.legalName");
  if (!present(company.address)) missing.push("company.address");
  if (!present(representative.fullName)) missing.push("representative.fullName");
  if (representativeIdLength !== 9 && representativeIdLength !== 11) {
    missing.push("representative.identification");
  }
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) missing.push("representative.email");
  return missing;
}

/**
 * Motivo por el que NO se puede enviar el expediente, o `null`.
 *
 * Separa dos cosas que suelen confundirse: que el expediente esté completo y que
 * el cliente haya aceptado la versión vigente del consentimiento.
 */
export function submitRefusal(input: {
  payload: unknown;
  consentVersion: string | null | undefined;
  expectedConsentVersion?: string;
}): string | null {
  const expected = input.expectedConsentVersion ?? ECF_DGII_CONSENT_VERSION;
  if (!input.consentVersion || input.consentVersion.trim().length === 0) {
    return "ECF_DGII_CONSENT_REQUIRED";
  }
  if (input.consentVersion.trim() !== expected) {
    return "ECF_DGII_CONSENT_VERSION_UNKNOWN";
  }
  const payload = input.payload;
  if (payload === null || typeof payload !== "object" || Array.isArray(payload)) {
    return "ECF_DGII_DRAFT_REQUIRED";
  }
  if (missingDraftFields(payload).length > 0) {
    return "ECF_DGII_DRAFT_INCOMPLETE";
  }
  return null;
}

/**
 * Serializa de forma determinista: claves ordenadas, sin `undefined`.
 *
 * Sin esto, dos objetos equivalentes con distinto orden de claves producirían
 * hashes distintos y la idempotencia del envío sería falsa.
 */
export function canonicalize(value: unknown): string {
  if (value === null || value === undefined) return "null";
  if (typeof value === "number") {
    return Number.isFinite(value) ? JSON.stringify(value) : "null";
  }
  if (typeof value === "string" || typeof value === "boolean") {
    return JSON.stringify(value);
  }
  if (Array.isArray(value)) {
    return `[${value.map((item) => canonicalize(item)).join(",")}]`;
  }
  if (typeof value === "object") {
    const record = value as Record<string, unknown>;
    const keys = Object.keys(record)
      .filter((key) => record[key] !== undefined)
      .sort();
    return `{${keys
      .map((key) => `${JSON.stringify(key)}:${canonicalize(record[key])}`)
      .join(",")}}`;
  }
  return "null";
}

/** SHA-256 hexadecimal del valor canonicalizado. */
export function hashCanonical(value: unknown): string {
  return createHash("sha256").update(canonicalize(value), "utf8").digest("hex");
}
