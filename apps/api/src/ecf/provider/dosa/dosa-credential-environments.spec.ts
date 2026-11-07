import {
  DosaCredentialService,
  PrismaDosaCredentialStore,
  type DosaCredentialStore,
  type StoredDosaCredential,
} from "./dosa-credential.service";
import { splitCredentialsByEnvironment } from "./dosa-credential-environments";
import {
  DosaCredentialVault,
  type DosaCredentialEnvironment,
} from "./dosa-credential-vault.service";

/**
 * Reparto de credenciales por ambiente y endurecimiento del `upsert`.
 *
 * Caso real que origina estos casos (06–07/11/2026): DOSA entregó las dos llaves
 * de FULLTECH en un evento con `ambiente=Produccion`. El receptor guardó el
 * paquete completo bajo `environment=production`, así que la clave TEST quedó
 * encerrada en la fila de producción y la emisión de pruebas no podía usarla.
 *
 * Lo que esta suite fija:
 *
 * 1. Cada llave acaba en la fila de SU ambiente, venga como venga el evento.
 * 2. Un paquete parcial nunca borra la llave que no trae.
 * 3. El `upsert` no degrada `CONFIRMED`/`ACTIVE` ni reescribe si nada cambió.
 * 4. La reclasificación de lo ya guardado es idempotente y exige autorización.
 * 5. Nada de esto activa emisión ni mezcla empresas.
 */

const MASTER_KEY = Buffer.alloc(32, 7).toString("base64");
const COMPANY_A = "aaaaaaaa-0000-4000-8000-00000000000a";
const COMPANY_B = "bbbbbbbb-0000-4000-8000-00000000000b";
const RNC = "133080206";

function newVault(): DosaCredentialVault {
  return new DosaCredentialVault(MASTER_KEY);
}

/** Almacén en memoria con la misma semántica que la tabla real. */
function memoryStore() {
  const rows = new Map<string, StoredDosaCredential>();
  const writes: string[] = [];
  const keyOf = (input: {
    companyId: string;
    rnc: string;
    environment: DosaCredentialEnvironment;
  }) => `${input.companyId}|${input.rnc}|${input.environment}`;

  const store: DosaCredentialStore = {
    async upsert(row) {
      writes.push(row.environment);
      const existing = rows.get(keyOf(row));
      rows.set(keyOf(row), {
        ...row,
        // Igual que el SQL: nunca se degrada un estado ya alcanzado.
        status:
          existing && (existing.status === "CONFIRMED" || existing.status === "ACTIVE")
            ? existing.status
            : row.status,
      });
    },
    async find(input) {
      return rows.get(keyOf(input)) ?? null;
    },
    async listByCompany(companyId) {
      return [...rows.values()].filter((row) => row.companyId === companyId);
    },
    async setStatus(input) {
      const row = rows.get(keyOf(input));
      if (!row) return false;
      rows.set(keyOf(input), { ...row, status: input.status });
      return true;
    },
  };

  return { store, rows, writes, keyOf };
}

describe("reparto por ambiente", () => {
  it("separa las dos llaves y comparte el secreto", () => {
    const split = splitCredentialsByEnvironment({
      apiKeyProduccion: "prod-value",
      apiKeyTest: "test-value",
      apiSecret: "shared-secret",
    });

    expect(split.targets).toHaveLength(2);
    expect(split.targets[0]).toEqual({
      environment: "production",
      bundle: { apiKeyProduccion: "prod-value", apiSecret: "shared-secret" },
    });
    expect(split.targets[1]).toEqual({
      environment: "test",
      bundle: { apiKeyTest: "test-value", apiSecret: "shared-secret" },
    });
  });

  it("no inventa el ambiente que no trae su llave", () => {
    const onlyProd = splitCredentialsByEnvironment({ apiKeyProduccion: "p" });
    expect(onlyProd.targets.map((t) => t.environment)).toEqual(["production"]);
    expect(onlyProd.skipped).toEqual([
      { environment: "test", reason: "DEFINING_KEY_ABSENT" },
    ]);

    const onlyTest = splitCredentialsByEnvironment({ apiKeyTest: "t" });
    expect(onlyTest.targets.map((t) => t.environment)).toEqual(["test"]);
  });

  it("trata vacío y espacios como ausente", () => {
    const split = splitCredentialsByEnvironment({
      apiKeyProduccion: "   ",
      apiKeyTest: "",
      apiSecret: "s",
    });
    expect(split.targets).toHaveLength(0);
    expect(split.skipped).toHaveLength(2);
  });

  it("un secreto suelto no crea ninguna fila", () => {
    expect(splitCredentialsByEnvironment({ apiSecret: "solo" }).targets).toHaveLength(0);
  });
});

describe("ingesta: cada llave en su ambiente", () => {
  it("un evento con ambiente Produccion y las dos llaves crea DOS filas", async () => {
    const { store, rows } = memoryStore();
    const service = new DosaCredentialService(store, newVault());

    const result = await service.ingestFromProvider({
      companyId: COMPANY_A,
      rnc: RNC,
      environment: "production",
      bundle: { apiKeyProduccion: "p", apiKeyTest: "t", apiSecret: "s" },
      signatureAuthenticated: true,
    });

    expect(result.ok).toBe(true);
    expect(rows.size).toBe(2);

    const prod = rows.get(`${COMPANY_A}|${RNC}|production`)!;
    const test = rows.get(`${COMPANY_A}|${RNC}|test`)!;
    expect(prod.sealed.present).toEqual({
      apiKeyProduccion: true,
      apiKeyTest: false,
      apiSecret: true,
    });
    expect(test.sealed.present).toEqual({
      apiKeyProduccion: false,
      apiKeyTest: true,
      apiSecret: true,
    });
    // Ambos entran sin activar nada.
    expect(prod.status).toBe("PENDING_CONFIRMATION");
    expect(test.status).toBe("PENDING_CONFIRMATION");
  });

  it("un evento que solo trae producción no toca la fila de TEST", async () => {
    const { store, rows, writes } = memoryStore();
    const service = new DosaCredentialService(store, newVault());

    await service.ingestFromProvider({
      companyId: COMPANY_A,
      rnc: RNC,
      environment: "production",
      bundle: { apiKeyProduccion: "p1", apiKeyTest: "t1" },
      signatureAuthenticated: true,
    });
    const testBefore = rows.get(`${COMPANY_A}|${RNC}|test`)!;

    writes.length = 0;
    const result = await service.ingestFromProvider({
      companyId: COMPANY_A,
      rnc: RNC,
      environment: "production",
      bundle: { apiKeyProduccion: "p2" },
      signatureAuthenticated: true,
    });

    expect(result.ok).toBe(true);
    expect(writes).toEqual(["production"]);
    expect(rows.get(`${COMPANY_A}|${RNC}|test`)).toEqual(testBefore);
  });

  it("sin firma autenticada no escribe nada", async () => {
    const { store, rows } = memoryStore();
    const service = new DosaCredentialService(store, newVault());

    const result = await service.ingestFromProvider({
      companyId: COMPANY_A,
      rnc: RNC,
      environment: "production",
      bundle: { apiKeyProduccion: "p" },
      signatureAuthenticated: false,
    });

    expect(result).toMatchObject({
      ok: false,
      blockedReason: "ECF_DOSA_CREDENTIALS_EVENT_NOT_AUTHENTICATED",
    });
    expect(rows.size).toBe(0);
  });

  it("un paquete sin ninguna llave se rechaza sin escribir", async () => {
    const { store, rows } = memoryStore();
    const service = new DosaCredentialService(store, newVault());

    const result = await service.ingestFromProvider({
      companyId: COMPANY_A,
      rnc: RNC,
      environment: "production",
      bundle: { apiSecret: "solo" },
      signatureAuthenticated: true,
    });

    expect(result).toMatchObject({
      ok: false,
      blockedReason: "ECF_DOSA_CREDENTIALS_EMPTY_BUNDLE",
    });
    expect(rows.size).toBe(0);
  });

  it("dos empresas con el mismo RNC no se mezclan", async () => {
    const { store, rows } = memoryStore();
    const service = new DosaCredentialService(store, newVault());

    await service.ingestFromProvider({
      companyId: COMPANY_A,
      rnc: RNC,
      environment: "production",
      bundle: { apiKeyProduccion: "a", apiKeyTest: "at" },
      signatureAuthenticated: true,
    });
    await service.ingestFromProvider({
      companyId: COMPANY_B,
      rnc: RNC,
      environment: "production",
      bundle: { apiKeyProduccion: "b", apiKeyTest: "bt" },
      signatureAuthenticated: true,
    });

    expect(rows.size).toBe(4);
    expect(rows.get(`${COMPANY_A}|${RNC}|test`)!.sealed.fingerprint).not.toBe(
      rows.get(`${COMPANY_B}|${RNC}|test`)!.sealed.fingerprint,
    );
  });

  it("un criptograma de una empresa no se abre en el contexto de otra", async () => {
    const { store, rows } = memoryStore();
    const vault = newVault();
    const service = new DosaCredentialService(store, vault);

    await service.ingestFromProvider({
      companyId: COMPANY_A,
      rnc: RNC,
      environment: "production",
      bundle: { apiKeyProduccion: "a" },
      signatureAuthenticated: true,
    });

    const row = rows.get(`${COMPANY_A}|${RNC}|production`)!;
    expect(() =>
      vault.open({
        sealed: row.sealed,
        context: { companyId: COMPANY_B, rnc: RNC, environment: "production" },
        purpose: "REMEDIATION",
        authorized: true,
      }),
    ).toThrow(/DOSA_CREDENTIALS_TAMPERED|DOSA_CREDENTIALS_CONTEXT_MISMATCH/);
  });
});

describe("reclasificación de lo ya guardado", () => {
  async function seedLegacyRow() {
    const { store, rows } = memoryStore();
    const vault = newVault();
    // Reproduce el estado real: el paquete completo quedó en producción.
    const sealed = vault.seal(
      { companyId: COMPANY_A, rnc: RNC, environment: "production" },
      { apiKeyProduccion: "p", apiKeyTest: "t", apiSecret: "s" },
    );
    rows.set(`${COMPANY_A}|${RNC}|production`, {
      companyId: COMPANY_A,
      rnc: RNC,
      environment: "production",
      status: "PENDING_CONFIRMATION",
      source: "WEBHOOK",
      sealed,
      updatedAt: null,
    });
    return { store, rows, vault, service: new DosaCredentialService(store, vault) };
  }

  it("sin autorización no descifra ni escribe", async () => {
    const { service, rows } = await seedLegacyRow();

    const result = await service.reclassifyStoredCredentials({
      companyId: COMPANY_A,
      rnc: RNC,
      sourceEnvironment: "production",
      authorized: false,
    });

    expect(result).toMatchObject({
      ok: false,
      blockedReason: "DOSA_CREDENTIALS_OPEN_NOT_AUTHORIZED",
    });
    expect(rows.size).toBe(1);
  });

  it("crea la fila TEST y deja intacta la de producción", async () => {
    const { service, rows } = await seedLegacyRow();
    const prodBefore = rows.get(`${COMPANY_A}|${RNC}|production`)!;

    const result = await service.reclassifyStoredCredentials({
      companyId: COMPANY_A,
      rnc: RNC,
      sourceEnvironment: "production",
      authorized: true,
    });

    expect(result.ok).toBe(true);
    expect(result.written.map((entry) => entry.environment)).toEqual(["test"]);
    expect(rows.get(`${COMPANY_A}|${RNC}|production`)).toEqual(prodBefore);
    expect(rows.get(`${COMPANY_A}|${RNC}|test`)!.sealed.present).toEqual({
      apiKeyProduccion: false,
      apiKeyTest: true,
      apiSecret: true,
    });
  });

  it("es idempotente: la segunda pasada no escribe nada", async () => {
    const { service } = await seedLegacyRow();

    await service.reclassifyStoredCredentials({
      companyId: COMPANY_A,
      rnc: RNC,
      sourceEnvironment: "production",
      authorized: true,
    });
    const second = await service.reclassifyStoredCredentials({
      companyId: COMPANY_A,
      rnc: RNC,
      sourceEnvironment: "production",
      authorized: true,
    });

    expect(second.written).toHaveLength(0);
    expect(second.already).toEqual(expect.arrayContaining(["production", "test"]));
  });

  it("en dry-run informa lo que haría sin escribir", async () => {
    const { service, rows } = await seedLegacyRow();

    const result = await service.reclassifyStoredCredentials({
      companyId: COMPANY_A,
      rnc: RNC,
      sourceEnvironment: "production",
      authorized: true,
      dryRun: true,
    });

    expect(result.ok).toBe(true);
    expect(result.applied).toBe(false);
    expect(result.written.map((entry) => entry.environment)).toEqual(["test"]);
    // Nada se escribió: sigue habiendo solo la fila de producción.
    expect(rows.size).toBe(1);
  });

  it("no reclasifica nada si la fila no existe", async () => {
    const { store } = memoryStore();
    const service = new DosaCredentialService(store, newVault());

    const result = await service.reclassifyStoredCredentials({
      companyId: COMPANY_A,
      rnc: RNC,
      sourceEnvironment: "production",
      authorized: true,
    });

    expect(result).toMatchObject({ ok: false, blockedReason: "DOSA_CREDENTIALS_NOT_FOUND" });
  });
});

describe("upsert endurecido (SQL)", () => {
  function captureSql() {
    const queries: string[] = [];
    const client = {
      async $queryRaw<T>(query: TemplateStringsArray) {
        queries.push(query.join("?"));
        return [] as unknown as T;
      },
    };
    return { queries, client };
  }

  const row: StoredDosaCredential = {
    companyId: COMPANY_A,
    rnc: RNC,
    environment: "production",
    status: "PENDING_CONFIRMATION",
    source: "WEBHOOK",
    sealed: {
      ciphertext: "c",
      iv: "i",
      authTag: "a",
      keyVersion: 1,
      fingerprint: "f",
      present: { apiKeyProduccion: true, apiKeyTest: false, apiSecret: false },
    },
    updatedAt: null,
  };

  it("nunca rebaja un estado CONFIRMED o ACTIVE", async () => {
    const { queries, client } = captureSql();
    await new PrismaDosaCredentialStore(client).upsert(row);
    const sql = queries[0];

    expect(sql).toContain("IN ('CONFIRMED','ACTIVE')");
    expect(sql).toContain("THEN");
  });

  it("no reescribe la fila cuando el fingerprint no cambia", async () => {
    const { queries, client } = captureSql();
    await new PrismaDosaCredentialStore(client).upsert(row);

    expect(queries[0]).toContain('IS DISTINCT FROM EXCLUDED."fingerprint"');
  });

  it("conserva created_at: solo actualiza updated_at", async () => {
    const { queries, client } = captureSql();
    await new PrismaDosaCredentialStore(client).upsert(row);
    const updateSection = queries[0].split("DO UPDATE SET")[1] ?? "";

    expect(updateSection).toContain('"updated_at" = NOW()');
    expect(updateSection).not.toContain('"created_at"');
  });

  it("sigue usando la clave única que aísla empresa, RNC y ambiente", async () => {
    const { queries, client } = captureSql();
    await new PrismaDosaCredentialStore(client).upsert(row);

    expect(queries[0]).toContain('ON CONFLICT ("company_id","rnc","environment")');
  });
});
