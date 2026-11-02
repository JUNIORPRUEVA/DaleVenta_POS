import type { ConfigService } from "@nestjs/config";
import { isAlanubeRealTransportSelected } from "../alanube/alanube-transport.provider";
import { AlanubeFiscalProvider } from "./alanube-fiscal.provider";
import { DosaFiscalProvider } from "./dosa-fiscal.provider";
import {
  ECF_PROVIDER_BLOCKED,
  type EcfFiscalProviderId,
  type EcfFiscalProviderPort,
} from "./ecf-fiscal-provider.port";

/** Token de inyección del registro. */
export const ECF_FISCAL_PROVIDER_REGISTRY = Symbol("ECF_FISCAL_PROVIDER_REGISTRY");

/** Proveedores conocidos por la plataforma, exista o no adaptador utilizable. */
export const ECF_KNOWN_PROVIDER_IDS: readonly EcfFiscalProviderId[] = ["ALANUBE", "DOSA"];

/**
 * Estado observable de un proveedor.
 *
 * `registered` dice si hay adaptador cargado; `emissionAllowed` dice si ese
 * adaptador puede emitir de verdad AHORA. Ambos son independientes a propósito:
 * DOSA está previsto pero no implementado, y Alanube está implementado pero
 * apagado por política.
 */
export type EcfProviderAvailability = {
  providerId: EcfFiscalProviderId;
  registered: boolean;
  emissionAllowed: boolean;
  reason: string | null;
};

export class EcfProviderRegistryError extends Error {
  /**
   * El mensaje SIEMPRE empieza por el código estable, para que el código viaje
   * también en los logs y en los mensajes de error que ve el operador.
   */
  constructor(
    readonly code: string,
    message?: string,
  ) {
    super(message ? `${code}: ${message}` : code);
    this.name = "EcfProviderRegistryError";
  }
}

/**
 * Registro de proveedores fiscales.
 *
 * Es una pieza de lectura: no emite, no consulta y no hace red. Su única
 * responsabilidad es resolver "qué adaptador corresponde a esta empresa" y
 * decir con honestidad si ese adaptador puede emitir.
 */
export class EcfProviderRegistry {
  private readonly byId: ReadonlyMap<EcfFiscalProviderId, EcfFiscalProviderPort>;

  constructor(
    providers: readonly EcfFiscalProviderPort[],
    private readonly defaultProviderId: EcfFiscalProviderId = "ALANUBE",
  ) {
    const map = new Map<EcfFiscalProviderId, EcfFiscalProviderPort>();
    for (const provider of providers) {
      // Un duplicado sería una ambigüedad fiscal: se rechaza en construcción.
      if (map.has(provider.id)) {
        throw new EcfProviderRegistryError(
          "ECF_PROVIDER_DUPLICATED",
          `Provider ${provider.id} registered twice`,
        );
      }
      map.set(provider.id, provider);
    }
    if (!map.has(defaultProviderId)) {
      throw new EcfProviderRegistryError(
        ECF_PROVIDER_BLOCKED.unknownProvider,
        `Default provider ${defaultProviderId} is not registered`,
      );
    }
    this.byId = map;
  }

  /** Adaptadores cargados, en orden de registro. */
  list(): readonly EcfFiscalProviderPort[] {
    return [...this.byId.values()];
  }

  /** Proveedor por defecto (el que se usa cuando la empresa no fija otro). */
  get defaultProvider(): EcfFiscalProviderPort {
    // El constructor garantiza que existe.
    return this.byId.get(this.defaultProviderId) as EcfFiscalProviderPort;
  }

  /** Adaptador, o `null` si no está registrado. */
  get(providerId: EcfFiscalProviderId): EcfFiscalProviderPort | null {
    return this.byId.get(providerId) ?? null;
  }

  /** Adaptador obligatorio: lanza si el proveedor no está registrado. */
  require(providerId: EcfFiscalProviderId): EcfFiscalProviderPort {
    const provider = this.get(providerId);
    if (!provider) {
      throw new EcfProviderRegistryError(
        ECF_PROVIDER_BLOCKED.unknownProvider,
        `Provider ${providerId} is not registered`,
      );
    }
    return provider;
  }

  /** `true` si el adaptador puede producir una emisión fiscal real ahora. */
  emissionAllowed(providerId: EcfFiscalProviderId): boolean {
    return this.get(providerId)?.capabilities.realEmissionEnabled === true;
  }

  /**
   * Adaptador listo para emitir. Falla cerrado: un proveedor registrado pero
   * apagado NO se devuelve, de modo que nadie puede emitir "por accidente".
   */
  requireEmissionProvider(providerId: EcfFiscalProviderId): EcfFiscalProviderPort {
    const provider = this.require(providerId);
    if (!provider.capabilities.realEmissionEnabled) {
      throw new EcfProviderRegistryError(
        ECF_PROVIDER_BLOCKED.emissionDisabled,
        `Provider ${providerId} cannot emit`,
      );
    }
    return provider;
  }

  /** Estado de todos los proveedores conocidos, incluidos los no registrados. */
  availability(): readonly EcfProviderAvailability[] {
    return ECF_KNOWN_PROVIDER_IDS.map((providerId) => {
      const provider = this.get(providerId);
      if (!provider) {
        return {
          providerId,
          registered: false,
          emissionAllowed: false,
          reason: ECF_PROVIDER_BLOCKED.unknownProvider,
        };
      }
      const allowed = provider.capabilities.realEmissionEnabled;
      return {
        providerId,
        registered: true,
        emissionAllowed: allowed,
        reason: allowed ? null : ECF_PROVIDER_BLOCKED.emissionDisabled,
      };
    });
  }
}

/**
 * Construye el registro por defecto.
 *
 * Alanube se registra con el resultado de la política de sandbox existente, así
 * que por defecto queda apagado. DOSA se registra como estructura sin
 * implementación: presente para diagnóstico, incapaz de emitir.
 */
export function createEcfFiscalProviderRegistry(options: {
  alanubeRealEmissionEnabled: boolean;
}): EcfProviderRegistry {
  return new EcfProviderRegistry(
    [
      new AlanubeFiscalProvider({ realEmissionEnabled: options.alanubeRealEmissionEnabled }),
      new DosaFiscalProvider(),
    ],
    "ALANUBE",
  );
}

/**
 * Variante para inyección de Nest: lee la MISMA política que ya decide el
 * transporte real (`isAlanubeRealTransportSelected`), sin reimplementarla.
 * No hace red ni toca secretos.
 */
export function createEcfFiscalProviderRegistryFromConfig(
  config: ConfigService,
): EcfProviderRegistry {
  return createEcfFiscalProviderRegistry({
    alanubeRealEmissionEnabled: isAlanubeRealTransportSelected(config),
  });
}
