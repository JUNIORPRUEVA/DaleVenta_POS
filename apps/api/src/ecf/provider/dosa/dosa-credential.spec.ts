import { randomBytes } from "node:crypto";
import {
  DOSA_CREDENTIAL_KEY_VERSION,
  DosaCredentialVault,
  DosaCredentialVaultError,
  type DosaCredentialContext,
} from "./dosa-credential-vault.service";
import {
  DosaCredentialService,
  type DosaCredentialStore,
  type StoredDosaCredential,
} from "./dosa-credential.service";
import type { DosaCredentialEnvironment, DosaCredentialStatus } from "./dosa-credential-vault.service";

/**
 * Bóveda de credenciales fiscales.
 *
 * Todo sintético: las claves de prueba se generan en memoria y no salen del
 * proceso. Lo que se demuestra aquí es que sin la clave correcta y sin el
 * contexto correcto **no se descifra nada**, y que nada sale en claro por
 * ninguna superficie de lectura.
 */

const MASTER = randomBytes(32).toString("base64");
const COMPANY_A = "11111111-1111-4111-8111-111111111111";
const COMPANY_B = "22222222-2222-4222-8222-222222222222";
const RNC_A = "133306001";
const RNC_B = "130000002";

const BUNDLE = {
  apiKeyProduccion: "PROD-KEY-SECRETA",
  apiKeyTest: "TEST-KEY-SECRETA",
  apiSecret: "API-SECRETO",
};

function ctxCompanyA(): DosaCredentialContext {
  return { companyId: COMPANY_A, rnc: RNC_A, environment: "test" };
}

class MemoryStore implements DosaCredentialStore {
  readonly rows = new Map<string, StoredDosaCredential>();
  private key(row: {
    companyId: string;
    rnc: string;
    environment: DosaCredentialEnvironment;
  }) {
    return `${row.companyId}|${row.rnc}|${row.environment}`;
  }

  async upsert(row: StoredDosaCredential): Promise<void> {
    this.rows.set(this.key(row), { ...row, updatedAt: new Date().toISOString() });
  }

  async find(row: {
    companyId: string;
    rnc: string;
    environment: DosaCredentialEnvironment;
  }): Promise<StoredDosaCredential | null> {
    return this.rows.get(this.key(row)) ?? null;
  }

  async listByCompany(companyId: string): Promise<StoredDosaCredential[]> {
    return [...this.rows.values()].filter((row) => row.companyId === companyId);
  }

  async setStatus(row: {
    companyId: string;
    rnc: string;
    environment: DosaCredentialEnvironment;
    status: DosaCredentialStatus;
  }): Promise<boolean> {
    const current = this.rows.get(this.key(row));
    if (!current) return false;
    this.rows.set(this.key(row), { ...current, status: row.status });
    return true;
  }
}

describe("DosaCredentialVault", () => {
  it("sin clave maestra falla cerrado (nunca texto claro)", () => {
    const vault = new DosaCredentialVault(null);
    expect(vault.isReady).toBe(false);
    expect(() => vault.seal(ctxCompanyA(), BUNDLE)).toThrow(
      /DOSA_CREDENTIALS_KEY_MISSING/,
    );
  });

  it("rechaza una clave maestra con tamaño incorrecto", () => {
    const vault = new DosaCredentialVault(Buffer.from("corta").toString("base64"));
    expect(vault.isReady).toBe(false);
  });

  it("cifra y descifra con el contexto correcto", () => {
    const vault = new DosaCredentialVault(MASTER);
    const sealed = vault.seal(ctxCompanyA(), BUNDLE);

    const opened = vault.open({
      sealed,
      context: ctxCompanyA(),
      purpose: "EMISSION",
      authorized: true,
    });
    expect(opened).toEqual(BUNDLE);
  });

  it("el criptograma no contiene ningún valor en claro", () => {
    const vault = new DosaCredentialVault(MASTER);
    const sealed = vault.seal(ctxCompanyA(), BUNDLE);
    const serialized = JSON.stringify(sealed);
    expect(serialized).not.toContain("PROD-KEY-SECRETA");
    expect(serialized).not.toContain("TEST-KEY-SECRETA");
    expect(serialized).not.toContain("API-SECRETO");
    expect(sealed.keyVersion).toBe(DOSA_CREDENTIAL_KEY_VERSION);
  });

  it("dos cifrados del mismo valor son distintos (IV aleatorio)", () => {
    const vault = new DosaCredentialVault(MASTER);
    const first = vault.seal(ctxCompanyA(), BUNDLE);
    const second = vault.seal(ctxCompanyA(), BUNDLE);
    expect(first.ciphertext).not.toBe(second.ciphertext);
    // La huella sí es estable: sirve para detectar cambios sin revelar nada.
    expect(first.fingerprint).toBe(second.fingerprint);
  });

  it("un criptograma movido a otra empresa NO se descifra", () => {
    const vault = new DosaCredentialVault(MASTER);
    const sealed = vault.seal(ctxCompanyA(), BUNDLE);

    expect(() =>
      vault.open({
        sealed,
        context: { companyId: COMPANY_B, rnc: RNC_A, environment: "test" },
        purpose: "EMISSION",
        authorized: true,
      }),
    ).toThrow(/DOSA_CREDENTIALS_TAMPERED/);
  });

  it("un criptograma movido a otro RNC NO se descifra", () => {
    const vault = new DosaCredentialVault(MASTER);
    const sealed = vault.seal(ctxCompanyA(), BUNDLE);
    expect(() =>
      vault.open({
        sealed,
        context: { companyId: COMPANY_A, rnc: RNC_B, environment: "test" },
        purpose: "EMISSION",
        authorized: true,
      }),
    ).toThrow(DosaCredentialVaultError);
  });

  it("un criptograma manipulado NO se descifra (GCM detecta)", () => {
    const vault = new DosaCredentialVault(MASTER);
    const sealed = vault.seal(ctxCompanyA(), BUNDLE);
    const bytes = Buffer.from(sealed.ciphertext, "base64");
    bytes[0] = bytes[0] ^ 0xff;
    expect(() =>
      vault.open({
        sealed: { ...sealed, ciphertext: bytes.toString("base64") },
        context: ctxCompanyA(),
        purpose: "EMISSION",
        authorized: true,
      }),
    ).toThrow(/DOSA_CREDENTIALS_TAMPERED/);
  });

  it("open sin autorización explícita no devuelve nada", () => {
    const vault = new DosaCredentialVault(MASTER);
    const sealed = vault.seal(ctxCompanyA(), BUNDLE);
    expect(() =>
      vault.open({
        sealed,
        context: ctxCompanyA(),
        purpose: "EMISSION",
        authorized: false,
      }),
    ).toThrow(/DOSA_CREDENTIALS_OPEN_NOT_AUTHORIZED/);
  });

  it("un conjunto vacío de credenciales se rechaza", () => {
    const vault = new DosaCredentialVault(MASTER);
    expect(() => vault.seal(ctxCompanyA(), {})).toThrow(
      /DOSA_CREDENTIALS_EMPTY_BUNDLE/,
    );
  });
});

describe("DosaCredentialService", () => {
  function build() {
    const store = new MemoryStore();
    const service = new DosaCredentialService(
      store,
      new DosaCredentialVault(MASTER),
    );
    return { store, service };
  }

  it("un evento NO autenticado no guarda credenciales", async () => {
    const { store, service } = build();
    const result = await service.ingestFromProvider({
      companyId: COMPANY_A,
      rnc: RNC_A,
      environment: "test",
      bundle: BUNDLE,
      signatureAuthenticated: false,
    });
    expect(result).toMatchObject({ ok: false });
    expect(store.rows.size).toBe(0);
  });

  it("un evento autenticado guarda cifrado y en PENDING_CONFIRMATION", async () => {
    const { store, service } = build();
    const result = await service.ingestFromProvider({
      companyId: COMPANY_A,
      rnc: RNC_A,
      environment: "test",
      bundle: BUNDLE,
      signatureAuthenticated: true,
    });

    expect(result).toMatchObject({ ok: true, status: "PENDING_CONFIRMATION" });
    const row = [...store.rows.values()][0];
    expect(row.status).toBe("PENDING_CONFIRMATION");
    expect(JSON.stringify(row)).not.toContain("TEST-KEY-SECRETA");
  });

  it("inspect nunca devuelve valores, solo presencia y huella", async () => {
    const { service } = build();
    await service.ingestFromProvider({
      companyId: COMPANY_A,
      rnc: RNC_A,
      environment: "test",
      bundle: BUNDLE,
      signatureAuthenticated: true,
    });

    const inspection = await service.inspect({
      companyId: COMPANY_A,
      rnc: RNC_A,
      environment: "test",
    });

    expect(inspection).not.toBeNull();
    expect(inspection?.present).toEqual({
      apiKeyProduccion: true,
      apiKeyTest: true,
      apiSecret: true,
    });
    expect(inspection).not.toHaveProperty("apiKeyTest");
    const serialized = JSON.stringify(inspection);
    expect(serialized).not.toContain("TEST-KEY-SECRETA");
    expect(serialized).not.toContain("PROD-KEY-SECRETA");
  });

  it("ACTIVE exige proveedor + DGII + autorización administrativa", async () => {
    const { service } = build();
    await service.ingestFromProvider({
      companyId: COMPANY_A,
      rnc: RNC_A,
      environment: "test",
      bundle: BUNDLE,
      signatureAuthenticated: true,
    });

    const base = {
      companyId: COMPANY_A,
      rnc: RNC_A,
      environment: "test" as const,
      to: "ACTIVE" as const,
    };

    expect(
      await service.promote({
        ...base,
        providerConfirmed: true,
        dgiiApproved: true,
        administrativeAuthorization: false,
      }),
    ).toMatchObject({ ok: false });

    expect(
      await service.promote({
        ...base,
        providerConfirmed: true,
        dgiiApproved: false,
        administrativeAuthorization: true,
      }),
    ).toMatchObject({ ok: false });

    expect(
      await service.promote({
        ...base,
        providerConfirmed: false,
        dgiiApproved: true,
        administrativeAuthorization: true,
      }),
    ).toMatchObject({ ok: false });

    const ok = await service.promote({
      ...base,
      providerConfirmed: true,
      dgiiApproved: true,
      administrativeAuthorization: true,
    });
    expect(ok).toEqual({ ok: true, status: "ACTIVE" });
  });

  it("un evento del proveedor no llega a ACTIVE por sí solo", async () => {
    const { service } = build();
    await service.ingestFromProvider({
      companyId: COMPANY_A,
      rnc: RNC_A,
      environment: "test",
      bundle: BUNDLE,
      signatureAuthenticated: true,
    });
    const inspection = await service.inspect({
      companyId: COMPANY_A,
      rnc: RNC_A,
      environment: "test",
    });
    expect(inspection?.status).toBe("PENDING_CONFIRMATION");
    expect(inspection?.status).not.toBe("ACTIVE");
  });

  it("openForEmission devuelve el valor solo con autorización y contexto correctos", async () => {
    const { service } = build();
    await service.ingestFromProvider({
      companyId: COMPANY_A,
      rnc: RNC_A,
      environment: "test",
      bundle: BUNDLE,
      signatureAuthenticated: true,
    });

    await expect(
      service.openForEmission({
        companyId: COMPANY_A,
        rnc: RNC_A,
        environment: "test",
        authorized: false,
      }),
    ).rejects.toThrow(/DOSA_CREDENTIALS_OPEN_NOT_AUTHORIZED/);

    await expect(
      service.openForEmission({
        companyId: COMPANY_A,
        rnc: RNC_B,
        environment: "test",
        authorized: true,
      }),
    ).rejects.toThrow();

    const opened = await service.openForEmission({
      companyId: COMPANY_A,
      rnc: RNC_A,
      environment: "test",
      authorized: true,
    });
    expect(opened.apiKeyTest).toBe("TEST-KEY-SECRETA");
  });

  it("las credenciales de production y test no se pisan entre sí", async () => {
    const { service } = build();
    await service.ingestFromProvider({
      companyId: COMPANY_A,
      rnc: RNC_A,
      environment: "test",
      bundle: { apiKeyTest: "SOLO-TEST" },
      signatureAuthenticated: true,
    });
    await service.ingestFromProvider({
      companyId: COMPANY_A,
      rnc: RNC_A,
      environment: "production",
      bundle: { apiKeyProduccion: "SOLO-PROD" },
      signatureAuthenticated: true,
    });

    const test = await service.inspect({
      companyId: COMPANY_A,
      rnc: RNC_A,
      environment: "test",
    });
    const production = await service.inspect({
      companyId: COMPANY_A,
      rnc: RNC_A,
      environment: "production",
    });
    expect(test?.present).toEqual({
      apiKeyProduccion: false,
      apiKeyTest: true,
      apiSecret: false,
    });
    expect(production?.present).toEqual({
      apiKeyProduccion: true,
      apiKeyTest: false,
      apiSecret: false,
    });
  });

  it("listForCompany solo ve las credenciales de esa empresa", async () => {
    const { service } = build();
    await service.ingestFromProvider({
      companyId: COMPANY_A,
      rnc: RNC_A,
      environment: "test",
      bundle: BUNDLE,
      signatureAuthenticated: true,
    });
    await service.ingestFromProvider({
      companyId: COMPANY_B,
      rnc: RNC_B,
      environment: "test",
      bundle: { apiKeyTest: "DE-B" },
      signatureAuthenticated: true,
    });

    const listA = await service.listForCompany(COMPANY_A);
    expect(listA).toHaveLength(1);
    expect(listA[0].companyId).toBe(COMPANY_A);
    expect(JSON.stringify(listA)).not.toContain("DE-B");
  });
});
