import { randomBytes } from "node:crypto";
import {
  DosaCredentialService,
  type DosaCredentialStore,
  type StoredDosaCredential,
} from "./dosa-credential.service";
import {
  DosaCredentialVault,
  type DosaCredentialEnvironment,
  type DosaCredentialStatus,
} from "./dosa-credential-vault.service";
import {
  DosaEmissionService,
  type DosaCompanyFiscalConfigReader,
} from "./dosa-emission.service";
import type { DosaEmissionConfig, DosaHttpTransport } from "./dosa-emission.client";
import type { DosaEcfRequestBody } from "./dosa-ecf.contract";

/**
 * Selección de API Key y caché del cliente.
 *
 * El defecto que se corrige aquí: en TEST se hacía `apiKeyTest ?? apiKeyProduccion`.
 * Con ese fallback, una empresa sin clave de prueba podía emitir contra el
 * entorno de pruebas firmando con su credencial de PRODUCCIÓN. Ahora cada entorno
 * usa exclusivamente su clave y, si falta, no hay tráfico HTTP.
 */

const MASTER = randomBytes(32).toString("base64");
const COMPANY = "12121212-0000-4000-8000-000000000012";
const OTHER_COMPANY = "13131313-0000-4000-8000-000000000013";
const RNC = "133306001";

const BODY: DosaEcfRequestBody = {
  encabezado: {
    version: "1.0",
    idDoc: { tipoeCF: "31", eNCF: "E31000000113500", fechaEmision: "03-11-2026" },
    emisor: { RNCEmisor: RNC, RazonSocialEmisor: "EMPRESA" },
    totales: {
      MontoGravadoTotal: "100.00",
      MontoGravadoI1: "100.00",
      MontoExento: "0.00",
      ITBIS1: "18",
      TotalITBIS: "18.00",
      MontoTotal: "118.00",
    },
  },
  detallesItems: [],
};

class MemoryStore implements DosaCredentialStore {
  readonly rows = new Map<string, StoredDosaCredential>();
  private key(row: {
    companyId: string;
    rnc: string;
    environment: DosaCredentialEnvironment;
  }) {
    return `${row.companyId}|${row.rnc}|${row.environment}`;
  }
  async upsert(row: StoredDosaCredential) {
    this.rows.set(this.key(row), row);
  }
  async find(row: {
    companyId: string;
    rnc: string;
    environment: DosaCredentialEnvironment;
  }) {
    return this.rows.get(this.key(row)) ?? null;
  }
  async listByCompany(companyId: string) {
    return [...this.rows.values()].filter((row) => row.companyId === companyId);
  }
  async setStatus(row: {
    companyId: string;
    rnc: string;
    environment: DosaCredentialEnvironment;
    status: DosaCredentialStatus;
  }) {
    const current = this.rows.get(this.key(row));
    if (!current) return false;
    this.rows.set(this.key(row), { ...current, status: row.status });
    return true;
  }
}

class FakeFiscalConfig implements DosaCompanyFiscalConfigReader {
  async read(companyId: string) {
    return { ecfEnabled: true, provider: companyId === OTHER_COMPANY ? "ALANUBE" : "DOSA" };
  }
}

class RecordingTransport implements DosaHttpTransport {
  readonly keys: string[] = [];
  async post(_url: string, init: { headers: Record<string, string> }) {
    this.keys.push(init.headers["X-API-KEY"] ?? "");
    return {
      status: 200,
      body: JSON.stringify({ codigo: "1", secuenciaUtilizada: true }),
    };
  }
}

function emissionConfig(overrides: Partial<DosaEmissionConfig> = {}): DosaEmissionConfig {
  return {
    enabled: true,
    environment: "TEST",
    baseUrl: "https://dosasystem.com",
    apiKey: "",
    apiKeyIsProduction: false,
    productionEnabled: false,
    testRnc: RNC,
    timeoutMs: 1000,
    breakerThreshold: 3,
    breakerCooldownMs: 60_000,
    ...overrides,
  };
}

async function build(options: {
  bundle: { apiKeyProduccion?: string; apiKeyTest?: string };
  status?: DosaCredentialStatus;
  config?: Partial<DosaEmissionConfig>;
}) {
  const store = new MemoryStore();
  const credentials = new DosaCredentialService(
    store,
    new DosaCredentialVault(MASTER),
  );
  await credentials.ingestFromProvider({
    companyId: COMPANY,
    rnc: RNC,
    environment: "test",
    bundle: options.bundle,
    signatureAuthenticated: true,
  });
  if (options.status && options.status !== "PENDING_CONFIRMATION") {
    await store.setStatus({
      companyId: COMPANY,
      rnc: RNC,
      environment: "test",
      status: options.status,
    });
  }
  const transport = new RecordingTransport();
  const service = new DosaEmissionService({
    fiscalConfig: new FakeFiscalConfig(),
    credentials,
    config: emissionConfig(options.config),
    transport,
  });
  return { store, credentials, transport, service };
}

describe("Selección de API Key — sin sustitución entre ambientes", () => {
  it("TEST usa la clave de TEST", async () => {
    const { service, transport } = await build({
      bundle: { apiKeyTest: "CLAVE-TEST", apiKeyProduccion: "CLAVE-PROD" },
      status: "ACTIVE",
    });

    const result = await service.emit({
      companyId: COMPANY,
      rnc: RNC,
      documentType: "E31",
      senderTaxId: RNC,
      sequenceAvailable: true,
      body: BODY,
      idempotencyKey: "k-1",
    });

    expect(result.ok).toBe(true);
    expect(transport.keys).toEqual(["CLAVE-TEST"]);
    expect(transport.keys).not.toContain("CLAVE-PROD");
  });

  it("TEST SIN clave de prueba NO emite aunque exista clave de producción", async () => {
    const { service, transport } = await build({
      bundle: { apiKeyProduccion: "CLAVE-PROD" },
      status: "ACTIVE",
    });

    const result = await service.emit({
      companyId: COMPANY,
      rnc: RNC,
      documentType: "E31",
      senderTaxId: RNC,
      sequenceAvailable: true,
      body: BODY,
      idempotencyKey: "k-1",
    });

    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect(result.blockingReasons.join(" ")).toContain(
        "ECF_DOSA_CREDENTIALS_MISSING_FOR_ENVIRONMENT:TEST",
      );
    }
    // Lo importante: no salió ni una petición.
    expect(transport.keys).toHaveLength(0);
  });

  it("PRODUCCIÓN usa la clave de producción", async () => {
    const store = new MemoryStore();
    const credentials = new DosaCredentialService(
      store,
      new DosaCredentialVault(MASTER),
    );
    await credentials.ingestFromProvider({
      companyId: COMPANY,
      rnc: RNC,
      environment: "production",
      bundle: { apiKeyProduccion: "CLAVE-PROD", apiKeyTest: "CLAVE-TEST" },
      signatureAuthenticated: true,
    });
    await store.setStatus({
      companyId: COMPANY,
      rnc: RNC,
      environment: "production",
      status: "ACTIVE",
    });
    const transport = new RecordingTransport();
    const service = new DosaEmissionService({
      fiscalConfig: new FakeFiscalConfig(),
      credentials,
      config: emissionConfig({
        environment: "PRODUCTION",
        productionEnabled: true,
      }),
      transport,
    });

    await service.emit({
      companyId: COMPANY,
      rnc: RNC,
      documentType: "E31",
      senderTaxId: RNC,
      sequenceAvailable: true,
      body: BODY,
      idempotencyKey: "k-1",
    });

    expect(transport.keys).toEqual(["CLAVE-PROD"]);
  });

  it("PRODUCCIÓN sin clave de producción NO usa la de TEST", async () => {
    const store = new MemoryStore();
    const credentials = new DosaCredentialService(
      store,
      new DosaCredentialVault(MASTER),
    );
    await credentials.ingestFromProvider({
      companyId: COMPANY,
      rnc: RNC,
      environment: "production",
      bundle: { apiKeyTest: "CLAVE-TEST" },
      signatureAuthenticated: true,
    });
    await store.setStatus({
      companyId: COMPANY,
      rnc: RNC,
      environment: "production",
      status: "ACTIVE",
    });
    const transport = new RecordingTransport();
    const service = new DosaEmissionService({
      fiscalConfig: new FakeFiscalConfig(),
      credentials,
      config: emissionConfig({
        environment: "PRODUCTION",
        productionEnabled: true,
      }),
      transport,
    });

    const result = await service.emit({
      companyId: COMPANY,
      rnc: RNC,
      documentType: "E31",
      senderTaxId: RNC,
      sequenceAvailable: true,
      body: BODY,
      idempotencyKey: "k-1",
    });

    expect(result.ok).toBe(false);
    expect(transport.keys).toHaveLength(0);
  });
});

describe("Caché del cliente — empresa, RNC, ambiente y versión de credencial", () => {
  it("una empresa distinta obtiene un cliente distinto (no hereda credenciales)", async () => {
    const { service, transport, credentials, store } = await build({
      bundle: { apiKeyTest: "CLAVE-A" },
      status: "ACTIVE",
    });

    // Segunda empresa con su propia credencial.
    await credentials.ingestFromProvider({
      companyId: OTHER_COMPANY,
      rnc: "130000002",
      environment: "test",
      bundle: { apiKeyTest: "CLAVE-B" },
      signatureAuthenticated: true,
    });
    await store.setStatus({
      companyId: OTHER_COMPANY,
      rnc: "130000002",
      environment: "test",
      status: "ACTIVE",
    });

    await service.emit({
      companyId: COMPANY,
      rnc: RNC,
      documentType: "E31",
      senderTaxId: RNC,
      sequenceAvailable: true,
      body: BODY,
      idempotencyKey: "k-1",
    });

    // OTHER_COMPANY es ALANUBE: la compuerta debe impedirlo, no reutilizar el cliente.
    const other = await service.emit({
      companyId: OTHER_COMPANY,
      rnc: "130000002",
      documentType: "E31",
      senderTaxId: "130000002",
      sequenceAvailable: true,
      body: BODY,
      idempotencyKey: "k-2",
    });

    expect(other.ok).toBe(false);
    expect(transport.keys).toEqual(["CLAVE-A"]);
  });

  it("rotar la clave invalida el cliente anterior y usa la nueva", async () => {
    const { service, transport, credentials, store } = await build({
      bundle: { apiKeyTest: "CLAVE-VIEJA" },
      status: "ACTIVE",
    });

    await service.emit({
      companyId: COMPANY,
      rnc: RNC,
      documentType: "E31",
      senderTaxId: RNC,
      sequenceAvailable: true,
      body: BODY,
      idempotencyKey: "k-1",
    });

    await credentials.ingestFromProvider({
      companyId: COMPANY,
      rnc: RNC,
      environment: "test",
      bundle: { apiKeyTest: "CLAVE-NUEVA" },
      signatureAuthenticated: true,
    });
    await store.setStatus({
      companyId: COMPANY,
      rnc: RNC,
      environment: "test",
      status: "ACTIVE",
    });

    await service.emit({
      companyId: COMPANY,
      rnc: RNC,
      documentType: "E31",
      senderTaxId: RNC,
      sequenceAvailable: true,
      body: BODY,
      idempotencyKey: "k-2",
    });

    expect(transport.keys).toEqual(["CLAVE-VIEJA", "CLAVE-NUEVA"]);
    // La clave vieja no se vuelve a usar después de la rotación.
    expect(transport.keys.filter((k) => k === "CLAVE-VIEJA")).toHaveLength(1);
  });

  it("el RNC forma parte de la clave de caché (no comparte cliente entre RNC)", async () => {
    const { service, transport } = await build({
      bundle: { apiKeyTest: "CLAVE-A" },
      status: "ACTIVE",
    });

    await service.emit({
      companyId: COMPANY,
      rnc: RNC,
      documentType: "E31",
      senderTaxId: RNC,
      sequenceAvailable: true,
      body: BODY,
      idempotencyKey: "k-1",
    });
    // Otro RNC de la misma empresa: la compuerta lo rechaza por identidad.
    const other = await service.emit({
      companyId: COMPANY,
      rnc: "130000009",
      documentType: "E31",
      senderTaxId: RNC,
      sequenceAvailable: true,
      body: BODY,
      idempotencyKey: "k-2",
    });

    expect(other.ok).toBe(false);
    expect(transport.keys).toEqual(["CLAVE-A"]);
  });
});
