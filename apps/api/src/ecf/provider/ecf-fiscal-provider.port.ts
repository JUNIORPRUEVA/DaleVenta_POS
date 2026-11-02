import type { EcfIssuanceMetadata } from "../fiscal-core/alanube-dom.contract";
import type {
  EcfDocumentType,
  EcfFiscalDocument,
} from "../fiscal-core/ecf-fiscal-document";

/**
 * Identificador del proveedor fiscal.
 *
 * Coincide con los valores previstos para `EcfProvider` en Prisma, que hoy solo
 * admite `ALANUBE`. Añadir `DOSA` a la base de datos requiere una migración
 * aditiva y NO se hace en esta fase.
 */
export type EcfFiscalProviderId = "ALANUBE" | "DOSA";

/** Dónde ocurre la transmisión del comprobante. */
export type EcfProviderTransmission = "LOCAL_SIMULATION" | "PROVIDER_CLOUD";

/** Cómo se obtiene la certificación del emisor ante la DGII. */
export type EcfProviderCertification = "ASSISTED_MANUAL" | "EMBEDDED_ASSISTANT";

/**
 * Lo que un adaptador declara sobre sí mismo. Es descriptivo: no activa nada.
 * `realEmissionEnabled` es la única bandera con efecto y por defecto es `false`
 * en todos los adaptadores, de modo que la facturación electrónica sigue
 * desactivada.
 */
export type EcfFiscalProviderCapabilities = {
  providerId: EcfFiscalProviderId;
  label: string;
  transmission: EcfProviderTransmission;
  certification: EcfProviderCertification;
  supportedDocumentTypes: readonly EcfDocumentType[];
  /** Existe consulta de estado implementada contra el proveedor. */
  querySupported: boolean;
  /** Existe recepción de eventos (webhook) implementada. */
  webhookSupported: boolean;
  /** `true` solo si este adaptador puede producir una emisión fiscal real. */
  realEmissionEnabled: boolean;
};

/** Resultado de normalizar un documento fiscal interno al formato del proveedor. */
export type EcfProviderMappingResult =
  | { ok: true; payload: unknown }
  | { ok: false; blockedReason: string };

/**
 * Puerto de proveedor fiscal.
 *
 * Alcance deliberado de esta fase: identidad, capacidades declaradas y
 * **normalización del documento**, que es el único punto realmente distinto
 * entre proveedores.
 *
 * El transporte HTTP y el webhook NO forman parte del puerto todavía: siguen
 * donde están hoy (`documents/ecf-simulated-dispatch.service.ts` y `alanube/`)
 * para no alterar el comportamiento ni abrir ninguna llamada externa. Migrarlos
 * es una fase posterior y explícita.
 */
export interface EcfFiscalProviderPort {
  readonly id: EcfFiscalProviderId;
  readonly capabilities: EcfFiscalProviderCapabilities;
  mapDocument(
    document: EcfFiscalDocument,
    metadata: EcfIssuanceMetadata,
  ): EcfProviderMappingResult;
}

/**
 * Códigos estables de bloqueo del proveedor.
 *
 * `contractBlocked` reutiliza el mismo código que ya usa
 * `EcfEmissionService.prepare`, para no introducir un segundo vocabulario.
 */
export const ECF_PROVIDER_BLOCKED = {
  unknownProvider: "ECF_PROVIDER_UNKNOWN",
  emissionDisabled: "ECF_PROVIDER_EMISSION_DISABLED",
  notImplemented: "ECF_PROVIDER_NOT_IMPLEMENTED",
  contractBlocked: "ECF_EMISSION_CONTRACT_BLOCKED",
} as const;
