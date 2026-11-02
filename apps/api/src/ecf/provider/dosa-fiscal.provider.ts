import { mapEcfToDosaDraft } from "./dosa/dosa-ecf.mapper";
import type {
  EcfFiscalProviderCapabilities,
  EcfFiscalProviderPort,
  EcfProviderMappingResult,
} from "./ecf-fiscal-provider.port";

/**
 * Adaptador DOSA.
 *
 * Qué hace de verdad, y qué no:
 *
 * * **`mapDocument` está implementado** contra el contrato documentado por el
 *   proveedor (`encabezado` + `detallesItems` + `informacionReferencia`). El
 *   mapeador devuelve ademas un borrador marcado `DRAFT_NOT_TRANSMITTABLE`: el
 *   mapeo existe; la transmision la decide la compuerta de emision.
 * * **`supportedDocumentTypes` refleja lo que el mapeador cubre**: E31, E32 y
 *   E34. E33/E41 no se declaran porque no estan implementados.
 * * **`webhookSupported` es `true`**: hay endpoint y verificacion de firma
 *   (bloqueada por defecto hasta que el proveedor documente el algoritmo).
 * * **`querySupported` es `false`**: la documentacion oficial del proveedor
 *   **no expone un endpoint de consulta de estado**. Solo documenta
 *   `EnviarFactura` y `NotaDesdeFactura`. Declarar soporte de consulta seria
 *   inventar una API.
 * * **`realEmissionEnabled` es `false` por defecto.** Solo se enciende si el
 *   llamador lo pide explicitamente, y aun asi la decision real la toma
 *   `assessDosaEmissionGate` en cada emision.
 */
export class DosaFiscalProvider implements EcfFiscalProviderPort {
  readonly id = "DOSA" as const;
  readonly capabilities: EcfFiscalProviderCapabilities;

  constructor(options: { realEmissionEnabled?: boolean } = {}) {
    this.capabilities = {
      providerId: "DOSA",
      label: "DOSA e-CF",
      // DOSA firma y transmite en su nube.
      transmission: "PROVIDER_CLOUD",
      certification: "EMBEDDED_ASSISTANT",
      supportedDocumentTypes: ["E31", "E32", "E34"],
      querySupported: false,
      webhookSupported: true,
      realEmissionEnabled: options.realEmissionEnabled === true,
    };
  }

  mapDocument(
    ...args: Parameters<EcfFiscalProviderPort["mapDocument"]>
  ): EcfProviderMappingResult {
    const [document, metadata] = args;
    const mapped = mapEcfToDosaDraft(document, metadata);
    if (!mapped.ok) return { ok: false, blockedReason: mapped.blockedReason };
    return { ok: true, payload: mapped.draft.body };
  }
}
