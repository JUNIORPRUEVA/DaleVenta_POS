import { INestApplication, ValidationPipe } from "@nestjs/common";
import { Test } from "@nestjs/testing";
import { execFileSync } from "node:child_process";
import { readFileSync } from "node:fs";
import { createServer, type IncomingMessage, type Server, type ServerResponse } from "node:http";
import type { AddressInfo } from "node:net";
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
import { fingerprint } from "../../documents/ecf-document-idempotency.service";

/**
 * EMISIÓN DOSA MULTIEMPRESA CONTRA UN SERVIDOR HTTP REAL LOCAL.
 *
 * A diferencia de la prueba con transporte inyectado, aquí **no se sustituye el
 * transporte**: se usa el `fetch` real apuntando a un servidor `node:http` en
 * `127.0.0.1`. Se ejercita, por tanto:
 *
 *   serialización del cuerpo → cliente HTTP real → socket real → respuesta real
 *   → clasificación → persistencia de evidencia y estado
 *
 * El servidor local decide la respuesta según el **RNC del emisor** del cuerpo
 * recibido, así que cada empresa ficticia obtiene un escenario distinto sin que
 * la prueba toque el código de producción.
 *
 * Lo que esta prueba NO demuestra y no debe confundirse:
 *  - No hay llamada a DOSA: el destino es 127.0.0.1.
 *  - No hay aceptación fiscal: como mucho, una respuesta de proveedor
 *    correlacionada que termina en `HUMAN_REVIEW_REQUIRED`.
 *  - `DGII_ACCEPTED` no es alcanzable aquí; se comprueba explícitamente.
 */
jest.setTimeout(600000);

const PASSWORD = "DosaHttpE2E123!";
const SAFE_DB = /^fullpos_dosa_http_e2e_/;
const MASTER_KEY = Buffer.alloc(32, 11).toString("base64");
const TIMEOUT_MS = 400;
const uat = process.env.ECF_POSTGRES_UAT === "true" ? describe : describe.skip;

type Captured = {
  method: string;
  path: string;
  headers: Record<string, string | string[] | undefined>;
  body: string;
};

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

uat("Emisión DOSA sobre HTTP local real — cinco empresas", () => {
  let app: INestApplication;
  let prisma: PrismaService;
  let dbName: string;
  let adminUrl: string;
  let server: Server;
  let baseUrl: string;
  const requests: Captured[] = [];
  const ENV_BACKUP: Record<string, string | undefined> = {};

  const http = () => request(app.getHttpServer());

  function setEnv(key: string, value: string) {
    if (!(key in ENV_BACKUP)) ENV_BACKUP[key] = process.env[key];
    process.env[key] = value;
  }

  /** Último dígito del RNC sintético → escenario del proveedor. */
  function scenarioForRnc(rnc: string): string {
    return rnc.slice(-1);
  }

  function readBody(req: IncomingMessage): Promise<string> {
    return new Promise((resolve, reject) => {
      const chunks: Buffer[] = [];
      req.on("data", (chunk: Buffer) => chunks.push(chunk));
      req.on("end", () => resolve(Buffer.concat(chunks).toString("utf8")));
      req.on("error", reject);
    });
  }

  /** Respuesta del "proveedor" según el RNC emisor del cuerpo. */
  function respondFor(bodyText: string, res: ServerResponse): void {
    let rnc = "";
    let encf = "";
    try {
      const parsed = JSON.parse(bodyText) as Record<string, any>;
      rnc = parsed?.encabezado?.emisor?.RNCEmisor ?? "";
      encf = parsed?.encabezado?.idDoc?.eNCF ?? "";
    } catch {
      // Se responde como cuerpo mal formado más abajo.
    }

    const scenario = scenarioForRnc(rnc);
    // Respuesta conforme documentada (plana, `codigo` como texto).
    const accepted = {
      trackId: `track-${encf}`,
      codigo: "4",
      estado: "Aceptado Condicional",
      rnc,
      encf,
      url: "https://ecf.dgii.gov.do/testecf/consulta",
      codigoSeguridad: "EAkbyR",
      fechaFirma: "15-11-2025 14:46:41",
      secuenciaUtilizada: true,
      fechaRecepcion: "2025-11-15T10:46:42",
      mensajes: [],
    };

    switch (scenario) {
      case "8": {
        // HTTP 201 con `ok:false` y estado de rechazo: NO es aceptación.
        res.writeHead(201, { "Content-Type": "application/json" });
        res.end(
          JSON.stringify({
            ok: false,
            trackId: `track-${encf}`,
            estado: "Rechazado",
            encf,
            rnc,
            secuenciaUtilizada: false,
            mensajes: [{ valor: "El campo MontoGravadoI1 no coincide", codigo: 1934 }],
          }),
        );
        return;
      }
      case "9": {
        // HTTP 400 con texto plano (validación previa).
        res.writeHead(400, { "Content-Type": "text/plain" });
        res.end("El campo RNCEmisor en Emisor es obligatorio.");
        return;
      }
      case "7": {
        // Cuerpo no interpretable.
        res.writeHead(200, { "Content-Type": "application/json" });
        res.end("<html>no es json</html>");
        return;
      }
      case "6": {
        // Pendiente DGII (202): firmado y guardado por el proveedor.
        res.writeHead(202, { "Content-Type": "application/json" });
        res.end(JSON.stringify({ ...accepted, codigo: "3", estado: "Pendiente DGII" }));
        return;
      }
      default: {
        res.writeHead(200, { "Content-Type": "application/json" });
        res.end(JSON.stringify(accepted));
        return;
      }
    }
  }

  async function startServer() {
    server = createServer((req, res) => {
      void (async () => {
        const body = await readBody(req);
        requests.push({
          method: req.method ?? "",
          path: req.url ?? "",
          headers: req.headers,
          body,
        });
        respondFor(body, res);
      })();
    });
    await new Promise<void>((resolve) => server.listen(0, "127.0.0.1", resolve));
    const address = server.address() as AddressInfo;
    baseUrl = `http://127.0.0.1:${address.port}`;
  }

  async function stopServer() {
    if (!server) return;
    await new Promise<void>((resolve) => server.close(() => resolve()));
  }

  async function bootApp() {
    const moduleRef = await Test.createTestingModule({ imports: [AppModule] }).compile();
    app = moduleRef.createNestApplication();
    app.useGlobalPipes(
      new ValidationPipe({ whitelist: true, forbidNonWhitelisted: true, transform: true }),
    );
    await app.init();
    prisma = app.get(PrismaService);
  }

  beforeAll(async () => {
    if (process.env.ALANUBE_ENABLE_REAL_CALLS !== "false") {
      throw new Error("E2E_REFUSES_REAL_PROVIDER_CALLS");
    }
    await startServer();

    dbName = `fullpos_dosa_http_e2e_${Date.now()}`;
    if (!SAFE_DB.test(dbName)) throw new Error("Unsafe E2E DB name");
    adminUrl = replaceDbName(baseDatabaseUrl(), "postgres");
    const appUrl = replaceDbName(baseDatabaseUrl(), dbName);

    const admin = new Client({ connectionString: adminUrl });
    await admin.connect();
    await admin.query(`CREATE DATABASE ${dbName}`);
    await admin.end();

    setEnv("DATABASE_URL", appUrl);
    setEnv("JWT_SECRET", process.env.JWT_SECRET || "dosa-http-e2e-secret");
    setEnv("APP_ENV", "uat");
    setEnv("UAT_LOCAL_ONLY", "true");
    setEnv("ALANUBE_ENABLE_REAL_CALLS", "false");
    setEnv("DOSA_CREDENTIALS_MASTER_KEY", MASTER_KEY);
    setEnv("DOSA_EMISSION_ENABLED", "true");
    setEnv("DOSA_EMISSION_ENVIRONMENT", "TEST");
    setEnv("DOSA_PRODUCTION_EMISSION_ENABLED", "false");
    // El destino es un servidor HTTP LOCAL de pruebas, no DOSA.
    setEnv("DOSA_BASE_URL", baseUrl);
    setEnv("DOSA_EMISSION_TIMEOUT_MS", String(TIMEOUT_MS));
    setEnv("DOSA_WEBHOOK_ENABLED", "false");
    setEnv("ECF_PORTAL_PILOT_COMPANY_IDS", "");
    setEnv("ECF_PORTAL_AUTO_ENROLL_ENABLED", "false");

    execFileSync(process.execPath, [resolvePrismaCliPath(), "migrate", "deploy"], {
      cwd: process.cwd(),
      env: { ...process.env, DATABASE_URL: appUrl },
      stdio: "pipe",
    });

    await bootApp();
  }, 600000);

  afterAll(async () => {
    if (app) await app.close();
    await stopServer();
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

  /** RNC sintético cuyo último dígito decide el escenario del servidor. */
  async function registerTenant(suffix: string, scenarioDigit: string): Promise<Tenant> {
    const rnc = `7${String(Date.now()).slice(-7)}${scenarioDigit}`;
    const res = await http()
      .post("/auth/register-business")
      .send({
        firstName: "Http",
        lastName: suffix,
        email: `http-${Date.now()}-${suffix}@example.test`,
        phone: "8095550000",
        password: PASSWORD,
        confirmPassword: PASSWORD,
        commercialName: `Http ${suffix}`,
        taxId: rnc,
        businessPhone: "8095551111",
        address: `Calle Ficticia ${suffix}`,
        country: "DO",
      });
    if (res.status !== 201) throw new Error(`register-business ${suffix} -> ${res.status}`);
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

  async function setCertification(
    tenant: Tenant,
    status: "AUTHORIZED_SANDBOX" | "SUSPENDED" | "NOT_STARTED",
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

  async function sell(tenant: Tenant, buyerTaxId = "131000001"): Promise<string> {
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
        nombre: "Artículo HTTP",
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
    return (sale.body as { id: string }).id;
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

  async function seedCredentials(input: {
    companyId: string;
    rnc: string;
    apiKeyTest: string;
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
      bundle: { apiKeyTest: input.apiKeyTest, apiSecret: `secret-${input.companyId.slice(0, 8)}` },
      signatureAuthenticated: true,
    });
    expect(ingested.ok).toBe(true);
    if (input.status === "ACTIVE") {
      const promoted = await service.promote({
        companyId: input.companyId,
        rnc: input.rnc,
        environment: "test",
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
            postulacionId: "postulacion-ficticia-test",
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
    return service;
  }

  /** Empresa lista para emitir, con su RNC de escenario y su clave propia. */
  async function readyCompany(suffix: string, scenarioDigit: string) {
    const tenant = await registerTenant(suffix, scenarioDigit);
    await enableEcf(tenant);
    await registerSequence(tenant);
    await setCertification(tenant, "AUTHORIZED_SANDBOX");
    const apiKey = `sk_test_HTTP_${suffix.toUpperCase()}`;
    await seedCredentials({
      companyId: tenant.companyId,
      rnc: tenant.rnc,
      apiKeyTest: apiKey,
      status: "ACTIVE",
    });
    const saleId = await sell(tenant);
    const documentId = await prepareOk(tenant, saleId);
    return { tenant, documentId, apiKey };
  }

  function dispatch(tenant: Tenant, documentId: string) {
    return http()
      .post(`/ecf/documents/${documentId}/dispatch-dosa`)
      .set("Authorization", `Bearer ${tenant.token}`)
      .send({});
  }

  function documentOf(tenant: Tenant, documentId: string) {
    return prisma.ecfElectronicDocument.findFirstOrThrow({
      where: { id: documentId, companyId: tenant.companyId },
      select: { id: true, status: true, payloadSummary: true },
    });
  }

  // --------------------------------------------------------------------- casos

  it("A: la petición sale por HTTP real con su RNC, su e-NCF y su clave, y la respuesta se persiste", async () => {
    const { tenant, documentId, apiKey } = await readyCompany("a", "1");
    requests.length = 0;

    const res = await dispatch(tenant, documentId);
    expect(res.body).toMatchObject({ ok: true });

    // 1) Hubo una petición HTTP REAL al endpoint documentado.
    expect(requests).toHaveLength(1);
    const sent = requests[0];
    expect(sent.method).toBe("POST");
    expect(sent.path).toBe("/fe/api/emision/ecf/EnviarFactura");

    // 2) Autenticación SALIENTE: API key de la empresa, y ninguna firma de webhook.
    expect(sent.headers["x-api-key"]).toBe(apiKey);
    expect(sent.headers["x-dosa-signature"]).toBeUndefined();
    expect(Object.keys(sent.headers).sort()).toEqual(
      expect.arrayContaining(["content-type", "x-api-key"]),
    );

    // 3) Serialización exacta del cuerpo DOSA.
    const body = JSON.parse(sent.body) as Record<string, any>;
    expect(body.encabezado.emisor.RNCEmisor).toBe(tenant.rnc);
    expect(body.encabezado.idDoc.tipoeCF).toBe("31");
    expect(body.encabezado.idDoc.eNCF).toBe(res.body.encf);
    expect(body.detallesItems.length).toBeGreaterThan(0);

    // 4) La respuesta del servidor quedó persistida con la huella de lo enviado.
    const attempt = await prisma.ecfElectronicDocumentAttempt.findFirstOrThrow({
      where: { companyId: tenant.companyId, documentId, operation: "SEND_TO_PROVIDER" },
    });
    expect(attempt.requestFingerprint).toBe(fingerprint(body));

    const doc = await documentOf(tenant, documentId);
    // Aceptación CONDICIONAL del proveedor: nunca aceptación fiscal automática.
    expect(doc.status).not.toBe("DGII_ACCEPTED");
    expect(["HUMAN_REVIEW_REQUIRED", "PROVIDER_ACCEPTED", "DGII_STATUS_PENDING"]).toContain(
      doc.status,
    );
  });

  it("HTTP 201 con ok:false NO se convierte en aceptación", async () => {
    const { tenant, documentId } = await readyCompany("okfalse", "8");
    requests.length = 0;

    const res = await dispatch(tenant, documentId);
    expect(requests).toHaveLength(1);

    const doc = await documentOf(tenant, documentId);
    expect(doc.status).not.toBe("DGII_ACCEPTED");
    expect(doc.status).not.toBe("PROVIDER_ACCEPTED");
    // Un rechazo del proveedor exige revisión humana; no se reemite a ciegas.
    expect(["HUMAN_REVIEW_REQUIRED", "UNKNOWN_RESULT", "PROVIDER_REJECTED"]).toContain(
      doc.status,
    );
    expect(res.body.canRetryPost).toBe(false);
  });

  it("HTTP 400 con texto plano deja el resultado desconocido y no reintenta", async () => {
    const { tenant, documentId } = await readyCompany("bad400", "9");
    requests.length = 0;

    const res = await dispatch(tenant, documentId);
    expect(requests).toHaveLength(1);
    expect(res.body.canRetryPost).toBe(false);
    const doc = await documentOf(tenant, documentId);
    expect(doc.status).not.toBe("DGII_ACCEPTED");
    expect(["UNKNOWN_RESULT", "HUMAN_REVIEW_REQUIRED"]).toContain(doc.status);
  });

  it("una respuesta mal formada no se interpreta como éxito", async () => {
    const { tenant, documentId } = await readyCompany("malformed", "7");
    requests.length = 0;

    await dispatch(tenant, documentId);
    expect(requests).toHaveLength(1);
    const doc = await documentOf(tenant, documentId);
    expect(doc.status).not.toBe("DGII_ACCEPTED");
    expect(["UNKNOWN_RESULT", "HUMAN_REVIEW_REQUIRED"]).toContain(doc.status);
  });

  it("202 Pendiente DGII se guarda como pendiente, no como aceptado", async () => {
    const { tenant, documentId } = await readyCompany("pending", "6");
    requests.length = 0;

    await dispatch(tenant, documentId);
    expect(requests).toHaveLength(1);
    const doc = await documentOf(tenant, documentId);
    expect(doc.status).not.toBe("DGII_ACCEPTED");
  });

  it("un segundo despacho del mismo documento no genera una segunda petición HTTP", async () => {
    const { tenant, documentId } = await readyCompany("dup", "1");
    requests.length = 0;

    const first = await dispatch(tenant, documentId);
    expect(first.body).toMatchObject({ ok: true });
    expect(requests).toHaveLength(1);

    const second = await dispatch(tenant, documentId);
    expect(second.status).toBeGreaterThanOrEqual(400);
    expect(requests).toHaveLength(1);
  });

  it("B: sin credenciales no hay ninguna petición HTTP", async () => {
    const tenant = await registerTenant("nokey", "1");
    await enableEcf(tenant);
    await registerSequence(tenant);
    await setCertification(tenant, "AUTHORIZED_SANDBOX");
    const documentId = await prepareOk(tenant, await sell(tenant));
    requests.length = 0;

    const res = await dispatch(tenant, documentId);
    expect(res.body).toMatchObject({ ok: false });
    expect(requests).toHaveLength(0);
  });

  it("C: una credencial pendiente no emite", async () => {
    const tenant = await registerTenant("pending", "1");
    await enableEcf(tenant);
    await registerSequence(tenant);
    await setCertification(tenant, "AUTHORIZED_SANDBOX");
    await seedCredentials({
      companyId: tenant.companyId,
      rnc: tenant.rnc,
      apiKeyTest: "sk_test_HTTP_PENDING",
      status: "PENDING_CONFIRMATION",
    });
    const documentId = await prepareOk(tenant, await sell(tenant));
    requests.length = 0;

    const res = await dispatch(tenant, documentId);
    expect(res.body.blockingReasons).toContain("ECF_DOSA_GATE_CREDENTIALS_NOT_ACTIVE");
    expect(requests).toHaveLength(0);
  });

  it("E: certificación suspendida no emite aunque la credencial esté activa", async () => {
    const tenant = await registerTenant("suspended", "1");
    await enableEcf(tenant);
    await registerSequence(tenant);
    await seedCredentials({
      companyId: tenant.companyId,
      rnc: tenant.rnc,
      apiKeyTest: "sk_test_HTTP_SUSPENDED",
      status: "ACTIVE",
    });
    await setCertification(tenant, "SUSPENDED");
    const documentId = await prepareOk(tenant, await sell(tenant));
    requests.length = 0;

    const res = await dispatch(tenant, documentId);
    expect(res.body).toMatchObject({
      ok: false,
      code: "ECF_DOSA_DISPATCH_CERTIFICATION_NOT_AUTHORIZED",
    });
    expect(requests).toHaveLength(0);
  });

  it("acceso cruzado: el documento de otra empresa no se despacha", async () => {
    const { documentId } = await readyCompany("cross-a", "1");
    const other = await registerTenant("cross-b", "1");
    await enableEcf(other);
    await registerSequence(other);
    await setCertification(other, "AUTHORIZED_SANDBOX");
    requests.length = 0;

    const res = await dispatch(other, documentId);
    expect(res.status).toBeGreaterThanOrEqual(400);
    expect(requests).toHaveLength(0);
  });

  it("concurrencia: dos empresas emiten a la vez con su propio cuerpo y clave", async () => {
    const first = await readyCompany("conc-a", "1");
    const second = await readyCompany("conc-b", "1");
    requests.length = 0;

    const [res1, res2] = await Promise.all([
      dispatch(first.tenant, first.documentId),
      dispatch(second.tenant, second.documentId),
    ]);
    expect(res1.body).toMatchObject({ ok: true });
    expect(res2.body).toMatchObject({ ok: true });
    expect(requests).toHaveLength(2);

    const byRnc = new Map<string, { key: unknown; encf: string }>();
    for (const sent of requests) {
      const body = JSON.parse(sent.body) as Record<string, any>;
      byRnc.set(body.encabezado.emisor.RNCEmisor, {
        key: sent.headers["x-api-key"],
        encf: body.encabezado.idDoc.eNCF,
      });
    }
    expect(byRnc.get(first.tenant.rnc)?.key).toBe(first.apiKey);
    expect(byRnc.get(second.tenant.rnc)?.key).toBe(second.apiKey);
    // Cada empresa numeró desde SU rango: los e-NCF son válidos e independientes.
    expect(byRnc.get(first.tenant.rnc)?.encf).toMatch(/^E31\d{10}$/);
    expect(byRnc.get(second.tenant.rnc)?.encf).toMatch(/^E31\d{10}$/);
  });

  it("el estado persiste tras reiniciar el backend y no se reenvía solo", async () => {
    const { tenant, documentId } = await readyCompany("restart", "1");
    requests.length = 0;
    await dispatch(tenant, documentId);
    expect(requests).toHaveLength(1);
    const before = (await documentOf(tenant, documentId)).status;

    await app.close();
    await bootApp();

    expect((await documentOf(tenant, documentId)).status).toBe(before);
    const again = await dispatch(tenant, documentId);
    expect(again.status).toBeGreaterThanOrEqual(400);
    expect(requests).toHaveLength(1);
  });

  it("la facturación normal del POS sigue funcionando con e-CF deshabilitado", async () => {
    const tenant = await registerTenant("pos", "1");
    const saleId = await sell(tenant);
    const persisted = await prisma.sale.findFirstOrThrow({
      where: { id: saleId, companyId: tenant.companyId },
    });
    expect(persisted.id).toBe(saleId);
    expect(
      await prisma.ecfElectronicDocument.count({ where: { companyId: tenant.companyId } }),
    ).toBe(0);
  });
});
