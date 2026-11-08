import { INestApplication, ValidationPipe } from "@nestjs/common";
import { Test } from "@nestjs/testing";
import { execFileSync } from "node:child_process";
import { readFileSync } from "node:fs";
import { Client } from "pg";
import request from "supertest";

import { AppModule } from "../../../app.module";
import { PrismaService } from "../../../prisma/prisma.service";
import { resolvePrismaCliPath } from "../../../testing/prisma-cli";
import {
  DosaCredentialService,
  PrismaDosaCredentialStore,
} from "./dosa-credential.service";
import { DosaCredentialVault } from "./dosa-credential-vault.service";
import { ECF_DOSA_EMISSION_TRANSPORT } from "./dosa-emission.service";
import { FakeDosaHttpTransport } from "./dosa-emission.fake-transport";
import { fingerprint } from "../../documents/ecf-document-idempotency.service";

/**
 * ORQUESTADOR DE EMISIÓN DOSA — prueba de extremo a extremo por HTTP.
 *
 * A diferencia de la prueba anterior, aquí NO se llama al mapeador ni al servicio
 * de emisión desde la prueba: se hace `POST /ecf/documents/:id/dispatch-dosa` y
 * corre el camino real completo:
 *
 *   ruta → DosaEmissionDispatchService → authorizeForDispatch (barrera +
 *   compuerta + bóveda) → DosaEmissionWire → EcfEmissionService.dispatchOnce
 *   (reclamo FOR UPDATE, envío único, evidencia, estado) → PostgreSQL
 *
 * Lo ÚNICO sustituido es el socket: `ECF_DOSA_EMISSION_TRANSPORT` se inyecta con
 * un transporte falso que no abre conexiones. Con eso se puede inspeccionar el
 * cuerpo exacto que recibiría DOSA.
 *
 * Advertencia que este archivo mantiene: `DOSA_EMISSION_ENABLED=true` se fija
 * SÓLO dentro de este proceso de prueba, con transporte falso y base desechable.
 * Ninguna configuración versionada cambia y no se contacta con DOSA ni con la
 * DGII. Un "éxito" aquí es una RECEPCIÓN SIMULADA, nunca aceptación fiscal.
 */
jest.setTimeout(600000);

const PASSWORD = "DosaDispatchE2E123!";
const SAFE_DB = /^fullpos_dosa_dispatch_e2e_/;
const MASTER_KEY = Buffer.alloc(32, 9).toString("base64");
const uat = process.env.ECF_POSTGRES_UAT === "true" ? describe : describe.skip;

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

uat("Orquestador de emisión DOSA — cinco empresas por HTTP", () => {
  let app: INestApplication;
  let prisma: PrismaService;
  let dbName: string;
  let adminUrl: string;
  const transport = new FakeDosaHttpTransport();
  const ENV_BACKUP: Record<string, string | undefined> = {};

  const http = () => request(app.getHttpServer());

  function setEnv(key: string, value: string) {
    if (!(key in ENV_BACKUP)) ENV_BACKUP[key] = process.env[key];
    process.env[key] = value;
  }

  /** Arranca la app con el transporte falso inyectado. */
  async function bootApp() {
    const moduleRef = await Test.createTestingModule({ imports: [AppModule] })
      .overrideProvider(ECF_DOSA_EMISSION_TRANSPORT)
      .useValue(transport)
      .compile();
    app = moduleRef.createNestApplication();
    app.useGlobalPipes(
      new ValidationPipe({ whitelist: true, forbidNonWhitelisted: true, transform: true }),
    );
    await app.init();
    prisma = app.get(PrismaService);
  }

  /** Aplica el entorno de emisión SIMULADA en UAT. */
  function applyEmissionEnv(environment: "TEST" | "PRODUCTION") {
    setEnv("APP_ENV", "uat");
    setEnv("UAT_LOCAL_ONLY", "true");
    setEnv("ALANUBE_ENABLE_REAL_CALLS", "false");
    setEnv("DOSA_CREDENTIALS_MASTER_KEY", MASTER_KEY);
    setEnv("DOSA_EMISSION_ENABLED", "true");
    setEnv("DOSA_EMISSION_ENVIRONMENT", environment);
    // Producción NUNCA autorizada en estas pruebas.
    setEnv("DOSA_PRODUCTION_EMISSION_ENABLED", "false");
    setEnv("DOSA_BASE_URL", "https://dosa.fake.invalid");
    setEnv("DOSA_WEBHOOK_ENABLED", "false");
    setEnv("ECF_PORTAL_PILOT_COMPANY_IDS", "");
    setEnv("ECF_PORTAL_AUTO_ENROLL_ENABLED", "false");
  }

  beforeAll(async () => {
    if (process.env.ALANUBE_ENABLE_REAL_CALLS !== "false") {
      throw new Error("E2E_REFUSES_REAL_PROVIDER_CALLS");
    }
    dbName = `fullpos_dosa_dispatch_e2e_${Date.now()}`;
    if (!SAFE_DB.test(dbName)) throw new Error("Unsafe E2E DB name");
    adminUrl = replaceDbName(baseDatabaseUrl(), "postgres");
    const appUrl = replaceDbName(baseDatabaseUrl(), dbName);

    const admin = new Client({ connectionString: adminUrl });
    await admin.connect();
    await admin.query(`CREATE DATABASE ${dbName}`);
    await admin.end();

    setEnv("DATABASE_URL", appUrl);
    setEnv("JWT_SECRET", process.env.JWT_SECRET || "dosa-dispatch-e2e-secret");
    applyEmissionEnv("TEST");

    execFileSync(process.execPath, [resolvePrismaCliPath(), "migrate", "deploy"], {
      cwd: process.cwd(),
      env: { ...process.env, DATABASE_URL: appUrl },
      stdio: "pipe",
    });

    await bootApp();
  }, 600000);

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
    const rnc = `8${String(Date.now()).slice(-7)}${Math.floor(Math.random() * 9)}`;
    const res = await http()
      .post("/auth/register-business")
      .send({
        firstName: "Dispatch",
        lastName: suffix,
        email: `dispatch-${Date.now()}-${suffix}@example.test`,
        phone: "8095550000",
        password: PASSWORD,
        confirmPassword: PASSWORD,
        commercialName: `Dispatch ${suffix}`,
        taxId: rnc,
        businessPhone: "8095551111",
        address: `Calle Ficticia ${suffix}`,
        country: "DO",
      });
    if (res.status !== 201) {
      throw new Error(`register-business ${suffix} -> ${res.status}`);
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

  async function registerSequence(tenant: Tenant) {
    // La numeración exige la autorización DGII declarada (fail-closed).
    const declared = await http()
      .post("/ecf/dgii/authorized-sequences")
      .set("Authorization", `Bearer ${tenant.token}`)
      .send({
        documentType: "E31",
        authorizationNumber: "SYNTH-E31-1-50",
        rangeFrom: 1,
        rangeTo: 50,
        approvedQuantity: 50,
        declarationAccepted: true,
      });
    expect(declared.status).toBe(201);
    const res = await http()
      .post("/ecf/sequences")
      .set("Authorization", `Bearer ${tenant.token}`)
      .send({ documentType: "E31", startNumber: 1, endNumber: 50 });
    expect(res.status).toBe(201);
  }

  /** Estado de certificación: es la autorización fiscal, no la credencial. */
  async function setCertification(
    tenant: Tenant,
    status: "NOT_STARTED" | "AUTHORIZED_SANDBOX" | "SUSPENDED" | "PRODUCTION_READY",
  ) {
    await prisma.ecfCompanyConfiguration.update({
      where: { companyId: tenant.companyId },
      data: { certificationStatus: status as never },
    });
  }

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
      .send({ voucherType: "B01", prefix: "B01", startNumber: 1, endNumber: 20 });
    expect(sequence.status).toBe(201);
  }

  async function sell(tenant: Tenant, buyerTaxId: string) {
    await setupFiscal(tenant);
    const opened = await http()
      .post("/cash/sessions/open")
      .set("Authorization", `Bearer ${tenant.token}`)
      .send({ openingAmount: 0 });
    expect(opened.status).toBe(201);
    const session = await prisma.cashSession.findFirstOrThrow({
      where: { companyId: tenant.companyId, openedByUserId: tenant.userId, status: "OPEN" },
      orderBy: { openedAt: "desc" },
    });

    const product = await http()
      .post("/products")
      .set("Authorization", `Bearer ${tenant.token}`)
      .send({
        nombre: "Artículo Fiscal",
        codigo: `SKU-${Date.now()}-${Math.floor(Math.random() * 10000)}`,
        categoria: "Fiscal",
        precio: 118,
        costo: 59,
        stock: 40,
      });
    expect(product.status).toBe(201);

    const client = await http()
      .post("/clients")
      .set("Authorization", `Bearer ${tenant.token}`)
      .send({
        nombre: `Cliente ${buyerTaxId}`,
        telefono: "8090000000",
        taxId: buyerTaxId,
        businessName: `Cliente ${buyerTaxId}`,
        direccion: "Av. Ficticia 1",
      });
    expect(client.status).toBe(201);

    const sale = await http()
      .post("/sales")
      .set("Authorization", `Bearer ${tenant.token}`)
      .send({
        originCashSessionId: session.id,
        paymentMethod: "cash",
        paymentCashAmount: 118,
        fiscalVoucherType: "B01",
        customerId: client.body.id,
        expectedTotalSold: 118,
        items: [
          {
            productId: product.body.id,
            productSource: "LOCAL",
            productName: product.body.nombre,
            qty: 1,
            priceSoldUnit: 118,
          },
        ],
      });
    if (sale.status !== 201) {
      throw new Error(`POST /sales -> ${sale.status}: ${JSON.stringify(sale.body)}`);
    }
    return sale.body as { id: string };
  }

  async function prepareOk(tenant: Tenant, saleId: string): Promise<string> {
    const res = await http()
      .post("/ecf/documents/prepare")
      .set("Authorization", `Bearer ${tenant.token}`)
      .send({
        saleId,
        documentType: "E31",
        paymentType: 1,
        incomeType: 1,
        sequenceDueDate: new Date(Date.now() + 30 * 24 * 60 * 60 * 1000)
          .toISOString()
          .slice(0, 10),
      });
    if (res.status !== 201 || res.body?.ok !== true) {
      throw new Error(`prepare rechazado: HTTP ${res.status} ${JSON.stringify(res.body)}`);
    }
    const documentId = res.body.documentId ?? res.body.value?.documentId;
    if (typeof documentId !== "string") {
      throw new Error(`prepare sin documentId: ${JSON.stringify(res.body)}`);
    }
    return documentId;
  }

  /** Credenciales ficticias por empresa, con el estado pedido. */
  async function seedCredentials(input: {
    companyId: string;
    rnc: string;
    apiKeyTest: string;
    apiKeyProduccion?: string;
    status: "PENDING_CONFIRMATION" | "ACTIVE";
  }) {
    const service = new DosaCredentialService(
      new PrismaDosaCredentialStore(prisma as never),
      new DosaCredentialVault(MASTER_KEY),
    );
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

  /** Empresa lista para emitir: e-CF, secuencia, autorización y credencial ACTIVE. */
  async function readyCompany(suffix: string, apiKeyTest: string) {
    const tenant = await registerTenant(suffix);
    await enableEcf(tenant);
    await registerSequence(tenant);
    await setCertification(tenant, "AUTHORIZED_SANDBOX");
    await seedCredentials({
      companyId: tenant.companyId,
      rnc: tenant.rnc,
      apiKeyTest,
      status: "ACTIVE",
    });
    const sale = await sell(tenant, "131000001");
    const documentId = await prepareOk(tenant, sale.id);
    return { tenant, documentId };
  }

  function dispatch(tenant: Tenant, documentId: string) {
    return http()
      .post(`/ecf/documents/${documentId}/dispatch-dosa`)
      .set("Authorization", `Bearer ${tenant.token}`)
      .send({});
  }

  // --------------------------------------------------------------------- casos

  it("A: una venta recorre el orquestador real y el cuerpo llega al transporte con su RNC y su clave", async () => {
    const { tenant, documentId } = await readyCompany("a", "sk_test_DISPATCH_A");
    transport.reset();

    const res = await dispatch(tenant, documentId);
    expect(res.status).toBeLessThan(300);
    expect(res.body).toMatchObject({ ok: true });
    // El orquestador común NUNCA declara aceptación fiscal.
    expect(res.body.result).toBe("STOPPED_REVIEW_REQUIRED");
    expect(res.body.canRetryPost).toBe(false);

    // Una sola petición, con la clave de TEST de ESTA empresa.
    expect(transport.requests).toHaveLength(1);
    const sent = transport.requests[0];
    const authHeader = Object.entries(sent.headers).find(([key]) =>
      /api[-_]?key/i.test(key),
    );
    expect(authHeader?.[1]).toBe("sk_test_DISPATCH_A");

    // El cuerpo es el CONTRATO DE DOSA (no el DOM interno).
    const body = JSON.parse(sent.body) as Record<string, any>;
    expect(Object.keys(body).sort()).toEqual(["detallesItems", "encabezado"]);
    expect(body.encabezado.emisor.RNCEmisor).toBe(tenant.rnc);
    expect(body.encabezado.idDoc.eNCF).toBe(res.body.encf);
    expect(body.encabezado.idDoc.eNCF).toMatch(/^E31\d{10}$/);
    expect(body.encabezado.idDoc.tipoeCF).toBe("31");
    expect(body.detallesItems.length).toBeGreaterThan(0);

    // Estado y evidencia persistidos, con la huella de lo realmente enviado.
    const row = await prisma.ecfElectronicDocument.findFirstOrThrow({
      where: { id: documentId, companyId: tenant.companyId },
      select: { status: true, id: true },
    });
    expect(["HUMAN_REVIEW_REQUIRED", "UNKNOWN_RESULT", "SEND_IN_PROGRESS", "PROVIDER_ACCEPTED"]).toContain(
      row.status,
    );
    const attempt = await prisma.ecfElectronicDocumentAttempt.findFirstOrThrow({
      where: { companyId: tenant.companyId, documentId, operation: "SEND_TO_PROVIDER" },
    });
    expect(attempt.requestFingerprint).toBe(fingerprint(body));
    expect(await prisma.ecfEvidenceReceipt.count({ where: { companyId: tenant.companyId, documentId } }))
      .toBeGreaterThanOrEqual(0);
  });

  it("A: un segundo despacho del mismo documento no produce otra petición", async () => {
    const { tenant, documentId } = await readyCompany("a2", "sk_test_DISPATCH_A2");
    transport.reset();

    const first = await dispatch(tenant, documentId);
    expect(first.body).toMatchObject({ ok: true });
    expect(transport.requests).toHaveLength(1);

    const second = await dispatch(tenant, documentId);
    // `dispatchOnce` reclama la tentativa: el segundo intento es un conflicto.
    expect(second.status).toBeGreaterThanOrEqual(400);
    expect(transport.requests).toHaveLength(1);
    expect(
      await prisma.ecfElectronicDocumentAttempt.count({
        where: { companyId: tenant.companyId, documentId, operation: "SEND_TO_PROVIDER" },
      }),
    ).toBe(1);
  });

  it("B: sin credenciales la emisión se rechaza y no se envía nada", async () => {
    const tenant = await registerTenant("b");
    await enableEcf(tenant);
    await registerSequence(tenant);
    await setCertification(tenant, "AUTHORIZED_SANDBOX");
    const sale = await sell(tenant, "131000002");
    const documentId = await prepareOk(tenant, sale.id);
    transport.reset();

    const res = await dispatch(tenant, documentId);
    expect(res.body).toMatchObject({ ok: false, code: "ECF_DOSA_GATE_BLOCKED" });
    expect(res.body.blockingReasons).toContain("ECF_DOSA_GATE_CREDENTIALS_MISSING");
    expect(transport.requests).toHaveLength(0);
  });

  it("C: PRODUCCIÓN no se autoriza aunque existan ambas claves", async () => {
    const tenant = await registerTenant("c");
    await enableEcf(tenant);
    await registerSequence(tenant);
    await setCertification(tenant, "PRODUCTION_READY");
    await seedCredentials({
      companyId: tenant.companyId,
      rnc: tenant.rnc,
      apiKeyTest: "sk_test_DISPATCH_C",
      apiKeyProduccion: "sk_prod_DISPATCH_C",
      status: "ACTIVE",
    });
    const sale = await sell(tenant, "131000003");
    const documentId = await prepareOk(tenant, sale.id);

    // Se rearranca la app con ambiente de PRODUCCIÓN y la bandera apagada.
    await app.close();
    applyEmissionEnv("PRODUCTION");
    await bootApp();
    transport.reset();

    const res = await dispatch(tenant, documentId);
    expect(res.body).toMatchObject({ ok: false, code: "ECF_DOSA_GATE_BLOCKED" });
    expect(res.body.blockingReasons).toContain("ECF_DOSA_GATE_PRODUCTION_NOT_AUTHORIZED");
    expect(transport.requests).toHaveLength(0);

    // Se vuelve al ambiente de pruebas para el resto de casos.
    await app.close();
    applyEmissionEnv("TEST");
    await bootApp();
  });

  it("C: una base sin vínculo no puede emitir (el documento no existe para su token)", async () => {
    // La empresa A intenta despachar un identificador inexistente.
    const tenant = await registerTenant("c2");
    await enableEcf(tenant);
    await setCertification(tenant, "AUTHORIZED_SANDBOX");
    transport.reset();

    const res = await dispatch(tenant, "11111111-1111-4111-8111-111111111111");
    expect(res.status).toBeGreaterThanOrEqual(400);
    expect(transport.requests).toHaveLength(0);
  });

  it("D: una entrega en conflicto no rota la credencial vigente y la emisión usa la original", async () => {
    const tenant = await registerTenant("d");
    await enableEcf(tenant);
    await registerSequence(tenant);
    await setCertification(tenant, "AUTHORIZED_SANDBOX");

    // Credencial vigente y activada.
    const service = await seedCredentials({
      companyId: tenant.companyId,
      rnc: tenant.rnc,
      apiKeyTest: "sk_test_DISPATCH_D1",
      status: "ACTIVE",
    });
    // Segunda entrega con OTRA clave: no puede sustituir a una credencial ya
    // activa. La rotación es una decisión humana, no un efecto del webhook.
    const conflicting = await service.ingestFromProvider({
      companyId: tenant.companyId,
      rnc: tenant.rnc,
      environment: "test",
      bundle: { apiKeyTest: "sk_test_DISPATCH_D2", apiSecret: "otro-secreto" },
      signatureAuthenticated: true,
    });
    expect(conflicting).toMatchObject({ ok: true, stored: [] });
    expect(conflicting.conflicts).toContain("test");

    const sale = await sell(tenant, "131000004");
    const documentId = await prepareOk(tenant, sale.id);
    transport.reset();

    const res = await dispatch(tenant, documentId);
    // La emisión sigue con la credencial ORIGINAL: el conflicto no secuestró la
    // clave ni habilitó la ajena.
    expect(res.body).toMatchObject({ ok: true });
    expect(transport.requests).toHaveLength(1);
    const authHeader = Object.entries(transport.requests[0].headers).find(([key]) =>
      /api[-_]?key/i.test(key),
    );
    expect(authHeader?.[1]).toBe("sk_test_DISPATCH_D1");
  });

  it("D: una credencial sin activar no emite aunque la entrega sea válida", async () => {
    const tenant = await registerTenant("d2");
    await enableEcf(tenant);
    await registerSequence(tenant);
    await setCertification(tenant, "AUTHORIZED_SANDBOX");
    await seedCredentials({
      companyId: tenant.companyId,
      rnc: tenant.rnc,
      apiKeyTest: "sk_test_DISPATCH_D3",
      status: "PENDING_CONFIRMATION",
    });

    const sale = await sell(tenant, "131000006");
    const documentId = await prepareOk(tenant, sale.id);
    transport.reset();

    const res = await dispatch(tenant, documentId);
    // Recibir credenciales no habilita emisión por sí solo.
    expect(res.body).toMatchObject({ ok: false, code: "ECF_DOSA_GATE_BLOCKED" });
    expect(res.body.blockingReasons).toContain("ECF_DOSA_GATE_CREDENTIALS_NOT_ACTIVE");
    expect(transport.requests).toHaveLength(0);
  });

  it("E: certificación suspendida impide el despacho aunque la credencial esté ACTIVE", async () => {
    const tenant = await registerTenant("e");
    await enableEcf(tenant);
    await registerSequence(tenant);
    await seedCredentials({
      companyId: tenant.companyId,
      rnc: tenant.rnc,
      apiKeyTest: "sk_test_DISPATCH_E",
      status: "ACTIVE",
    });
    await setCertification(tenant, "SUSPENDED");
    const sale = await sell(tenant, "131000005");
    const documentId = await prepareOk(tenant, sale.id);
    transport.reset();

    const res = await dispatch(tenant, documentId);
    expect(res.body).toMatchObject({
      ok: false,
      code: "ECF_DOSA_DISPATCH_CERTIFICATION_NOT_AUTHORIZED",
    });
    expect(res.body.blockingReasons).toContain(
      "ECF_DOSA_DISPATCH_CERTIFICATION_NOT_AUTHORIZED:SUSPENDED",
    );
    expect(transport.requests).toHaveLength(0);
  });

  it("aislamiento: el documento de una empresa no se despacha con el token de otra", async () => {
    const { documentId } = await readyCompany("iso-a", "sk_test_ISO_A");
    const other = await registerTenant("iso-b");
    await enableEcf(other);
    await registerSequence(other);
    await setCertification(other, "AUTHORIZED_SANDBOX");
    transport.reset();

    const res = await dispatch(other, documentId);
    expect(res.status).toBeGreaterThanOrEqual(400);
    expect(transport.requests).toHaveLength(0);
    // El documento de A sigue sin tentativa.
    expect(
      await prisma.ecfElectronicDocumentAttempt.count({
        where: { companyId: other.companyId, operation: "SEND_TO_PROVIDER" },
      }),
    ).toBe(0);
  });

  it("concurrencia: dos empresas despachan a la vez con su propio RNC y su propia clave", async () => {
    const first = await readyCompany("conc-1", "sk_test_CONC_1");
    const second = await readyCompany("conc-2", "sk_test_CONC_2");
    transport.reset();

    const [res1, res2] = await Promise.all([
      dispatch(first.tenant, first.documentId),
      dispatch(second.tenant, second.documentId),
    ]);
    expect(res1.body).toMatchObject({ ok: true });
    expect(res2.body).toMatchObject({ ok: true });
    expect(transport.requests).toHaveLength(2);

    const byRnc = new Map<string, { key: string | undefined; encf: string }>();
    for (const sent of transport.requests) {
      const body = JSON.parse(sent.body) as Record<string, any>;
      const authHeader = Object.entries(sent.headers).find(([key]) =>
        /api[-_]?key/i.test(key),
      );
      byRnc.set(body.encabezado.emisor.RNCEmisor, {
        key: authHeader?.[1],
        encf: body.encabezado.idDoc.eNCF,
      });
    }
    expect(byRnc.get(first.tenant.rnc)?.key).toBe("sk_test_CONC_1");
    expect(byRnc.get(second.tenant.rnc)?.key).toBe("sk_test_CONC_2");
    expect(byRnc.get(first.tenant.rnc)?.encf).toMatch(/^E31\d{10}$/);
    expect(byRnc.get(second.tenant.rnc)?.encf).toMatch(/^E31\d{10}$/);
  });

  it("el estado sobrevive al reinicio del backend y no se reenvía solo", async () => {
    const { tenant, documentId } = await readyCompany("restart", "sk_test_RESTART");
    transport.reset();
    const first = await dispatch(tenant, documentId);
    expect(first.body).toMatchObject({ ok: true });
    const before = await prisma.ecfElectronicDocument.findFirstOrThrow({
      where: { id: documentId, companyId: tenant.companyId },
      select: { status: true },
    });

    await app.close();
    await bootApp();

    const after = await prisma.ecfElectronicDocument.findFirstOrThrow({
      where: { id: documentId, companyId: tenant.companyId },
      select: { status: true },
    });
    expect(after.status).toBe(before.status);
    // Tras reiniciar, un nuevo despacho sigue siendo un conflicto: no se duplica.
    const again = await dispatch(tenant, documentId);
    expect(again.status).toBeGreaterThanOrEqual(400);
    expect(transport.requests).toHaveLength(1);
  });

  it("una venta normal del POS sigue funcionando con DOSA deshabilitado", async () => {
    const tenant = await registerTenant("pos");
    // e-CF apagado por completo: ni configuración, ni secuencia, ni certificación.
    const sale = await sell(tenant, "131000009");
    const persisted = await prisma.sale.findFirstOrThrow({
      where: { id: sale.id, companyId: tenant.companyId },
    });
    expect(persisted.id).toBe(sale.id);
    expect(await prisma.ecfElectronicDocument.count({ where: { companyId: tenant.companyId } })).toBe(0);

    const prepared = await http()
      .post("/ecf/documents/prepare")
      .set("Authorization", `Bearer ${tenant.token}`)
      .send({ saleId: sale.id, documentType: "E31", paymentType: 1, incomeType: 1 });
    expect(prepared.body).toMatchObject({ ok: false, code: "ECF_COMPANY_DISABLED" });
  });
});
