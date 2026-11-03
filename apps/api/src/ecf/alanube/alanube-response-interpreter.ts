import type { AlanubeSafeResponse, AlanubeTransportResult } from "./alanube-safe-http.types";
import type { EcfDocumentType } from "../fiscal-core/ecf-fiscal-document";
import { validateAlanubeOfficialResponse } from "./alanube-schema-validator";
import { ALANUBE_DOM_SCHEMAS } from "./contracts/alanube-dom-schemas.generated";

export type AlanubeInterpretedResult =
  | {
      kind: "PROVIDER_ACCEPTED" | "PROVIDER_REJECTED" | "UNKNOWN_RESULT";
      safeCode: string;
      safeMessage: string;
      providerDocumentId?: string;
      providerStatus?: string;
      observedLegalStatus?: string;
    }
  | {
      kind:
        | "AUTHENTICATION_ERROR"
        | "AUTHORIZATION_ERROR"
        | "VALIDATION_ERROR"
        | "RATE_LIMIT"
        | "CONNECTIVITY_ERROR"
        | "UNEXPECTED_RESPONSE";
      safeCode: string;
      safeMessage: string;
    };

export function interpretAlanubeResult(
  result: AlanubeTransportResult,
  documentType?: EcfDocumentType,
): AlanubeInterpretedResult {
  if (!result.ok) {
    if (result.errorCode === "TIMEOUT" || result.errorCode === "NETWORK_ERROR") {
      return {
        kind: "UNKNOWN_RESULT",
        safeCode: result.errorCode,
        safeMessage: "No se obtuvo una respuesta confiable del proveedor.",
      };
    }
    return {
      kind: "UNEXPECTED_RESPONSE",
      safeCode: result.errorCode,
      safeMessage: "Comunicación bloqueada o respuesta no verificable.",
    };
  }
  return interpretAlanubeResponse(result.response, documentType);
}

export function interpretAlanubeResponse(
  response: AlanubeSafeResponse,
  documentType?: EcfDocumentType,
): AlanubeInterpretedResult {
  if (response.statusCode === 401) {
    return {
      kind: "AUTHENTICATION_ERROR",
      safeCode: "ALANUBE_HTTP_401",
      safeMessage: "Alanube rechazó la autenticación.",
    };
  }
  if (response.statusCode === 403) {
    return {
      kind: "AUTHORIZATION_ERROR",
      safeCode: "ALANUBE_HTTP_403",
      safeMessage: "Alanube rechazó la autorización.",
    };
  }
  if (response.statusCode === 429) {
    return {
      kind: "RATE_LIMIT",
      safeCode: "ALANUBE_HTTP_429",
      safeMessage: "Alanube informó límite de solicitudes.",
    };
  }
  if (response.statusCode >= 400 && response.statusCode < 500) {
    if (documentType && ALANUBE_DOM_SCHEMAS[documentType].responses[String(response.statusCode)] &&
        !validateAlanubeOfficialResponse(documentType, response.statusCode, response.body).ok) {
      return { kind: "UNEXPECTED_RESPONSE", safeCode: "ALANUBE_ERROR_SCHEMA_INVALID", safeMessage: "Cuerpo de error no conforme al schema documentado." };
    }
    return {
      kind: "VALIDATION_ERROR",
      safeCode: `ALANUBE_HTTP_${response.statusCode}`,
      safeMessage: "Alanube rechazó la solicitud.",
    };
  }
  if (response.statusCode >= 500 && response.statusCode <= 599) {
    return {
      kind: "UNKNOWN_RESULT",
      safeCode: `ALANUBE_HTTP_${response.statusCode}`,
      safeMessage: "Resultado incierto; requiere conciliación o revisión humana.",
    };
  }
  if (response.statusCode >= 200 && response.statusCode < 300) {
    if (documentType) {
      const validation = validateAlanubeOfficialResponse(documentType, response.statusCode, response.body);
      if (!validation.ok) return { kind: "UNKNOWN_RESULT", safeCode: "ALANUBE_RESPONSE_SCHEMA_INVALID",
        safeMessage: "Respuesta sin conformidad contractual; requiere conciliación." };
      const body = response.body as Record<string, unknown>;
      // Schemas do not require these response properties. Require explicit
      // evidence locally before returning even a processing observation.
      if (typeof body.id !== "string" || typeof body.status !== "string") {
        return { kind: "UNKNOWN_RESULT", safeCode: "ALANUBE_RESPONSE_INCOMPLETE", safeMessage: "Falta identidad o estado verificable del proveedor." };
      }
      const properties = ALANUBE_DOM_SCHEMAS[documentType].responses[String(response.statusCode)].properties as Record<string, unknown>;
      return { kind: "UNKNOWN_RESULT", safeCode: "ALANUBE_PROCESSING_OBSERVED",
        safeMessage: "Estado de procesamiento observado; no acredita aceptación fiscal.",
        providerDocumentId: body.id, providerStatus: body.status,
        ...(properties.legalStatus && typeof body.legalStatus === "string" ? { observedLegalStatus: body.legalStatus } : {}) };
    }
    return {
      kind: "UNKNOWN_RESULT",
      safeCode: "ALANUBE_RESPONSE_SCHEMA_UNVERIFIED",
      safeMessage:
        "HTTP exitoso no equivale a aceptación del proveedor ni de DGII; esquema pendiente.",
    };
  }
  return {
    kind: "UNEXPECTED_RESPONSE",
    safeCode: "ALANUBE_HTTP_UNEXPECTED",
    safeMessage: "Respuesta Alanube no reconocida.",
  };
}

