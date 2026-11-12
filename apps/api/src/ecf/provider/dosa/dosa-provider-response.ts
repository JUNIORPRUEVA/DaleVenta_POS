import type { EcfDocumentType } from "../../fiscal-core/ecf-fiscal-document";
import type { EcfProviderObservation } from "../../documents/ecf-provider-response";
import { classifyDosaResponse } from "./dosa-response.mapper";

/**
 * Correlación de la RESPUESTA de DOSA con la operación de ESTA empresa.
 *
 * Por qué hace falta un evaluador propio
 * --------------------------------------
 * `assessEcfProviderResponse` (el común) está modelado sobre la respuesta de
 * Alanube: exige `id` ULID, `documentNumber`, `legalStatus` y
 * `sequenceConsumed`. Una respuesta de DOSA es plana y usa `trackId`, `encf`,
 * `estado` y `secuenciaUtilizada`, así que **nunca** correlacionaría: toda
 * emisión DOSA habría quedado como «resultado desconocido» aunque el proveedor
 * hubiera contestado con claridad.
 *
 * Este evaluador aplica el contrato documentado en
 * `docs/ecf/research/DOSA_EMISSION_API_2026-11.md` §5 (respuesta plana, decisión
 * por el texto de `estado`, semántica de `secuenciaUtilizada`).
 *
 * Lo que sigue siendo cierto y no se relaja:
 *  - Se clasifica por `estado`, no por `codigo` (la tabla de códigos tiene una
 *    contradicción conocida con el código 0).
 *  - Ninguna respuesta concede aceptación fiscal: `canUpdateFiscalStatus` es
 *    siempre `false` y nunca se escribe `DGII_ACCEPTED` desde aquí.
 *  - Un cuerpo ilegible no correlaciona: es resultado desconocido.
 */

/**
 * Estado de documento que corresponde a cada resultado correlacionado.
 *
 * Nunca propone `DGII_ACCEPTED`: una respuesta del proveedor no es prueba de
 * aceptación fiscal verificable, así que lo máximo a lo que se llega es a
 * revisión humana o a «pendiente de la DGII».
 */
export const DOSA_OUTCOME_STATUS = {
  ACCEPTED: "HUMAN_REVIEW_REQUIRED",
  CONDITIONALLY_ACCEPTED: "HUMAN_REVIEW_REQUIRED",
  REJECTED: "PROVIDER_REJECTED",
  IN_PROCESS: "DGII_STATUS_PENDING",
  UNRESOLVED: "HUMAN_REVIEW_REQUIRED",
  NOT_RECEIVED: "PROVIDER_REJECTED",
} as const;

/**
 * Traduce el resultado documentado de DOSA al vocabulario común.
 *
 * El tipo compartido solo admite cuatro valores y no se amplía para no afectar
 * a Alanube. La distinción fina (condicional, pendiente, no recibido) se
 * conserva en `observedLegalStatus`, en `safeCode` y en `documentStatus`.
 */
const OUTCOME_VOCABULARY: Record<string, "ACCEPTED" | "REJECTED" | "PENDING" | "UNKNOWN"> = {
  ACCEPTED: "ACCEPTED",
  CONDITIONALLY_ACCEPTED: "ACCEPTED",
  REJECTED: "REJECTED",
  NOT_RECEIVED: "REJECTED",
  IN_PROCESS: "PENDING",
  UNRESOLVED: "UNKNOWN",
};

export type DosaObservationContext = {
  documentType: EcfDocumentType;
  expectedEncf: string;
  /** RNC de la empresa emisora: la respuesta debe hablar de ella. */
  expectedTaxId: string;
};

function asRecord(value: unknown): Record<string, unknown> | null {
  return value && typeof value === "object" && !Array.isArray(value)
    ? (value as Record<string, unknown>)
    : null;
}

function firstString(source: Record<string, unknown> | null, keys: string[]): string | null {
  if (!source) return null;
  for (const key of keys) {
    const value = source[key];
    if (typeof value === "string" && value.trim().length > 0) return value.trim();
  }
  return null;
}

function normalizeRnc(value: string): string {
  return value.replace(/[^0-9A-Za-z]/g, "").toUpperCase();
}

export function assessDosaProviderResponse(
  httpStatus: number,
  body: unknown,
  context: DosaObservationContext,
): EcfProviderObservation {
  // Forma tolerante al envoltorio `data`, igual que el clasificador.
  const envelope = asRecord(body);
  const data = asRecord(envelope?.data) ?? envelope;

  const encf = firstString(data, ["encf", "eNCF", "e_ncf", "ncf"]);
  const rnc = firstString(data, ["rnc", "RNC"]);
  const trackId = firstString(data, ["trackId", "track_id", "id"]);
  const secuencia = data?.secuenciaUtilizada;
  const sequenceConsumed = typeof secuencia === "boolean" ? secuencia : null;

  const classification = data === null ? null : classifyDosaResponse(data);
  const outcome = classification?.outcome ?? "UNRESOLVED";

  const httpAcceptable = httpStatus === 200 || httpStatus === 201 || httpStatus === 202;
  const encfValid = encf !== null && new RegExp(`^${context.documentType}\\d{10}$`).test(encf);
  const encfMatches = encf !== null && encf === context.expectedEncf;
  const rncMatches =
    rnc === null || normalizeRnc(rnc) === normalizeRnc(context.expectedTaxId);

  const checks = {
    HTTP_ACCEPTABLE: httpAcceptable,
    BODY_READABLE: data !== null,
    ENCF_PRESENT: encfValid,
    ENCF_MATCH: encfMatches,
    RNC_MATCH: rncMatches,
    TRACK_ID_PRESENT: trackId !== null,
    // Un aceptado (simple o condicional) debe declarar la secuencia consumida:
    // si el proveedor acepta y dice que no gastó numeración, una de las dos
    // cosas no es cierta y no se puede correlacionar.
    SEQUENCE_CONSISTENT:
      (outcome !== "ACCEPTED" && outcome !== "CONDITIONALLY_ACCEPTED") ||
      sequenceConsumed === true,
  };

  const reasons = Object.entries(checks)
    .filter(([, pass]) => pass === false)
    .map(([key]) => key);
  const correlated = reasons.length === 0;

  const providerOutcome = correlated ? outcome : "UNKNOWN";
  const documentStatus = correlated
    ? DOSA_OUTCOME_STATUS[outcome as keyof typeof DOSA_OUTCOME_STATUS] ?? "HUMAN_REVIEW_REQUIRED"
    : "UNKNOWN_RESULT";

  const base: EcfProviderObservation = {
    checks,
    reasons,
    // DOSA no publica un JSON Schema de respuesta: cadena vacía = «no hay
    // esquema que validar», no «esquema superado».
    schemaSha256: "",
    schemaErrors: classification?.unresolvedReason
      ? [{ path: "$", keyword: classification.unresolvedReason.slice(0, 256) }]
      : [],
    correlated,
    observedOutcome: OUTCOME_VOCABULARY[outcome] ?? "UNKNOWN",
    providerOutcome: OUTCOME_VOCABULARY[providerOutcome] ?? "UNKNOWN",
    safeCode: reasons.length
      ? `ECF_DOSA_${reasons[0]}_FAILED`
      : `ECF_DOSA_OBSERVED_${outcome}`,
    // `trackId` es la referencia de seguimiento del proveedor para ESTA entrega.
    remoteId: correlated ? trackId : null,
    documentNumber: encfValid ? encf : null,
    providerStatus: firstString(data, ["estado"]),
    observedLegalStatus: firstString(data, ["estado"]),
    sequenceConsumed,
    canUpdateFiscalStatus: false,
    canRetryPost: false,
  };

  // `documentStatus` viaja junto al resto: el orquestador lo usa para proponer
  // el estado del documento sin ampliar el tipo compartido.
  return Object.assign(base, { documentStatus });
}

/** Estados de documento que este evaluador puede proponer. */
export type EcfDocumentStatusLike =
  | "HUMAN_REVIEW_REQUIRED"
  | "PROVIDER_REJECTED"
  | "DGII_STATUS_PENDING"
  | "UNKNOWN_RESULT";
