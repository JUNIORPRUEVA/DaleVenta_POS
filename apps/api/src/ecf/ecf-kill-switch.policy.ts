import type { EcfCertificationStatus, EcfEnvironment } from "@prisma/client";

export type EcfKillSwitchInput = {
  environment: EcfEnvironment | "SANDBOX" | "PRODUCTION";
  providerTransportEnabled: boolean;
  realCallsEnabled: boolean;
  diagnosticEnabled: boolean;
  emissionEnabled: boolean;
  companyEcfEnabled: boolean;
  certificationStatus: EcfCertificationStatus | string;
  userHasPermission: boolean;
  contractApproved: boolean;
};

export type EcfKillSwitchDecision =
  | { ok: true }
  | { ok: false; code: string; safeMessage: string };

export function assertEcfCanPrepareProviderCall(
  input: EcfKillSwitchInput,
): EcfKillSwitchDecision {
  if (input.environment !== "SANDBOX") {
    return blocked("ECF_PRODUCTION_BLOCKED", "Solo Sandbox esta permitido.");
  }
  if (!input.providerTransportEnabled) {
    return blocked("ECF_TRANSPORT_DISABLED", "El transporte Alanube esta deshabilitado.");
  }
  if (!input.realCallsEnabled) {
    return blocked("ECF_REAL_CALLS_DISABLED", "Las llamadas reales estan deshabilitadas.");
  }
  if (!input.userHasPermission) {
    return blocked("ECF_PERMISSION_REQUIRED", "El usuario no tiene permiso e-CF.");
  }
  if (!input.companyEcfEnabled) {
    return blocked("ECF_COMPANY_DISABLED", "La empresa no tiene e-CF habilitado.");
  }
  if (!input.contractApproved) {
    return blocked("ECF_CONTRACT_NOT_APPROVED", "El contrato Alanube no esta aprobado.");
  }
  return { ok: true };
}

export function assertEcfCanEmit(input: EcfKillSwitchInput): EcfKillSwitchDecision {
  const providerCall = assertEcfCanPrepareProviderCall(input);
  if (!providerCall.ok) return providerCall;
  if (!input.emissionEnabled) {
    return blocked("ECF_EMISSION_DISABLED", "La emision e-CF esta deshabilitada.");
  }
  if (input.certificationStatus !== "AUTHORIZED_SANDBOX") {
    return blocked("ECF_CERTIFICATION_REQUIRED", "La empresa no esta autorizada para emision Sandbox.");
  }
  return { ok: true };
}

export function assertEcfCanRunDiagnostic(input: EcfKillSwitchInput): EcfKillSwitchDecision {
  if (input.environment !== "SANDBOX") {
    return blocked("ECF_PRODUCTION_BLOCKED", "Solo Sandbox esta permitido.");
  }
  if (!input.diagnosticEnabled) {
    return blocked("ECF_DIAGNOSTIC_DISABLED", "El diagnostico Alanube esta deshabilitado.");
  }
  if (!input.userHasPermission) {
    return blocked("ECF_PERMISSION_REQUIRED", "El usuario no tiene permiso e-CF.");
  }
  return { ok: true };
}

function blocked(code: string, safeMessage: string): EcfKillSwitchDecision {
  return { ok: false, code, safeMessage };
}
