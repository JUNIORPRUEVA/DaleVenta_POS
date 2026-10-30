import type { AlanubeTransportResult } from "./alanube-safe-http.types";

export type AlanubeErrorClass =
  | "AUTHENTICATION"
  | "AUTHORIZATION"
  | "VALIDATION"
  | "TIMEOUT"
  | "NETWORK"
  | "RATE_LIMIT"
  | "PROVIDER"
  | "UNKNOWN_OUTCOME"
  | "CONTRACT_MISMATCH"
  | "BLOCKED";

export type AlanubeClassifiedError = {
  class: AlanubeErrorClass;
  safeCode: string;
  retryable: boolean;
  requiresHumanReview: boolean;
};

export function classifyAlanubeTransportResult(
  result: AlanubeTransportResult,
  operation: "READ" | "EMISSION" = "EMISSION",
): AlanubeClassifiedError {
  const error = classifyTransport(result);
  return { ...error, retryable: operation === "READ" && error.retryable };
}

function classifyTransport(
  result: AlanubeTransportResult,
): AlanubeClassifiedError {
  if (!result.ok) {
    if (result.errorCode === "TIMEOUT") return classified("TIMEOUT", result.errorCode, true, true);
    if (result.errorCode === "NETWORK_ERROR") return classified("NETWORK", result.errorCode, true, true);
    if (result.errorCode === "PROVIDER_REJECTED") return classified("PROVIDER", result.errorCode, false, true);
    if (result.errorCode === "CONFIGURATION_ERROR") return classified("CONTRACT_MISMATCH", result.errorCode, false, true);
    return classified("BLOCKED", result.errorCode, false, false);
  }
  const status = result.response.statusCode;
  if (status === 401) return classified("AUTHENTICATION", "ALANUBE_HTTP_401", false, true);
  if (status === 403) return classified("AUTHORIZATION", "ALANUBE_HTTP_403", false, true);
  if (status === 429) return classified("RATE_LIMIT", "ALANUBE_HTTP_429", true, false);
  if (status >= 400 && status < 500) return classified("VALIDATION", `ALANUBE_HTTP_${status}`, false, true);
  if (status >= 500) return classified("UNKNOWN_OUTCOME", `ALANUBE_HTTP_${status}`, true, true);
  return classified("UNKNOWN_OUTCOME", "ALANUBE_RESPONSE_REQUIRES_INTERPRETATION", false, true);
}

function classified(
  errorClass: AlanubeErrorClass,
  safeCode: string,
  retryable: boolean,
  requiresHumanReview: boolean,
): AlanubeClassifiedError {
  return { class: errorClass, safeCode, retryable, requiresHumanReview };
}
