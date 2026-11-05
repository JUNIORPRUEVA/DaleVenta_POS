import { ConfigService } from "@nestjs/config";
import type { EcfIssuanceMetadata } from "../fiscal-core/alanube-dom.contract";
import { mapEcfToAlanubeDom } from "../fiscal-core/alanube-dom.mapper";
import { invalidFixtures, validE31WithItbis } from "../fiscal-core/ecf-fixtures";
import { AlanubeFiscalProvider } from "./alanube-fiscal.provider";
import { DosaFiscalProvider } from "./dosa-fiscal.provider";
import { ECF_PROVIDER_BLOCKED, type EcfFiscalProviderPort } from "./ecf-fiscal-provider.port";
import {
  createEcfFiscalProviderRegistry,
  createEcfFiscalProviderRegistryFromConfig,
  EcfProviderRegistry,
  EcfProviderRegistryError,
} from "./ecf-provider.registry";

const metadata: EcfIssuanceMetadata = {
  encf: "E310000000001",
  paymentType: 1,
  sequenceDueDate: "2027-12-31",
  incomeType: 1,
};

/** Sin `sequenceDueDate` ni `incomeType`: el esquema DOM los exige. */
const incompleteMetadata: EcfIssuanceMetadata = { encf: "E310000000001", paymentType: 1 };

function fakeProvider(id: EcfFiscalProviderPort["id"], realEmissionEnabled = false): EcfFiscalProviderPort {
  return {
    id,
    capabilities: {
      providerId: id,
      label: `fake-${id}`,
      transmission: "LOCAL_SIMULATION",
      certification: "ASSISTED_MANUAL",
      supportedDocumentTypes: ["E31"],
      querySupported: false,
      webhookSupported: false,
      realEmissionEnabled,
    },
    mapDocument: () => ({ ok: false, blockedReason: ECF_PROVIDER_BLOCKED.notImplemented }),
  };
}

describe("EcfFiscalProvider port — adaptador Alanube", () => {
  it("declara Alanube apagado por defecto y transmisión simulada", () => {
    const provider = new AlanubeFiscalProvider({ realEmissionEnabled: false });
    expect(provider.id).toBe("ALANUBE");
    expect(provider.capabilities.realEmissionEnabled).toBe(false);
    expect(provider.capabilities.transmission).toBe("LOCAL_SIMULATION");
    expect(provider.capabilities.supportedDocumentTypes).toEqual(["E31", "E32", "E34"]);
  });

  it("conserva exactamente el payload del mapper existente", () => {
    const provider = new AlanubeFiscalProvider({ realEmissionEnabled: false });
    const expected = mapEcfToAlanubeDom(validE31WithItbis, metadata);
    const result = provider.mapDocument(validE31WithItbis, metadata);

    expect(expected.schemaValidation?.ok).toBe(true);
    expect(result).toEqual({ ok: true, payload: expected.payload });
  });

  it("bloquea con el mismo código de contrato cuando el payload no valida", () => {
    const provider = new AlanubeFiscalProvider({ realEmissionEnabled: false });
    const expected = mapEcfToAlanubeDom(validE31WithItbis, incompleteMetadata);
    expect(expected.schemaValidation?.ok).toBe(false);

    expect(provider.mapDocument(validE31WithItbis, incompleteMetadata)).toEqual({
      ok: false,
      blockedReason: "ECF_EMISSION_CONTRACT_BLOCKED",
    });
  });

  it("propaga el mismo fallo que el mapper ante un documento local inválido", () => {
    const provider = new AlanubeFiscalProvider({ realEmissionEnabled: false });
    // El mapper lanza; el adaptador no lo silencia ni lo convierte en otra cosa.
    expect(() => mapEcfToAlanubeDom(invalidFixtures.itbisInconsistent, metadata))
      .toThrow(/ECF_TOTAL_ITBIS_MISMATCH/);
    expect(() => provider.mapDocument(invalidFixtures.itbisInconsistent, metadata))
      .toThrow(/ECF_TOTAL_ITBIS_MISMATCH/);
  });
});

describe("EcfFiscalProvider port — adaptador DOSA", () => {
  it("declara lo que realmente cubre y sigue sin poder emitir por defecto", () => {
    const provider = new DosaFiscalProvider();
    expect(provider.id).toBe("DOSA");
    // Sigue apagado: mapear no es emitir.
    expect(provider.capabilities.realEmissionEnabled).toBe(false);
    // Lo que el mapeador cubre de verdad.
    expect(provider.capabilities.supportedDocumentTypes).toEqual([
      "E31",
      "E32",
      "E34",
    ]);
    expect(provider.capabilities.webhookSupported).toBe(true);
    // No hay endpoint de consulta de estado documentado: no se inventa.
    expect(provider.capabilities.querySupported).toBe(false);
  });

  it("mapea un E31 al contrato documentado, sin marcar el payload como emitible", () => {
    const result = new DosaFiscalProvider().mapDocument(validE31WithItbis, metadata);
    expect(result.ok).toBe(true);
    expect(result).toHaveProperty("payload");
    if (result.ok) {
      const payload = result.payload as {
        encabezado: { idDoc: { tipoeCF: string }; totales: Record<string, string> };
      };
      expect(payload.encabezado.idDoc.tipoeCF).toBe("31");
      expect(payload.encabezado.totales.MontoTotal).toMatch(/^\d+\.\d{2}$/);
    }
  });

  it("sigue fallando cerrado con un tipo que el contrato no cubre", () => {
    const e33 = { ...validE31WithItbis, type: "E33" as never };
    const result = new DosaFiscalProvider().mapDocument(e33, metadata);
    expect(result.ok).toBe(false);
    expect(result).not.toHaveProperty("payload");
  });
});

describe("EcfProviderRegistry", () => {
  const registry = createEcfFiscalProviderRegistry({ alanubeRealEmissionEnabled: false });

  it("registra Alanube y DOSA con DOSA como proveedor por defecto", () => {
    expect(registry.list().map((provider) => provider.id).sort()).toEqual(["ALANUBE", "DOSA"]);
    expect(registry.defaultProvider.id).toBe("DOSA");
  });

  it("informa la disponibilidad real de cada proveedor", () => {
    expect(registry.availability()).toEqual([
      {
        providerId: "ALANUBE",
        registered: true,
        emissionAllowed: false,
        reason: "ECF_PROVIDER_EMISSION_DISABLED",
      },
      {
        providerId: "DOSA",
        registered: true,
        emissionAllowed: false,
        reason: "ECF_PROVIDER_EMISSION_DISABLED",
      },
    ]);
  });

  it("impide emitir con un proveedor apagado", () => {
    expect(() => registry.requireEmissionProvider("ALANUBE")).toThrow(EcfProviderRegistryError);
    expect(() => registry.requireEmissionProvider("ALANUBE")).toThrow(/ECF_PROVIDER_EMISSION_DISABLED/);
    expect(() => registry.requireEmissionProvider("DOSA")).toThrow(/ECF_PROVIDER_EMISSION_DISABLED/);
  });

  it("permite emitir solo cuando la política lo autoriza", () => {
    const enabled = createEcfFiscalProviderRegistry({ alanubeRealEmissionEnabled: true });
    expect(enabled.emissionAllowed("ALANUBE")).toBe(true);
    expect(enabled.requireEmissionProvider("ALANUBE").id).toBe("ALANUBE");
    // DOSA sigue apagado aunque Alanube esté encendido.
    expect(enabled.emissionAllowed("DOSA")).toBe(false);
  });

  it("rechaza un proveedor desconocido en lugar de asumir uno", () => {
    expect(registry.get("DOSA")).toBeInstanceOf(DosaFiscalProvider);
    expect(() => registry.require("E33" as never)).toThrow(/ECF_PROVIDER_UNKNOWN/);
  });

  it("rechaza adaptadores duplicados", () => {
    expect(() => new EcfProviderRegistry([fakeProvider("ALANUBE"), fakeProvider("ALANUBE")]))
      .toThrow(/ECF_PROVIDER_DUPLICATED/);
  });

  it("exige que el proveedor por defecto esté registrado", () => {
    expect(() => new EcfProviderRegistry([fakeProvider("DOSA")], "ALANUBE"))
      .toThrow(/ECF_PROVIDER_UNKNOWN/);
  });
});

describe("createEcfFiscalProviderRegistryFromConfig", () => {
  it("queda apagado con la configuración por defecto (sin llamadas reales)", () => {
    const registry = createEcfFiscalProviderRegistryFromConfig(
      new ConfigService({ ALANUBE_ENV: "sandbox", ALANUBE_ENABLE_REAL_CALLS: "false" }),
    );
    expect(registry.emissionAllowed("ALANUBE")).toBe(false);
    expect(registry.emissionAllowed("DOSA")).toBe(false);
    expect(registry.list()).toHaveLength(2);
  });

  it("no habilita la emisión real sin configuración de sandbox completa", () => {
    const registry = createEcfFiscalProviderRegistryFromConfig(
      new ConfigService({
        ALANUBE_ENV: "sandbox",
        ALANUBE_ENABLE_REAL_CALLS: "true",
        ALANUBE_HTTP_TRANSPORT_ENABLED: "true",
      }),
    );
    // Falta URL oficial y referencia de token: la política existente dice no.
    expect(registry.emissionAllowed("ALANUBE")).toBe(false);
  });
});
