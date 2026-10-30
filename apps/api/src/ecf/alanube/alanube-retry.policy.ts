import type { AlanubeErrorClass } from "./alanube-error-classifier";

export type AlanubeRetryOperation = "READ" | "EMISSION" | "QUERY_STATUS" | "WEBHOOK";

export type AlanubeRetryDecision =
  | { retry: true; delayMs: number; reason: string }
  | { retry: false; reason: string };

export function decideAlanubeRetry(input: {
  operation: AlanubeRetryOperation;
  errorClass: AlanubeErrorClass;
  attempt: number;
  idempotent: boolean;
}): AlanubeRetryDecision {
  if (input.attempt >= 3) return { retry: false, reason: "MAX_ATTEMPTS" };
  if (input.operation === "EMISSION") {
    return { retry: false, reason: input.idempotent ? "PROVIDER_IDEMPOTENCY_UNVERIFIED" : "NON_IDEMPOTENT_EMISSION" };
  }
  if (["TIMEOUT", "NETWORK", "RATE_LIMIT"].includes(input.errorClass)) {
    return {
      retry: true,
      delayMs: Math.min(30000, 1000 * 2 ** input.attempt),
      reason: input.errorClass,
    };
  }
  if (input.errorClass === "UNKNOWN_OUTCOME") {
    return input.operation === "QUERY_STATUS"
      ? { retry: true, delayMs: 5000, reason: "STATUS_UNKNOWN" }
      : { retry: false, reason: "UNKNOWN_OUTCOME_REQUIRES_CONCILIATION" };
  }
  return { retry: false, reason: "NOT_RETRYABLE" };
}
