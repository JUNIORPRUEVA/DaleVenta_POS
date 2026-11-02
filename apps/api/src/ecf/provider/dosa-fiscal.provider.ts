import type { EcfFiscalProviderCapabilities, EcfFiscalProviderPort, EcfProviderMappingResult } from "./ecf-fiscal-provider.port";
import { ECF_PROVIDER_BLOCKED } from "./ecf-fiscal-provider.port";

/**
 * Adaptador DOSA — **solo estructura, sin implementación**.
 *
 * Existe para fijar el destino de la arquitectura y para que el registro pueda
 * informar de su estado real. Deliberadamente:
 *
 * - NO conoce el contrato JSON de `EnviarFactura` (`encabezado`,
 *   `detallesItems`, `Subtotales`, …) porque todavía no está implementado.
 * - NO hace ninguna llamada de red, ni tiene API Key, ni URL, ni credenciales.
 * - `mapDocument` falla cerrado: nunca devuelve un payload.
 *
 * Implementarlo requiere los materiales del proveedor y una fase autorizada
 * aparte (ver `docs/ECF_DOSA_INTEGRATION_READINESS.md`).
 */
export class DosaFiscalProvider implements EcfFiscalProviderPort {
  readonly id = "DOSA" as const;
  readonly capabilities: EcfFiscalProviderCapabilities = {
    providerId: "DOSA",
    label: "DOSA e-CF",
    // DOSA firma y transmite en su nube; aún no hay integración conectada.
    transmission: "PROVIDER_CLOUD",
    certification: "EMBEDDED_ASSISTANT",
    // Sin contrato implementado no se declara ningún tipo como soportado.
    supportedDocumentTypes: [],
    querySupported: false,
    webhookSupported: false,
    realEmissionEnabled: false,
  };

  mapDocument(): EcfProviderMappingResult {
    return { ok: false, blockedReason: ECF_PROVIDER_BLOCKED.notImplemented };
  }
}
