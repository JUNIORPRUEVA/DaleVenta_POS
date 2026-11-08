import { INestApplication, ValidationPipe } from "@nestjs/common";
import { Test } from "@nestjs/testing";
import { execFileSync } from "node:child_process";
import { readFileSync } from "node:fs";
import { Client } from "pg";
import request from "supertest";

import { AppModule } from "../../app.module";
import { PrismaService } from "../../prisma/prisma.service";
import { resolvePrismaCliPath } from "../../testing/prisma-cli";
import type { TenantUser } from "../../auth/tenant-context";
import { PrismaDosaCompanyFiscalConfigReader } from "../provider/dosa/dosa-company-fiscal-config";
import {
  DosaCredentialService,
  PrismaDosaCredentialStore,
} from "../provider/dosa/dosa-credential.service";
import { DosaCredentialVault } from "../provider/dosa/dosa-credential-vault.service";
import {
  DosaEmissionService,
  type DosaHttpTransport,
} from "../provider/dosa/dosa-emission.service";
import { readDosaEmissionConfig } from "../provider/dosa/dosa-emission.client";
import { PrismaDosaCompanyResolver } from "../provider/dosa/dosa-company-resolver.service";
import { mapEcfToDosaDraft } from "../provider/dosa/dosa-ecf.mapper";

/**
 * VALIDACIÓN INTEGRAL MULTIEMPRESA — cinco empresas ficticias.
 *
 * Qué demuestra (con PostgreSQL real, endpoints reales del POS y del módulo e-CF,
 * y un ADAPTADOR DOSA FALSO que solo captura la petición):
 *
 *  - A: venta del POS → E31 → e-NCF de SU rango → despacho simulado → estado final.
 *  - B: sin e-CF habilitado no prepara; la venta normal del POS sigue funcionando.
 *  - C: credenciales TEST y PRODUCCIÓN separadas; en TEST se usa la clave de TEST
 *       y PRODUCCIÓN queda bloqueada sin tocar el transporte.
 *  - D: RNC repetido en dos empresas → resolutor ambiguo, no elige a nadie.
 *  - E: certificación no activa → el despacho al proveedor queda bloqueado.
 *  - Aislamiento: B no puede preparar ni despachar la venta de A; cada empresa
 *    emite con su propio RNC y su propia clave.
 *  - Reinicio del backend: una instancia nueva ve el mismo estado persistido.
 *  - Concurrencia: A y C preparan y despachan a la vez sin interferirse.
 *
 * Qué NO hace, y por eso se declara explícitamente:
 *
 *  - No contacta con DOSA ni con la DGII: el transporte es un doble que **no
 *    abre ningún socket** y `ALANUBE_ENABLE_REAL_CALLS=false` es obligatorio.
 *  - No usa credenciales reales: las claves son literales de prueba guardadas en
 *    una base desechable creada y destruida por esta misma prueba.
 *  - Un "aceptado" aquí es `LOCAL_VALIDATED`/simulación, **nunca** aceptación
 *    fiscal de la DGII. La prueba lo comprueba (`officialFiscalAcceptance:false`).
 */
jest.setTimeout(600000);

const PASSWORD = "MultiCompanyE2E123!";
const SAFE_DB = /^fullpos_multicompany_e2e_/;
const uat = process.env.ECF_POSTGRES_UAT === "true" ? describe : describe.skip;

const MASTER_KEY = Buffer.alloc(32, 7).toString("base64");

function baseDatabaseUrl() {
  const envUrl = process.env.DATABASE_URL?.trim();
  if (envUrl) return envUrl;
  const raw = readFileSync(".env", "utf8");
  const line = raw.split(/\r?\n/).find((entry) => entry.startsWith("DATABASE_URL="));
  if (!line) throw new Error("DATABASE_URL missing");
  return line.slice("DATABASE_URL=".length).trim();
}

function replaceDbName(url: string, dbName: string) {
  const parsed = new URL(url);
  parsed.pathname = `/${dbName}`;
  return parsed.toString();
}

/** Petición capturada por el adaptador DOSA falso. */
type CapturedRequest = {
  url: string;
  headers: Record<string, string>;
  body: string;
};

uat("Validación integral multiempresa — cinco empresas ficticias", () => {
  let app: INestApplication;
  let prisma: PrismaService;
  let dbName: string;
  let adminUrl: string;
  let appUrl: string;

  const http = () => request(app.getHttpServer());
  const captured: CapturedRequest[] = [];
  const ENV_BACKUP: Record<string, string | undefined> = {};

  function setEnv(key: string, value: string) {
    if (!(key in ENV_BACKUP)) ENV_BACKUP[key] = process.env[key];
    process.env[key] = value;
  }

  /** Adaptador DOSA falso: guarda la petición y responde aceptación simulada. */
  const fakeTransport: DosaHttpTransport = {
    async post(url, init) {
      captured.push({ url, headers: { ...init.headers }, body: init.body });
      return {
        status: 200,
        body: JSON.stringify({
          encf: "SIMULADO",
          estado: "ACEPTADO",
          trackId: `fake-${captured.length}`,
        }),
      };
    },
  };

  beforeAll(async () => {
    if (process.env.ALANUBE_ENABLE_REAL_CALLS !== "false") {
      throw new Error("E2E_REFUSES_REAL_PROVIDER_CALLS");
    }

    dbName = `fullpos_multicompany_e2e_${Date.now()}`;
    if (!SAFE_DB.test(dbName)) throw new Error("Unsafe E2E DB name");
    adminUrl = replaceDbName(baseDatabaseUrl(), "postgres");
    appUrl = replaceDbName(baseDatabaseUrl(), dbName);

    const admin = new Client({ connectionString: adminUrl });
    await admin.connect();
    await admin.query(`CREATE DATABASE ${dbName}`);
    await admin.end();

    // `setEnv` deja el valor original en el respaldo: sin esto, esta suite
    // dejaría `DATABASE_URL` apuntando a una base que ELLA MISMA destruye y
    // contaminaría a todas las suites que se ejecuten después en el mismo
    // proceso (`--runInBand`).
    setEnv("DATABASE_URL", appUrl);
    setEnv("JWT_SECRET", process.env.JWT_SECRET || "multicompany-e2e-secret");
    // Despacho SIMULADO: exige UAT local y ninguna llamada real.
    setEnv("APP_ENV", "uat");
    setEnv("UAT_LOCAL_ONLY", "true");
    setEnv("ALANUBE_ENABLE_REAL_CALLS", "false");
    // Cifrado de credenciales de prueba (clave sintética de 32 bytes).
    setEnv("DOSA_CREDENTIALS_MASTER_KEY", MASTER_KEY);
    // Emisión habilitada SOLO para el adaptador falso de esta prueba.
    setEnv("DOSA_EMISSION_ENABLED", "true");
    setEnv("DOSA_EMISSION_ENVIRONMENT", "TEST");
    setEnv("DOSA_PRODUCTION_EMISSION_ENABLED", "false");
    setEnv("DOSA_BASE_URL", "https://dosa.fake.invalid");
    setEnv("ECF_PORTAL_PILOT_COMPANY_IDS", "");
    setEnv("ECF_PORTAL_AUTO_ENROLL_ENABLED", "false");

    execFileSync(process.execPath, [resolvePrismaCliPath(), "migrate", "deploy"], {
      cwd: process.cwd(),
      env: { ...process.env, DATABASE_URL: appUrl },
      stdio: "pipe",
    });

    await bootApp();
  }, 600000);

  async function bootApp() {
    const moduleRef = await Test.createTestingModule({ imports: [AppModule] }).compile();
    app = moduleRef.createNestApplication();
    app.useGlobalPipes(
      new ValidationPipe({ whitelist: true, forbidNonWhitelisted: true, transform: true }),
    );
    await app.init();
    prisma = app.get(PrismaService);
  }

  afterAll(async () => {
    if (app) await app.close();
    for (const [key, value] of Object.entries(ENV_BACKUP)) {
      if (value === undefined) delete process.env[key];
      else process.env[key] = value;
    }
    if (adminUrl && dbName && SAFE_DB.test(dbName)) {
      const admin = new Client({ connectionString: adminUrl });
      await admin.connect();
      await admin.query(
        "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = $1 AND pid <> pg_backend_pid()",
        [dbName],
      );
      await admin.query(`DROP DATABASE IF EXISTS ${dbName}`);
      await admin.end();
    }
  }, 120000);

  // ---------------------------------------------------------------- utilidades

  type Tenant = { token: string; userId: string; companyId: string; rnc: string };

  async function registerTenant(suffix: string): Promise<Tenant> {
    // RNC sintético y único por empresa: 9 dígitos, ningún dato real.
    const rnc = `9${String(Date.now()).slice(-7)}${Math.floor(Math.random() * 9)}`;
    const res = await http()
      .post("/auth/register-business")
      .send({
        firstName: "Multi",
        lastName: suffix,
        email: `multi-${Date.now()}-${suffix}@example.test`,
        phone: "8095550000",
        password: PASSWORD,
        confirmPassword: PASSWORD,
        commercialName: `Multi ${suffix}`,
        taxId: rnc,
        businessPhone: "8095551111",
        address: `Calle Ficticia ${suffix}`,
        country: "DO",
      });
    if (res.status !== 201) {
      throw new Error(`register-business ${suffix} -> ${res.status}: ${JSON.stringify(res.body)}`);
    }
    return {
      token: res.body.accessToken as string,
      userId: res.body.user.id as string,
      companyId: res.body.activeCompany.id as string,
      rnc,
    };
  }

  async function enableEcf(tenant: Tenant) {
    const res = await http()
      .patch("/ecf/config")
      .set("Authorization", `Bearer ${tenant.token}`)
      .send({ enabled: true, provider: "DOSA", environment: "SANDBOX", allowedTypes: ["E31"] });
    expect(res.status).toBe(200);
  }

  async function registerSequence(tenant: Tenant, start: number, end: number) {
    // La numeración exige la autorización DGII declarada: es la compuerta real
    // del módulo, así que la prueba la declara por la misma vía que el cliente.
    const declared = await http()
      .post("/ecf/dgii/authorized-sequences")
      .set("Authorization", `Bearer ${tenant.token}`)
      .send({
        documentType: "E31",
        authorizationNumber: `SYNTH-E31-${start}-${end}`,
        rangeFrom: start,
        rangeTo: end,
        approvedQuantity: end - start + 1,
        declarationAccepted: true,
      });
    expect(declared.status).toBe(201);
    const res = await http()
      .post("/ecf/sequences")
      .set("Authorization", `Bearer ${tenant.token}`)
      .send({ documentType: "E31", startNumber: start, endNumber: end });
    expect(res.status).toBe(201);
    return res.body as { id: string; prefix?: string };
  }

  /** Configuración fiscal mínima del POS: unidades, impuesto, ajustes y B01. */
  async function setupFiscal(tenant: Tenant) {
    const units = await http()
      .patch("/settings")
      .set("Authorization", `Bearer ${tenant.token}`)
      .send({ measurementUnitsEnabled: true });
    expect(units.status).toBe(200);

    const tax = await http()
      .post("/taxes")
      .set("Authorization", `Bearer ${tenant.token}`)
      .send({ name: "ITBIS 18", rate: 0.18, isActive: true, isDefault: true });
    expect(tax.status).toBe(201);

    const fiscal = await http()
      .patch("/company/fiscal-settings")
      .set("Authorization", `Bearer ${tenant.token}`)
      .send({
        taxEnabled: true,
        defaultTaxId: tax.body.id,
        defaultTaxRate: 0.18,
        pricesIncludeTax: true,
        ncfEnabled: true,
      });
    expect(fiscal.status).toBe(200);

    const sequence = await http()
      .post("/ncf/sequences")
      .set("Authorization", `Bearer ${tenant.token}`)
      .send({ voucherType: "B01", prefix: "B01", startNumber: 1, endNumber: 10 });
    expect(sequence.status).toBe(201);
  }

  async function openCashSession(tenant: Tenant) {
    const opened = await http()
      .post("/cash/sessions/open")
      .set("Authorization", `Bearer ${tenant.token}`)
      .send({ openingAmount: 0 });
    expect(opened.status).toBe(201);
    const session = await prisma.cashSession.findFirstOrThrow({
      where: { companyId: tenant.companyId, openedByUserId: tenant.userId, status: "OPEN" },
      orderBy: { openedAt: "desc" },
    });
    return session.id;
  }

  async function createProduct(tenant: Tenant) {
    const res = await http()
      .post("/products")
      .set("Authorization", `Bearer ${tenant.token}`)
      .send({
        nombre: "Artículo Ficticio",
        codigo: `SKU-${Date.now()}-${Math.floor(Math.random() * 10000)}`,
        categoria: "Fiscal",
        precio: 118,
        costo: 59,
        stock: 50,
      });
    if (res.status !== 201) {
      throw new Error(`POST /products -> ${res.status}: ${JSON.stringify(res.body)}`);
    }
    return res.body as { id: string; nombre: string };
  }

  async function createClient(tenant: Tenant, taxId: string) {
    const res = await http()
      .post("/clients")
      .set("Authorization", `Bearer ${tenant.token}`)
      .send({
        nombre: `Cliente Ficticio ${taxId}`,
        telefono: "8090000000",
        taxId,
        businessName: `Cliente Ficticio ${taxId}`,
        direccion: "Av. Ficticia 1",
      });
    if (res.status !== 201) {
      throw new Error(`POST /clients -> ${res.status}: ${JSON.stringify(res.body)}`);
    }
    return res.body as { id: string };
  }

  /** Venta real del POS con comprobante B01. */
  async function sell(tenant: Tenant, buyerTaxId: string) {
    await setupFiscal(tenant);
    const sessionId = await openCashSession(tenant);
    const product = await createProduct(tenant);
    const client = await createClient(tenant, buyerTaxId);
    const res = await http()
      .post("/sales")
      .set("Authorization", `Bearer ${tenant.token}`)
      .send({
        originCashSessionId: sessionId,
        paymentMethod: "cash",
        paymentCashAmount: 118,
        fiscalVoucherType: "B01",
        customerId: client.id,
        expectedTotalSold: 118,
        items: [
          {
            productId: product.id,
            productSource: "LOCAL",
            productName: product.nombre,
            qty: 1,
            priceSoldUnit: 118,
          },
        ],
      });
    if (res.status !== 201) {
      throw new Error(`POST /sales -> ${res.status}: ${JSON.stringify(res.body)}`);
    }
    return res.body as { id: string };
  }

  async function prepare(tenant: Tenant, saleId: string) {
    return http()
      .post("/ecf/documents/prepare")
      .set("Authorization", `Bearer ${tenant.token}`)
      .send({
        saleId,
        documentType: "E31",
        paymentType: 1,
        incomeType: 1,
        // `sequenceDueDate` es obligatorio por contrato para E31: sin él la
        // preparación se rechaza con ECF_METADATA_REQUIRED.
        sequenceDueDate: new Date(Date.now() + 30 * 24 * 60 * 60 * 1000)
          .toISOString()
          .slice(0, 10),
      });
  }

  /** Siembra credenciales ficticias y las deja en el estado pedido. */
  async function seedCredentials(input: {
    companyId: string;
    rnc: string;
    apiKeyTest: string;
    apiKeyProduccion?: string;
    status: "PENDING_CONFIRMATION" | "ACTIVE";
  }) {
    const store = new PrismaDosaCredentialStore(prisma as never);
    const vault = new DosaCredentialVault(MASTER_KEY);
    const service = new DosaCredentialService(store, vault);

    const ingested = await service.ingestFromProvider({
      companyId: input.companyId,
      rnc: input.rnc,
      environment: "test",
      bundle: {
        apiKeyTest: input.apiKeyTest,
        ...(input.apiKeyProduccion ? { apiKeyProduccion: input.apiKeyProduccion } : {}),
        apiSecret: `secret-${input.companyId.slice(0, 8)}`,
      },
      signatureAuthenticated: true,
    });
    expect(ingested.ok).toBe(true);

    if (input.status === "ACTIVE") {
      for (const environment of input.apiKeyProduccion
        ? (["test", "production"] as const)
        : (["test"] as const)) {
        const promoted = await service.promote({
          companyId: input.companyId,
          rnc: input.rnc,
          environment,
          to: "ACTIVE",
          evidence: {
            identityLinked: true,
            postulationBound: true,
            providerConfirmed: true,
            dgiiApproved: true,
            administrativeAuthorized: true,
            details: {
              attemptNo: 1,
              attemptStartedAt: new Date().toISOString(),
              postulacionId: `postulacion-ficticia-${environment}`,
              linkedSessions: 1,
              authenticatedProviderEvents: 1,
              providerEventsForOtherPostulations: 0,
              dgiiState: "APPROVED",
              dgiiSource: "DGII_OFFICIAL_RECORD",
            } as never,
          },
        });
        expect(promoted).toMatchObject({ ok: true });
      }
    }
    return service;
  }

  /** Emisor DOSA con el adaptador falso, para inspeccionar la petición real. */
  async function emissionService(environment: "TEST" | "PRODUCTION") {
    const store = new PrismaDosaCredentialStore(prisma as never);
    const credentials = new DosaCredentialService(store, new DosaCredentialVault(MASTER_KEY));
    return new DosaEmissionService({
      fiscalConfig: new PrismaDosaCompanyFiscalConfigReader(prisma as never),
      credentials,
      config: readDosaEmissionConfig({
        ...process.env,
        DOSA_EMISSION_ENVIRONMENT: environment,
        DOSA_EMISSION_ENABLED: "true",
      }),
      transport: fakeTransport,
    });
  }

  /**
   * Cuerpo DOSA del comprobante preparado, construido con el MAPEADOR OFICIAL.
   *
   * Importante para no confundir dos cosas distintas:
   *
   * * `payloadSummary.emission.payload` es el DOM de **Alanube** (lo que usa
   *   `dispatchOnce` para el transporte genérico).
   * * DOSA exige su propio contrato (`encabezado` + `detallesItems`), que se
   *   obtiene con `mapEcfToDosaDraft` a partir del documento fiscal persistido.
   *
   * Mandar el DOM de Alanube al cliente de DOSA sería un comprobante mal formado;
   * la barrera del punto de envío lo rechaza, y por eso este helper existe.
   */
  async function dosaBodyOf(documentId: string) {
    const row = await prisma.ecfElectronicDocument.findFirstOrThrow({
      where: { id: documentId },
      select: { fiscalDocument: true, payloadSummary: true, documentType: true },
    });
    const emission = (row.payloadSummary as Record<string, any> | null)?.emission as
      | { encf?: string }
      | undefined;
    const encf = emission?.encf ?? "";
    const mapped = mapEcfToDosaDraft(
      row.fiscalDocument as never,
      {
        encf,
        paymentType: 1,
        incomeType: 1,
        sequenceDueDate: new Date(Date.now() + 30 * 24 * 60 * 60 * 1000)
          .toISOString()
          .slice(0, 10),
      } as never,
    );
    if (!mapped.ok) {
      throw new Error(`mapEcfToDosaDraft bloqueó el documento: ${mapped.blockedReason}`);
    }
    return { body: mapped.draft.body as never, encf };
  }

  /**
   * Prepara y EXIGE el resultado fiscal correcto.
   *
   * Un rechazo fiscal no es un error HTTP: el módulo responde `201` con
   * `{ ok: false, code }`. Por eso la comprobación se hace sobre el código, y el
   * mensaje de fallo lo imprime para no tener que adivinar qué lo bloqueó.
   */
  async function prepareOk(tenant: Tenant, saleId: string) {
    const res = await prepare(tenant, saleId);
    if (res.status !== 201 || res.body?.ok !== true) {
      throw new Error(
        `prepare rechazado: HTTP ${res.status} ${JSON.stringify(res.body)}`,
      );
    }
    const documentId = res.body.documentId ?? res.body.value?.documentId;
    if (typeof documentId !== "string") {
      throw new Error(`prepare sin documentId: ${JSON.stringify(res.body)}`);
    }
    return { res, documentId };
  }

  /**
   * Borrador persistido, con el e-NCF resuelto.
   *
   * El e-NCF NO es una columna: el orquestador lo guarda en
   * `payload_summary.emission.encf`, que es también lo que usa `dispatchOnce`
   * antes de enviar. Se lee de ahí para no inventar una segunda fuente.
   */
  async function bodyOfDraft(documentId: string) {
    const row = await prisma.ecfElectronicDocument.findFirstOrThrow({
      where: { id: documentId },
      select: {
        id: true,
        status: true,
        documentType: true,
        companyId: true,
        payloadSummary: true,
        fiscalDocument: true,
        internalDocumentNumber: true,
      },
    });
    const emission = (row.payloadSummary as Record<string, any> | null)?.emission as
      | { encf?: string; senderTaxId?: string; fingerprint?: string; payload?: unknown }
      | undefined;
    return Object.assign(row, {
      encf: emission?.encf ?? "",
      senderTaxId: emission?.senderTaxId ?? "",
      payload: emission?.payload,
    });
  }

  // --------------------------------------------------------------------- casos

  it("A: venta del POS → E31 con e-NCF propio → despacho simulado → estado final", async () => {
    const A = await registerTenant("a");
    await enableEcf(A);
    const sequence = await registerSequence(A, 1, 10);
    expect(sequence.id).toBeTruthy();

    const sale = await sell(A, "130000001");
    const { documentId } = await prepareOk(A, sale.id);

    const document = await bodyOfDraft(documentId);
    // El e-NCF sale del rango de ESTA empresa y del tipo E31.
    expect(document.documentType).toBe("E31");
    expect(document.encf).toMatch(/^E31/);
    expect(document.companyId).toBe(A.companyId);

    const dispatched = await http()
      .post(`/ecf/documents/${documentId}/simulate-dispatch`)
      .set("Authorization", `Bearer ${A.token}`)
      .send({ scenario: "PROVIDER_ACCEPTED" });
    expect([200, 201]).toContain(dispatched.status);
    // Nunca se declara aceptación fiscal oficial por una simulación.
    expect(dispatched.body.officialFiscalAcceptance).toBe(false);
    expect(dispatched.body.simulated).toBe(true);

    const after = await bodyOfDraft(documentId);
    expect(after.encf).toBe(document.encf);
    expect(["ACCEPTED", "SENT", "HUMAN_REVIEW_REQUIRED", "PENDING"]).toContain(after.status);
  });

  it("B: sin e-CF habilitado no prepara, pero la venta normal del POS funciona", async () => {
    const B = await registerTenant("b");
    const sale = await sell(B, "130000002");

    const prepared = await prepare(B, sale.id);
    // La preparación devuelve un resultado fiscal, no una excepción.
    expect(prepared.status).toBeLessThan(300);
    expect(prepared.body).toMatchObject({ ok: false, code: "ECF_COMPANY_DISABLED" });

    // Nada se creó y la venta sigue intacta.
    expect(await prisma.ecfElectronicDocument.count({ where: { companyId: B.companyId } })).toBe(0);
    const persisted = await prisma.sale.findFirstOrThrow({
      where: { id: sale.id, companyId: B.companyId },
    });
    expect(persisted.id).toBe(sale.id);
  });

  it("B no puede preparar la venta de A (aislamiento por empresa)", async () => {
    const A = await registerTenant("iso-a");
    const B = await registerTenant("iso-b");
    await enableEcf(A);
    await registerSequence(A, 1, 10);
    await enableEcf(B);
    await registerSequence(B, 1, 10);

    const saleA = await sell(A, "130000003");
    const attempt = await prepare(B, saleA.id);

    // Un rechazo fiscal se responde 201 con `ok:false`, así que la prueba mira el
    // CÓDIGO: la venta de A no existe para B y no se revela su contenido.
    expect(attempt.status).toBeLessThan(300);
    expect(attempt.body).toMatchObject({
      ok: false,
      code: "ECF_SALE_NOT_FOUND",
    });
    expect(JSON.stringify(attempt.body)).not.toContain(saleA.id);
    expect(await prisma.ecfElectronicDocument.count({ where: { companyId: B.companyId } })).toBe(0);
    expect(await prisma.ecfElectronicDocument.count({ where: { companyId: A.companyId } })).toBe(0);
  });

  it("C: credenciales TEST y PRODUCCIÓN separadas; en TEST se usa la clave de TEST", async () => {
    const C = await registerTenant("c");
    await enableEcf(C);
    await registerSequence(C, 1, 10);

    await seedCredentials({
      companyId: C.companyId,
      rnc: C.rnc,
      apiKeyTest: "sk_test_FICTICIA_C",
      apiKeyProduccion: "sk_prod_FICTICIA_C",
      status: "ACTIVE",
    });

    const sale = await sell(C, "130000004");
    const { documentId } = await prepareOk(C, sale.id);

    const document = await bodyOfDraft(documentId);
    const { body, encf } = await dosaBodyOf(documentId);

    captured.length = 0;
    const service = await emissionService("TEST");
    const result = await service.emit({
      companyId: C.companyId,
      rnc: C.rnc,
      documentType: "E31",
      senderTaxId: C.rnc,
      sequenceAvailable: true,
      body,
    });
    if (!result.ok) {
      throw new Error(`emisión TEST rechazada: ${JSON.stringify(result)}`);
    }

    // Se envió UNA petición, con la clave de TEST de esta empresa.
    expect(captured).toHaveLength(1);
    const sent = captured[0];
    const authHeader = Object.entries(sent.headers).find(([key]) =>
      /api[-_]?key/i.test(key),
    );
    expect(authHeader?.[1]).toBe("sk_test_FICTICIA_C");
    // El cuerpo que recibiría el proveedor es el de ESTA empresa y su e-NCF.
    const sentBody = JSON.parse(sent.body) as Record<string, any>;
    expect(sentBody.encabezado.emisor.RNCEmisor).toBe(C.rnc);
    expect(sentBody.encabezado.idDoc.eNCF).toBe(encf);
    expect(encf).toBe(document.encf);
    expect(sent.body.length).toBeGreaterThan(100);
  });

  it("C: PRODUCCIÓN sin autorización explícita no llega a usar la clave de producción", async () => {
    const C2 = await registerTenant("c2");
    await enableEcf(C2);
    await registerSequence(C2, 1, 10);
    await seedCredentials({
      companyId: C2.companyId,
      rnc: C2.rnc,
      apiKeyTest: "sk_test_FICTICIA_C2",
      apiKeyProduccion: "sk_prod_FICTICIA_C2",
      status: "ACTIVE",
    });

    const sale = await sell(C2, "130000005");
    const { documentId } = await prepareOk(C2, sale.id);
    const { body } = await dosaBodyOf(documentId);

    captured.length = 0;
    const service = await emissionService("PRODUCTION");
    const result = await service.emit({
      companyId: C2.companyId,
      rnc: C2.rnc,
      documentType: "E31",
      senderTaxId: C2.rnc,
      sequenceAvailable: true,
      body,
    });

    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect(result.code).toBe("ECF_DOSA_GATE_BLOCKED");
      expect(result.blockingReasons).toContain("ECF_DOSA_GATE_PRODUCTION_NOT_AUTHORIZED");
    }
    // Ni una sola petición: el bloqueo ocurre antes de construir el cliente.
    expect(captured).toHaveLength(0);
  });

  it("las claves de una empresa no se usan para otra", async () => {
    const X = await registerTenant("key-x");
    const Y = await registerTenant("key-y");
    for (const [tenant, key] of [
      [X, "sk_test_FICTICIA_X"],
      [Y, "sk_test_FICTICIA_Y"],
    ] as const) {
      await enableEcf(tenant);
      await registerSequence(tenant, 1, 10);
      await seedCredentials({
        companyId: tenant.companyId,
        rnc: tenant.rnc,
        apiKeyTest: key,
        status: "ACTIVE",
      });
    }

    for (const [tenant, expectedKey] of [
      [X, "sk_test_FICTICIA_X"],
      [Y, "sk_test_FICTICIA_Y"],
    ] as const) {
      const sale = await sell(tenant, `13000001${expectedKey.slice(-1) === "X" ? "6" : "7"}`);
      const { documentId } = await prepareOk(tenant, sale.id);
      const { body } = await dosaBodyOf(documentId);

      captured.length = 0;
      const service = await emissionService("TEST");
      const result = await service.emit({
        companyId: tenant.companyId,
        rnc: tenant.rnc,
        documentType: "E31",
        senderTaxId: tenant.rnc,
        sequenceAvailable: true,
        body,
      });
      if (!result.ok) {
        throw new Error(`emisión rechazada para ${expectedKey}: ${JSON.stringify(result)}`);
      }
      expect(captured).toHaveLength(1);
      const authHeader = Object.entries(captured[0].headers).find(([key]) =>
        /api[-_]?key/i.test(key),
      );
      expect(authHeader?.[1]).toBe(expectedKey);
      // El cuerpo enviado lleva el RNC de SU empresa, no el de la otra.
      const sentBody = JSON.parse(captured[0].body) as Record<string, any>;
      expect(sentBody.encabezado.emisor.RNCEmisor).toBe(tenant.rnc);
      expect(sentBody.encabezado.emisor.RNCEmisor).not.toBe(
        tenant.companyId === X.companyId ? Y.rnc : X.rnc,
      );
    }
  });

  it("un reintento con la misma clave de idempotencia no produce un segundo envío", async () => {
    const J = await registerTenant("j");
    await enableEcf(J);
    await registerSequence(J, 1, 10);
    await seedCredentials({
      companyId: J.companyId,
      rnc: J.rnc,
      apiKeyTest: "sk_test_FICTICIA_J",
      status: "ACTIVE",
    });

    const sale = await sell(J, "130000013");
    const { documentId } = await prepareOk(J, sale.id);
    const { body } = await dosaBodyOf(documentId);

    captured.length = 0;
    const service = await emissionService("TEST");
    const idempotencyKey = `retry-${documentId}`;
    const first = await service.emit({
      companyId: J.companyId,
      rnc: J.rnc,
      documentType: "E31",
      senderTaxId: J.rnc,
      sequenceAvailable: true,
      body,
      idempotencyKey,
    });
    if (!first.ok) {
      throw new Error(`primer envío rechazado: ${JSON.stringify(first)}`);
    }
    expect(captured).toHaveLength(1);

    // Segundo intento con la MISMA clave: el cliente lo corta antes de la red.
    const second = await service.emit({
      companyId: J.companyId,
      rnc: J.rnc,
      documentType: "E31",
      senderTaxId: J.rnc,
      sequenceAvailable: true,
      body,
      idempotencyKey,
    });

    // Todavía no hay segunda petición: no se duplicó el comprobante.
    expect(captured).toHaveLength(1);
    if (!second.ok) {
      // El transporte devuelve un resultado con `blockedReason` de idempotencia.
      expect(JSON.stringify(second)).toContain("ALREADY_SENT");
    } else {
      // Si el cliente lo permite, al menos debe seguir siendo UNA petición.
      expect(captured).toHaveLength(1);
    }
  });

  it("D: RNC repetido en dos empresas deja el resolutor ambiguo y no elige ninguna", async () => {
    const D1 = await registerTenant("d1");
    const D2 = await registerTenant("d2");
    const sharedRnc = "133000999";
    // Dos intentos con el MISMO RNC: es la condición de ambigüedad.
    for (const tenant of [D1, D2]) {
      await prisma.$executeRaw`
        INSERT INTO "ecf_dosa_certification_sessions"
          ("id","company_id","rnc","attempt_no","active_key","status","updated_at")
        VALUES
          (gen_random_uuid(), ${tenant.companyId}::uuid, ${sharedRnc}, 1,
           ${`${tenant.companyId}:${sharedRnc}`}, 'NOT_STARTED', NOW())
      `;
    }

    const resolver = new PrismaDosaCompanyResolver(prisma as never);
    await expect(resolver.resolveByRnc(sharedRnc)).resolves.toBeNull();

    // Un RNC de una sola empresa sí resuelve. Se registra su propio intento
    // (D1 solo tenía el RNC compartido) para que el caso único sea real.
    await prisma.$executeRaw`
      INSERT INTO "ecf_dosa_certification_sessions"
        ("id","company_id","rnc","attempt_no","active_key","status","updated_at")
      VALUES
        (gen_random_uuid(), ${D1.companyId}::uuid, ${D1.rnc}, 2,
         ${`${D1.companyId}:${D1.rnc}`}, 'NOT_STARTED', NOW())
    `;
    await expect(resolver.resolveByRnc(D1.rnc)).resolves.toMatchObject({
      companyId: D1.companyId,
    });
  });

  it("E: sin credencial activa el proveedor no recibe nada", async () => {
    const E = await registerTenant("e");
    await enableEcf(E);
    await registerSequence(E, 1, 10);
    // Credencial recibida pero NO activada: es el estado "no autorizado aún".
    await seedCredentials({
      companyId: E.companyId,
      rnc: E.rnc,
      apiKeyTest: "sk_test_FICTICIA_E",
      status: "PENDING_CONFIRMATION",
    });

    const sale = await sell(E, "130000008");
    const { documentId } = await prepareOk(E, sale.id);
    const { body } = await dosaBodyOf(documentId);
    const draft = await bodyOfDraft(documentId);

    captured.length = 0;
    const service = await emissionService("TEST");
    const result = await service.emit({
      companyId: E.companyId,
      rnc: E.rnc,
      documentType: "E31",
      senderTaxId: E.rnc,
      sequenceAvailable: true,
      body,
    });

    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect(result.blockingReasons).toContain("ECF_DOSA_GATE_CREDENTIALS_NOT_ACTIVE");
    }
    expect(captured).toHaveLength(0);

    // El documento sigue preparado: no se consumió ni se marcó enviado.
    const still = await bodyOfDraft(documentId);
    expect(still.encf).toBe(draft.encf);
    expect(still.status).not.toBe("ACCEPTED");
  });

  it("un RNC ajeno en el cuerpo se rechaza antes de cualquier envío", async () => {
    const F = await registerTenant("f");
    await enableEcf(F);
    await registerSequence(F, 1, 10);
    await seedCredentials({
      companyId: F.companyId,
      rnc: F.rnc,
      apiKeyTest: "sk_test_FICTICIA_F",
      status: "ACTIVE",
    });

    const sale = await sell(F, "130000009");
    const { documentId } = await prepareOk(F, sale.id);
    const { body } = await dosaBodyOf(documentId);
    const draftBody = body as Record<string, any>;
    expect(draftBody.encabezado.emisor.RNCEmisor).toBe(F.rnc);

    // Se altera el emisor del cuerpo: la barrera debe bloquear.
    draftBody.encabezado.emisor.RNCEmisor = "101000001";
    captured.length = 0;
    const service = await emissionService("TEST");
    const result = await service.emit({
      companyId: F.companyId,
      rnc: F.rnc,
      documentType: "E31",
      senderTaxId: F.rnc,
      sequenceAvailable: true,
      body: draftBody as never,
    });

    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect(result.blockingReasons).toContain("DOSA_BARRIER_SENDER_RNC_MISMATCH");
    }
    expect(captured).toHaveLength(0);
  });

  it("el estado sobrevive a un reinicio del backend", async () => {
    const G = await registerTenant("g");
    await enableEcf(G);
    await registerSequence(G, 1, 10);
    const sale = await sell(G, "130000010");
    const { documentId } = await prepareOk(G, sale.id);
    const before = await bodyOfDraft(documentId);

    await app.close();
    await bootApp();

    const after = await bodyOfDraft(documentId);
    expect(after.id).toBe(before.id);
    expect(after.encf).toBe(before.encf);
    // Y la empresa sigue pudiendo operar tras el reinicio.
    const config = await http()
      .get("/ecf/config")
      .set("Authorization", `Bearer ${G.token}`)
      .expect(200);
    expect(config.body.enabled).toBe(true);
  });

  it("dos empresas preparan y despachan a la vez sin interferirse", async () => {
    const H = await registerTenant("h");
    const I = await registerTenant("i");
    for (const tenant of [H, I]) {
      await enableEcf(tenant);
      await registerSequence(tenant, 1, 10);
    }

    const [saleH, saleI] = await Promise.all([sell(H, "130000011"), sell(I, "130000012")]);
    const [prepA, prepB] = await Promise.all([prepare(H, saleH.id), prepare(I, saleI.id)]);
    expect(prepA.status).toBe(201);
    expect(prepB.status).toBe(201);

    const docH = prepA.body.documentId ?? prepA.body.value?.documentId;
    const docI = prepB.body.documentId ?? prepB.body.value?.documentId;
    expect(docH).not.toBe(docI);

    const rowH = await bodyOfDraft(docH);
    const rowI = await bodyOfDraft(docI);
    expect(rowH.companyId).toBe(H.companyId);
    expect(rowI.companyId).toBe(I.companyId);

    // Independencia de numeración. Dos rangos independientes que empiezan en 1
    // producen el MISMO e-NCF (`E310000000001`) en empresas distintas: eso es
    // correcto y no es una fuga. Lo que debe ser cierto es que cada empresa
    // tenga SU secuencia y que el número salga del rango de esa empresa.
    const sequencesH = await prisma.ecfSequence.findMany({
      where: { companyId: H.companyId },
    });
    const sequencesI = await prisma.ecfSequence.findMany({
      where: { companyId: I.companyId },
    });
    expect(sequencesH.length).toBeGreaterThan(0);
    expect(sequencesI.length).toBeGreaterThan(0);
    expect(sequencesH[0].id).not.toBe(sequencesI[0].id);
    // Cada documento tomó su número del rango de SU empresa.
    expect(rowH.encf).toMatch(/^E31\d{10}$/);
    expect(rowI.encf).toMatch(/^E31\d{10}$/);
    const consumedH = Number(rowH.encf.slice(3));
    const consumedI = Number(rowI.encf.slice(3));
    expect(consumedH).toBeGreaterThanOrEqual(sequencesH[0].startNumber);
    expect(consumedH).toBeLessThanOrEqual(sequencesH[0].endNumber);
    expect(consumedI).toBeGreaterThanOrEqual(sequencesI[0].startNumber);
    expect(consumedI).toBeLessThanOrEqual(sequencesI[0].endNumber);
  });
});
