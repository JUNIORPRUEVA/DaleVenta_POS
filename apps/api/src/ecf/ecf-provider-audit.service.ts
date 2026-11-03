import { Injectable } from "@nestjs/common";

export type EcfProviderAuditInput = {
  companyId: string;
  operation: string;
  environment: string;
  correlationId: string;
  result: string;
  durationMs?: number;
  authorizationState: string;
  errorClass?: string;
  metadata?: Record<string, unknown>;
};

@Injectable()
export class EcfProviderAuditService {
  sanitize(input: EcfProviderAuditInput) {
    return redact(input) as EcfProviderAuditInput;
  }
}

export function redact(value: unknown): unknown {
  if (Array.isArray(value)) return value.map(redact);
  if (!value || typeof value !== "object") return value;
  const output: Record<string, unknown> = {};
  for (const [key, item] of Object.entries(value as Record<string, unknown>)) {
    const normalized = key.toLowerCase();
    if (
      normalized === "authorization" ||
      normalized.includes("token") ||
      normalized.includes("secret") ||
      normalized.includes("password") ||
      normalized.includes("payload") ||
      normalized.includes("body")
    ) {
      output[key] = "[REDACTED]";
    } else {
      output[key] = redact(item);
    }
  }
  return output;
}
