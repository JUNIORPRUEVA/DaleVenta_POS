import type { EcfCertificationStatus, EcfElectronicDocumentStatus } from "@prisma/client";
import type { AlanubeDomMapping } from "./fiscal-core/alanube-dom.contract";
import { contractAllowsEmission } from "./ecf-contract-registry";
import { alanubeTypeFor, validateAlanubeRequestConformance } from "./fiscal-core/alanube-dom.contract";
import type { EcfFiscalDocument } from "./fiscal-core/ecf-fiscal-document";
import { fingerprint } from "./documents/ecf-document-idempotency.service";

export type EcfPreEmissionInput = {
  companyId: string;
  documentStatus: EcfElectronicDocumentStatus | string;
  certificationStatus: EcfCertificationStatus | string;
  canEmit: boolean;
  idempotencyKey?: string | null;
  mapping: AlanubeDomMapping;
  authenticatedCompanyId?: string;
  documentCompanyId?: string;
  companyTaxId?: string;
  configuredProviderCompanyId?: string;
  userHasPermission?: boolean;
  authorizationGranted?: boolean;
  environment?: string;
  document?: EcfFiscalDocument;
  expectedFingerprint?: string;
  expectedPayloadFingerprint?: string;
};

export type EcfPreEmissionDecision =
  | { ok: true }
  | { ok: false; code: string; safeMessage: string };

export function assertEcfPreEmissionReady(input: EcfPreEmissionInput): EcfPreEmissionDecision {
  if (!input.companyId) return blocked("ECF_COMPANY_REQUIRED", "Empresa requerida.");
  if (!input.canEmit) return blocked("ECF_EMISSION_DISABLED", "La emision e-CF esta deshabilitada.");
  const type = alanubeTypeFor(input.mapping.kind);
  if (!type || input.document?.type !== type) return blocked("ECF_DOCUMENT_TYPE_MISMATCH", "Tipo documental no verificado.");
  if (type === "E34") return blocked("ECF_E34_ISSUANCE_BLOCKED", "E34 requiere orquestación transaccional y conciliación fiscal verificadas; envío bloqueado.");
  if (input.environment !== "SANDBOX") return blocked("ECF_ENVIRONMENT_BLOCKED", "Solo Sandbox permitido.");
  if (input.authenticatedCompanyId !== input.companyId || input.documentCompanyId !== input.companyId ||
      !input.companyTaxId || input.mapping.payload.sender?.rnc !== input.companyTaxId ||
      !input.configuredProviderCompanyId || input.mapping.payload.company?.id !== input.configuredProviderCompanyId) {
    return blocked("ECF_TENANT_MISMATCH", "Contexto de empresa no verificado.");
  }
  if (!input.userHasPermission || !input.authorizationGranted) return blocked("ECF_AUTHORIZATION_REQUIRED", "Autorización expresa y permiso requeridos.");
  if (input.certificationStatus !== "AUTHORIZED_SANDBOX") {
    return blocked("ECF_CERTIFICATION_REQUIRED", "Certificacion Sandbox requerida.");
  }
  if (input.documentStatus !== "READY_TO_SEND") {
    return blocked("ECF_DOCUMENT_NOT_READY", "El documento no esta listo para enviar.");
  }
  if (!input.idempotencyKey?.trim()) {
    return blocked("ECF_IDEMPOTENCY_REQUIRED", "La operacion requiere idempotencia.");
  }
  const uuid = "[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}";
  if (!new RegExp(`^${uuid}$`).test(input.companyId) ||
      !new RegExp(`^ecf:v2:${input.companyId}:${type}:(?:REQUEST:${uuid}|SOURCE:(?:SALE|COTIZACION|MANUAL):${uuid})$`).test(input.idempotencyKey) ||
      input.expectedFingerprint !== fingerprint(input.document) ||
      input.expectedPayloadFingerprint !== fingerprint(input.mapping.payload)) {
    return blocked("ECF_OPERATION_IDENTITY_MISMATCH", "Identidad o contenido de operación no verificados.");
  }
  if (!validateAlanubeRequestConformance(type, input.mapping.payload).ok) return blocked("ECF_PAYLOAD_INVALID", "Payload inválido para contrato DOM.");
  if (input.mapping.contractStatus !== "CONFIRMED_OFFICIAL" || !contractAllowsEmission(type)) {
    return blocked("ECF_CONTRACT_BLOCKED", "Contrato Alanube incompleto para emision.");
  }
  return { ok: true };
}

function blocked(code: string, safeMessage: string): EcfPreEmissionDecision {
  return { ok: false, code, safeMessage };
}
