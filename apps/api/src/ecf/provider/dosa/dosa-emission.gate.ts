/**
 * Compuerta única de emisión DOSA.
 *
 * Todo lo que puede salir mal en una emisión fiscal se comprueba aquí, en un
 * solo sitio y **antes** de construir el cliente HTTP. La función es pura: no
 * consulta base de datos, no lee entorno y no hace red. El llamador aporta la
 * evidencia; la compuerta decide.
 *
 * Regla de oro: si falta una sola condición, `allowed` es `false` y el motivo se
 * devuelve con código estable. No hay camino "casi autorizado".
 */

import type { EcfDocumentType } from "../../fiscal-core/ecf-fiscal-document";
import type {
  DosaCredentialEnvironment,
  DosaCredentialStatus,
} from "./dosa-credential-vault.service";
import { verifyFiscalIdentity } from "./dosa-emission.policy";

export const DOSA_GATE_BLOCKED = {
  companyNotOptedIn: "ECF_DOSA_GATE_COMPANY_NOT_OPTED_IN",
  providerNotDosa: "ECF_DOSA_GATE_PROVIDER_NOT_DOSA",
  credentialsMissing: "ECF_DOSA_GATE_CREDENTIALS_MISSING",
  credentialsNotActive: "ECF_DOSA_GATE_CREDENTIALS_NOT_ACTIVE",
  credentialsEnvironmentMismatch: "ECF_DOSA_GATE_CREDENTIALS_ENVIRONMENT_MISMATCH",
  emissionDisabled: "ECF_DOSA_GATE_EMISSION_DISABLED",
  productionNotAuthorized: "ECF_DOSA_GATE_PRODUCTION_NOT_AUTHORIZED",
  identityRejected: "ECF_DOSA_GATE_FISCAL_IDENTITY_REJECTED",
  sequenceUnavailable: "ECF_DOSA_GATE_SEQUENCE_UNAVAILABLE",
  documentTypeUnsupported: "ECF_DOSA_GATE_DOCUMENT_TYPE_UNSUPPORTED",
} as const;

/** Tipos que el mapeador de DOSA cubre hoy. */
export const DOSA_GATE_SUPPORTED_TYPES: readonly EcfDocumentType[] = [
  "E31",
  "E32",
  "E34",
];

export type DosaEmissionGateInput = {
  /** La empresa activó e-CF explícitamente. */
  companyEcfEnabled: boolean;
  /** El proveedor asignado a la empresa es DOSA (no Alanube). */
  companyProviderIsDosa: boolean;
  /** Estado de la credencial cifrada, `null` si no existe. */
  credentialStatus: DosaCredentialStatus | null;
  credentialEnvironment: DosaCredentialEnvironment | null;
  /** Entorno en el que se quiere emitir. */
  environment: DosaCredentialEnvironment;
  senderTaxId: string | null;
  expectedTestRnc: string | null;
  /** `DOSA_EMISSION_ENABLED`. */
  providerEmissionEnabled: boolean;
  /** `DOSA_PRODUCTION_EMISSION_ENABLED`. */
  productionEmissionEnabled: boolean;
  sequenceAvailable: boolean;
  documentType: EcfDocumentType;
};

export type DosaEmissionGateDecision = {
  allowed: boolean;
  blockingReasons: readonly string[];
};

export function assessDosaEmissionGate(
  input: DosaEmissionGateInput,
): DosaEmissionGateDecision {
  const blockingReasons: string[] = [];

  if (!DOSA_GATE_SUPPORTED_TYPES.includes(input.documentType)) {
    blockingReasons.push(DOSA_GATE_BLOCKED.documentTypeUnsupported);
  }
  if (!input.companyEcfEnabled) {
    blockingReasons.push(DOSA_GATE_BLOCKED.companyNotOptedIn);
  }
  if (!input.companyProviderIsDosa) {
    blockingReasons.push(DOSA_GATE_BLOCKED.providerNotDosa);
  }
  if (input.credentialStatus === null) {
    blockingReasons.push(DOSA_GATE_BLOCKED.credentialsMissing);
  } else if (input.credentialStatus !== "ACTIVE") {
    // PENDING_CONFIRMATION y CONFIRMED siguen siendo insuficientes: sin
    // activación autorizada no se emite.
    blockingReasons.push(DOSA_GATE_BLOCKED.credentialsNotActive);
  }
  if (
    input.credentialStatus !== null &&
    input.credentialEnvironment !== null &&
    input.credentialEnvironment !== input.environment
  ) {
    blockingReasons.push(DOSA_GATE_BLOCKED.credentialsEnvironmentMismatch);
  }
  if (!input.providerEmissionEnabled) {
    blockingReasons.push(DOSA_GATE_BLOCKED.emissionDisabled);
  }
  if (input.environment === "production" && !input.productionEmissionEnabled) {
    blockingReasons.push(DOSA_GATE_BLOCKED.productionNotAuthorized);
  }

  const identity = verifyFiscalIdentity({
    environment: input.environment,
    senderTaxId: input.senderTaxId,
    expectedTestRnc: input.expectedTestRnc,
  });
  if (!identity.ok) {
    blockingReasons.push(`${DOSA_GATE_BLOCKED.identityRejected}:${identity.reason}`);
  }

  if (!input.sequenceAvailable) {
    blockingReasons.push(DOSA_GATE_BLOCKED.sequenceUnavailable);
  }

  return { allowed: blockingReasons.length === 0, blockingReasons };
}
