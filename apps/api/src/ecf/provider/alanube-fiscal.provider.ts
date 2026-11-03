import type { EcfIssuanceMetadata } from "../fiscal-core/alanube-dom.contract";
import { mapEcfToAlanubeDom } from "../fiscal-core/alanube-dom.mapper";
import type { EcfFiscalDocument } from "../fiscal-core/ecf-fiscal-document";
import {
  ECF_PROVIDER_BLOCKED,
  type EcfFiscalProviderCapabilities,
  type EcfFiscalProviderPort,
  type EcfProviderMappingResult,
} from "./ecf-fiscal-provider.port";

export type AlanubeFiscalProviderOptions = {
  /**
   * Resultado de la política de sandbox que YA existe
   * (`isAlanubeRealTransportSelected`). Se inyecta para que el adaptador no
   * implemente una segunda definición de "el transporte real está activo".
   */
  realEmissionEnabled: boolean;
};

/**
 * Adaptador Alanube.
 *
 * Conserva el comportamiento actual sin duplicar lógica: delega en
 * `mapEcfToAlanubeDom` y aplica exactamente la misma comprobación de contrato
 * que hace `EcfEmissionService.prepare` antes de aceptar el borrador local.
 *
 * No contiene transporte, ni URLs, ni credenciales: no puede emitir nada.
 */
export class AlanubeFiscalProvider implements EcfFiscalProviderPort {
  readonly id = "ALANUBE" as const;
  readonly capabilities: EcfFiscalProviderCapabilities;

  constructor(options: AlanubeFiscalProviderOptions) {
    this.capabilities = {
      providerId: "ALANUBE",
      label: "Alanube DOM",
      transmission: options.realEmissionEnabled ? "PROVIDER_CLOUD" : "LOCAL_SIMULATION",
      certification: "ASSISTED_MANUAL",
      supportedDocumentTypes: ["E31", "E32", "E34"],
      // No hay consulta de estado ni recepción de eventos implementadas contra
      // el proveedor: se declara la realidad, no la intención.
      querySupported: false,
      webhookSupported: false,
      realEmissionEnabled: options.realEmissionEnabled,
    };
  }

  mapDocument(
    document: EcfFiscalDocument,
    metadata: EcfIssuanceMetadata,
  ): EcfProviderMappingResult {
    const mapping = mapEcfToAlanubeDom(document, metadata);
    if (mapping.schemaValidation?.ok !== true) {
      return { ok: false, blockedReason: ECF_PROVIDER_BLOCKED.contractBlocked };
    }
    return { ok: true, payload: mapping.payload };
  }
}
