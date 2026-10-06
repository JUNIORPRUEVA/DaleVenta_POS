import { ConflictException } from "@nestjs/common";
import type { Request } from "express";

export type FinancialRequestPath =
  | "SAFE_NEW_PATH"
  | "LEGACY_COMPAT_PATH"
  | "INVALID_PARTIAL_REQUEST";

export type FinancialClientMetadata = {
  platform?: string;
  appVersion?: string;
  deviceId?: string;
  deviceFamily?: string;
  osVersion?: string;
  deviceModel?: string;
  userAgent?: string;
};

export type FinancialLegacyLogContext = FinancialClientMetadata & {
  operation: string;
  companyId: string;
  userId: string;
  clientRequestId?: string | null;
  resolvedCashSessionId?: string | null;
};

export function financialLegacyCompatEnabled() {
  return flagEnabled(process.env.FINANCIAL_LEGACY_COMPAT);
}

export function cashCloseLegacyCompatEnabled() {
  return flagEnabled(process.env.CASH_CLOSE_LEGACY_COMPAT);
}

export function classifyFinancialContract(
  values: Record<string, unknown>,
  requiredNewFields: string[],
  optionalNewFields: string[] = [],
): FinancialRequestPath {
  const requiredPresent = requiredNewFields.filter((field) =>
    hasValue(values[field]),
  );
  const optionalPresent = optionalNewFields.filter((field) =>
    hasValue(values[field]),
  );
  const totalPresent = requiredPresent.length + optionalPresent.length;

  if (requiredPresent.length === requiredNewFields.length) {
    return "SAFE_NEW_PATH";
  }
  if (totalPresent === 0) {
    return "LEGACY_COMPAT_PATH";
  }
  return "INVALID_PARTIAL_REQUEST";
}

export function legacyCompatRejected() {
  return new ConflictException({
    code: "LEGACY_MISSING_SESSION",
    errorCode: "LEGACY_MISSING_SESSION",
    message: "Actualiza Fullpos para completar esta operación.",
  });
}

export function partialFinancialContractRejected(operation: string) {
  return new ConflictException({
    code: "INVALID_PARTIAL_FINANCIAL_REQUEST",
    errorCode: "INVALID_PARTIAL_FINANCIAL_REQUEST",
    operation,
    message: "Actualiza Fullpos para completar esta operación.",
  });
}

export function financialMetadataFromRequest(
  req: Request,
): FinancialClientMetadata {
  return {
    platform: headerValue(req, "x-client-platform"),
    appVersion: headerValue(req, "x-client-app-version"),
    deviceId: headerValue(req, "x-client-device-id"),
    deviceFamily: headerValue(req, "x-client-device-family"),
    osVersion: headerValue(req, "x-client-os-version"),
    deviceModel: headerValue(req, "x-client-device-model"),
    userAgent: headerValue(req, "user-agent"),
  };
}

export function legacyFinancialLogPayload(context: FinancialLegacyLogContext) {
  return {
    event: "LEGACY_FINANCIAL_REQUEST",
    operation: context.operation,
    companyId: context.companyId,
    userId: context.userId,
    clientRequestId: context.clientRequestId ?? undefined,
    resolvedCashSessionId: context.resolvedCashSessionId ?? undefined,
    platform: context.platform,
    appVersion: context.appVersion,
    deviceId: context.deviceId,
    timestamp: new Date().toISOString(),
  };
}

function hasValue(value: unknown) {
  return `${value ?? ""}`.trim().length > 0;
}

function flagEnabled(value: string | undefined) {
  const normalized = (value ?? "").trim().toLowerCase();
  return ["1", "true", "yes", "on"].includes(normalized);
}

function headerValue(req: Request, name: string) {
  const value = req.headers[name];
  const text = Array.isArray(value) ? value[0] : value;
  const trimmed = `${text ?? ""}`.trim();
  return trimmed.length > 0 ? trimmed : undefined;
}
