import { INestApplication, ValidationPipe } from "@nestjs/common";
import { Test } from "@nestjs/testing";
import type { Prisma } from "@prisma/client";
import { execFileSync } from "node:child_process";
import { randomUUID } from "node:crypto";
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
import { EcfEmissionService } from "../../documents/ecf-emission.service";
import { validE31WithItbis } from "../../fiscal-core/ecf-fixtures";

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
 *  - No hay aceptación fiscal real: las respuestas son sintéticas.
 *  - Por defecto se conserva revisión. El escenario habilitado explícitamente
 *    comprueba el registro local del resultado y sus evidencias.
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
  const unavailableRncs = new Set<string>();
  const settledRncs = new Set<string>();
  const providerAccepted = new Map<string, { body: string; path: string; response: string }>();
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
  function respondFor(bodyText: string, res: ServerResponse, requestUrl = "/", production = false): void {
    let rnc = "";
    let encf = "";
    let printedPayload: Record<string, any> = {};
    try {
      const parsed = JSON.parse(bodyText) as Record<string, any>;
      printedPayload = parsed;
      rnc = parsed?.encabezado?.emisor?.RNCEmisor ?? "";
      encf = parsed?.encabezado?.idDoc?.eNCF ?? "";
    } catch {
      // Se responde como cuerpo mal formado más abajo.
    }

    const creditQuery = new URL(requestUrl, "http://127.0.0.1").searchParams;
    encf = creditQuery.get("nuevoENCF") ?? encf;

    if (unavailableRncs.has(rnc)) { res.destroy(); return; }
    const scenario = scenarioForRnc(rnc);
    // Respuesta conforme documentada (plana, `codigo` como texto).
    const accepted = {
      trackId: `track-${encf}`,
      codigo: "4",
      estado: "Aceptado Condicional",
      rnc,
      encf,
      url: `https://ecf.dgii.gov.do/${production ? "ecf" : "testecf"}/ConsultaTimbre?${new URLSearchParams({
        RncEmisor: rnc, RncComprador: printedPayload.encabezado?.comprador?.RNCComprador ?? "",
        ENCF: encf, FechaEmision: creditQuery.get("fechaEmision") ?? printedPayload.encabezado?.emisor?.fechaEmision ?? "",
        MontoTotal: String(printedPayload.encabezado?.totales?.MontoTotal ?? ""),
        FechaFirma: "15-11-2025 14:46:41", CodigoSeguridad: "EAkbyR",
      })}`,
      codigoSeguridad: "EAkbyR",
      fechaFirma: "15-11-2025 14:46:41",
      secuenciaUtilizada: true,
      fechaRecepcion: "2025-11-15T10:46:42",
      mensajes: [],
    };

    if (scenario === "3" && encf.startsWith("E32")) {
      const amount=Number(printedPayload.encabezado.totales.MontoTotal);
      res.writeHead(200,{"Content-Type":"application/json"});
      res.end(JSON.stringify({...accepted,trackId:undefined,codigo:"1",estado:"Aceptado",montoTotal:amount,
        url:`https://fc.dgii.gov.do/testecf/ConsultaTimbreFC?RncEmisor=${rnc}&ENCF=${encf}&MontoTotal=${amount}&CodigoSeguridad=EAkbyR`}));
      return;
    }
    switch (scenario) {
      case "0": {
        // Simulates a provider that accepts exactly once but loses the first
        // HTTP response. Repeating the same request returns the stored result.
        const scope = `${rnc}|${production}|${encf}`;
        const cached = providerAccepted.get(scope);
        if (!cached) {
          providerAccepted.set(scope, { body: bodyText, path: requestUrl, response: JSON.stringify(accepted) });
          res.destroy();
          return;
        }
        if (cached.body !== bodyText || cached.path !== requestUrl) {
          res.writeHead(409); res.end('{"error":"SYNTHETIC_CHANGED_REQUEST"}'); return;
        }
        res.writeHead(200, { "Content-Type": "application/json" }); res.end(cached.response); return;
      }
      case "4": {
        res.writeHead(200, { "Content-Type": "application/json" });
        res.end(JSON.stringify({ ...accepted, rnc: "999999999" }));
        return;
      }
      case "5": {
        res.writeHead(200, { "Content-Type": "application/json" });
        res.end(JSON.stringify({ ...accepted, url: "https://example.test/invalid" }));
        return;
      }
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
        if(settledRncs.has(rnc)){res.writeHead(200,{"Content-Type":"application/json"});res.end(JSON.stringify(accepted));return;}
        // Pendiente DGII (202): firmado y guardado por el proveedor.
        res.writeHead(202, { "Content-Type": "application/json" });
        res.end(JSON.stringify({ ...accepted, trackId: undefined, codigo: "3", estado: "Pendiente DGII", leyendaContingencia: "EMITIDO EN CONTINGENCIA - PENDIENTE DGII" }));
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
        respondFor(body, res, req.url, String(req.headers["x-api-key"] ?? "").startsWith("sk_prod_"));
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
    setEnv("DOSA_CONFIRMED_DGII_OUTCOMES_ENABLED", "false");
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

  async function registerSequence(tenant: Tenant, documentType: "E31" | "E32" = "E31") {
    // La numeración exige la autorización DGII declarada (fail-closed).
    const declared = await http()
      .post("/ecf/dgii/authorized-sequences")
      .set("Authorization", `Bearer ${tenant.token}`)
      .send({
        documentType,
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
      .send({ documentType, startNumber: 1, endNumber: 50 });
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
      });
    expect(fiscal.status).toBe(200);
    // El motor NCF se retiró: la venta ya no pide talón B01; el e-CF se prepara
    // después con su propia numeración autorizada.
  }

  async function sell(tenant: Tenant, buyerTaxId = "131000001", electronicType?: "E31" | "E32" | "NORMAL"): Promise<string> {
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
        ...(electronicType ? { fiscalVoucherType: electronicType, sequenceDueDate: "2028-12-31" } : {}),
        paymentMethod: "cash",
        paymentCashAmount: 118,
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
    apiKeyProduccion?: string;
    environment?: "test" | "production";
    status: "PENDING_CONFIRMATION" | "ACTIVE";
  }) {
    const service = new DosaCredentialService(
      new PrismaDosaCredentialStore(prisma as never),
      new DosaCredentialVault(MASTER_KEY),
    );
    const ingested = await service.ingestFromProvider({
      companyId: input.companyId,
      rnc: input.rnc,
      environment: input.environment ?? "test",
      bundle: { apiKeyTest: input.apiKeyTest, apiKeyProduccion: input.apiKeyProduccion, apiSecret: `secret-${input.companyId.slice(0, 8)}` },
      signatureAuthenticated: true,
    });
    expect(ingested.ok).toBe(true);
    if (input.status === "ACTIVE") {
      const promoted = await service.promote({
        companyId: input.companyId,
        rnc: input.rnc,
        environment: input.environment ?? "test",
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
      select: { id: true, status: true, payloadSummary: true, printStamp: true },
    });
  }

  // --------------------------------------------------------------------- casos

  it("certified companies explicitly enable production with their own credentials and prepare commercial E31", async () => {
    const tenant=await registerTenant("production-enable","1");await enableEcf(tenant);
    const enable=()=>http().post("/ecf/production/enable").set("Authorization",`Bearer ${tenant.token}`)
      .send({expectedCompanyId:tenant.companyId});
    await http().post("/ecf/production/enable").set("Authorization",`Bearer ${tenant.token}`).expect(400);
    await http().post("/ecf/production/enable").set("Authorization",`Bearer ${tenant.token}`)
      .send({expectedCompanyId:randomUUID()}).expect(409);
    await enable().expect(403);
    setEnv("DOSA_PRODUCTION_EMISSION_ENABLED","true");setEnv("DOSA_CONFIRMED_DGII_OUTCOMES_ENABLED","true");
    try {
      await enable().expect(403);
      await prisma.ecfCompanyConfiguration.update({where:{companyId:tenant.companyId},data:{certificationStatus:"PRODUCTION_READY"}});
      await enable().expect(403);
      await seedCredentials({companyId:tenant.companyId,rnc:tenant.rnc,apiKeyTest:"synthetic-unused",apiKeyProduccion:"synthetic-production",
        environment:"production",status:"ACTIVE"});
      await registerSequence(tenant);
      const pending=await new EcfEmissionService(prisma).prepare({id:tenant.userId,companyId:tenant.companyId,role:"ADMIN"},{
        document:{...validE31WithItbis,sender:{...validE31WithItbis.sender,taxId:tenant.rnc},
          paymentForms:[{code:"1",amount:String(validE31WithItbis.totals.total)}]},
        metadata:{paymentType:1,incomeType:1,sequenceDueDate:"2028-12-31"},sourceType:"MANUAL",clientRequestId:randomUUID()});
      await prisma.ecfElectronicDocument.update({where:{id:pending.id},data:{status:"HUMAN_REVIEW_REQUIRED"}});
      const unresolved=await enable().expect(409);
      expect(unresolved.body.message).toBe("ECF_PRODUCTION_PENDING_TEST_RESULTS");
      // A synthetic reviewed engineering trial may close readiness without
      // inventing fiscal acceptance or changing its HUMAN_REVIEW_REQUIRED status.
      const proofHash="b".repeat(64), reviewPlan="SYNTHETIC_REVIEW";
      await prisma.ecfElectronicDocument.update({where:{id:pending.id},data:{payloadSummary:{
        ...(pending.payloadSummary as Prisma.JsonObject),controlledTest:{environment:"TEST",correlated:true,outcome:"ACCEPTED",
          responseSha256:proofHash,plan:reviewPlan}}}});
      await enable().expect(409);
      await prisma.ecfElectronicDocumentStatusLog.create({data:{companyId:tenant.companyId,documentId:pending.id,
        statusBefore:"HUMAN_REVIEW_REQUIRED",statusAfter:"HUMAN_REVIEW_REQUIRED",reasonCode:"LEGACY_TEST_ENVIRONMENT_CLASSIFIED",
        metadata:{environment:"SANDBOX",documentFingerprint:pending.payloadFingerprint,evidenceSha256:proofHash,
          evidencePlan:reviewPlan,manifestHash:"c".repeat(64),reviewer:"synthetic-review"}}});
      const legacyDraft=await prisma.ecfElectronicDocument.create({data:{companyId:tenant.companyId,environment:null,
        documentType:"E31",status:"LOCAL_DRAFT",payloadFingerprint:"d".repeat(64),idempotencyKey:randomUUID()}});
      await enable().expect(409);
      // Remove only this unused synthetic fixture; live histories require review.
      await prisma.ecfElectronicDocument.deleteMany({where:{companyId:tenant.companyId,id:legacyDraft.id,status:"LOCAL_DRAFT"}});
      requests.length=0;
      const configured=await enable().expect(201);
      expect(configured.body).toMatchObject({companyId:tenant.companyId,environment:"PRODUCTION",productionEnabled:true});
      expect((await documentOf(tenant,pending.id)).status).toBe("HUMAN_REVIEW_REQUIRED");
      await enable().expect(201);
      expect(requests).toHaveLength(0);
      await registerSequence(tenant);
      const saleId=await sell(tenant,"131000001","E31");
      const id=await prepareOk(tenant,saleId);
      const doc=await prisma.ecfElectronicDocument.findFirstOrThrow({where:{companyId:tenant.companyId,id}});
      expect(doc.environment).toBe("PRODUCTION");
      const other=await registerTenant("production-foreign","1");await enableEcf(other);
      await http().post("/ecf/production/enable").set("Authorization",`Bearer ${other.token}`)
        .send({expectedCompanyId:other.companyId}).expect(403);
      expect((await prisma.ecfCompanyConfiguration.findUniqueOrThrow({where:{companyId:other.companyId}})).environment).toBe("SANDBOX");
    }finally{setEnv("DOSA_PRODUCTION_EMISSION_ENABLED","false");setEnv("DOSA_CONFIRMED_DGII_OUTCOMES_ENABLED","false");}
  });

  it("RFCE E32 without trackId records its accepted result and public fiscal print data", async () => {
    setEnv("DOSA_CONFIRMED_DGII_OUTCOMES_ENABLED","true");
    try {
      const tenant=await registerTenant("rfce","3");await enableEcf(tenant);
      await prisma.ecfCompanyConfiguration.update({where:{companyId:tenant.companyId},data:{allowedTypes:["E31","E32"]}});
      await registerSequence(tenant,"E32");await setCertification(tenant,"AUTHORIZED_SANDBOX");
      await seedCredentials({companyId:tenant.companyId,rnc:tenant.rnc,apiKeyTest:"synthetic-rfce",status:"ACTIVE"});
      const saleId=await sell(tenant);
      const prepared=await http().post("/ecf/documents/prepare-consumo").set("Authorization",`Bearer ${tenant.token}`)
        .send({saleId,documentType:"E32",paymentType:1,incomeType:1}).expect(201);
      expect(prepared.body.ok).toBe(true);
      const id=prepared.body.value.documentId;
      const result=await dispatch(tenant,id);expect(result.body.confirmedFiscalOutcome).toBe(true);
      expect((await documentOf(tenant,id)).status).toBe("DGII_ACCEPTED");
      const print=await http().get(`/ecf/sales/${saleId}/print`).set("Authorization",`Bearer ${tenant.token}`).expect(200);
      expect(print.body.document).toMatchObject({documentType:"E32",state:"SIGNED",qrUrl:expect.stringContaining("fc.dgii.gov.do/testecf/")});
    }finally{setEnv("DOSA_CONFIRMED_DGII_OUTCOMES_ENABLED","false");}
  });
  it("202 is printable as contingency and later reconciles the same document without another sequence", async () => {
    setEnv("DOSA_CONFIRMED_DGII_OUTCOMES_ENABLED","true");
    const {tenant,documentId}=await readyCompany("contingency","6");
    const first=await dispatch(tenant,documentId);expect(first.body.confirmedFiscalOutcome).toBe(false);
    expect((await documentOf(tenant,documentId)).status).toBe("DGII_STATUS_PENDING");
    const print=await http().get(`/ecf/documents/${documentId}/print`).set("Authorization",`Bearer ${tenant.token}`).expect(200);
    expect(print.body.document).toMatchObject({state:"CONTINGENCY",contingencyLegend:"EMITIDO EN CONTINGENCIA - PENDIENTE DGII"});
    const stamp=(await documentOf(tenant,documentId)).printStamp;
    settledRncs.add(tenant.rnc);
    const clock=jest.spyOn(Date,"now").mockReturnValue(Date.now()+180000);
    try {
      const recovered=await http().post(`/ecf/documents/${documentId}/recover-dosa`).set("Authorization",`Bearer ${tenant.token}`).expect(201);
      expect(recovered.body.confirmedFiscalOutcome).toBe(true);
      expect(await documentOf(tenant,documentId)).toMatchObject({status:"DGII_ACCEPTED",printStamp:stamp});
    }finally{clock.mockRestore();setEnv("DOSA_CONFIRMED_DGII_OUTCOMES_ENABLED","false");}
  });

  it("a lost result survives restart and only one identical recovery is allowed after its lease", async () => {
    setEnv("DOSA_CONFIRMED_DGII_OUTCOMES_ENABLED","true");
    const {tenant,documentId}=await readyCompany("durable","2");
    unavailableRncs.add(tenant.rnc); requests.length=0;
    const initial=await dispatch(tenant,documentId);
    expect(initial.body.confirmedFiscalOutcome).toBe(false);
    expect(requests).toHaveLength(3);
    const originalRequest={body:requests[0].body,path:requests[0].path};
    await http().post(`/ecf/documents/${documentId}/recover-dosa`).set("Authorization",`Bearer ${tenant.token}`).expect(409);
    expect(requests).toHaveLength(3);
    unavailableRncs.delete(tenant.rnc);
    await app.close();await bootApp();
    const now=Date.now();const clock=jest.spyOn(Date,"now").mockReturnValue(now+180000);
    try {
      const results=await Promise.all([1,2].map(()=>http().post(`/ecf/documents/${documentId}/recover-dosa`).set("Authorization",`Bearer ${tenant.token}`)));
      expect(results.map(r=>r.status).sort()).toEqual([201,409]);
      expect(results.find(r=>r.status===201)?.body.confirmedFiscalOutcome).toBe(true);
      expect(requests).toHaveLength(4);
      expect({body:requests[3].body,path:requests[3].path}).toEqual(originalRequest);
      expect((await documentOf(tenant,documentId)).status).toBe("DGII_ACCEPTED");
      expect(await prisma.ecfElectronicDocumentAttempt.count({where:{companyId:tenant.companyId,documentId,operation:"SEND_TO_PROVIDER"}})).toBe(1);
      expect(await prisma.ecfElectronicDocumentAttempt.count({where:{companyId:tenant.companyId,documentId,operation:"QUERY_PROVIDER"}})).toBe(1);
    } finally {clock.mockRestore();setEnv("DOSA_CONFIRMED_DGII_OUTCOMES_ENABLED","false");}
  });

  it("Normal remains an internal sale, cannot become E31/E32 and consumes no fiscal sequence", async () => {
    const tenant=await registerTenant("normal", "1");
    await enableEcf(tenant); await registerSequence(tenant); await setCertification(tenant,"AUTHORIZED_SANDBOX");
    await prisma.ecfCompanyConfiguration.update({where:{companyId:tenant.companyId},data:{allowSalesWithoutEcf:true,allowedTypes:["E31","E32","E34"]}});
    requests.length=0;
    const saleId=await sell(tenant,"131000001","NORMAL");
    const saved=await prisma.sale.findFirstOrThrow({where:{companyId:tenant.companyId,id:saleId}});
    expect(saved.fiscalVoucherType).toBe("NORMAL");expect(saved.ncf).toBeNull();expect(saved.ncfExpirationDate).toBeNull();
    const prepare=await http().post("/ecf/documents/prepare").set("Authorization",`Bearer ${tenant.token}`)
      .send({saleId,documentType:"E31",paymentType:1,incomeType:1,sequenceDueDate:"2028-12-31"}).expect(201);
    expect(prepare.body).toMatchObject({ok:false,code:"ECF_NORMAL_SALE_NOT_ELECTRONIC"});
    const consumo=await http().post("/ecf/documents/prepare-consumo").set("Authorization",`Bearer ${tenant.token}`)
      .send({saleId,documentType:"E32",paymentType:1,incomeType:1}).expect(201);
    expect(consumo.body).toMatchObject({ok:false,code:"ECF_NORMAL_SALE_NOT_ELECTRONIC"});
    expect(await prisma.ecfElectronicDocument.count({where:{companyId:tenant.companyId,sourceId:saleId}})).toBe(0);
    expect(await prisma.ecfSequenceAuditLog.count({where:{companyId:tenant.companyId}})).toBe(0);
    expect(requests).toHaveLength(0);
    const print=await http().get(`/ecf/sales/${saleId}/print`).set("Authorization",`Bearer ${tenant.token}`).expect(200);
    expect(print.body.document).toBeNull();
    await prisma.ecfCompanyConfiguration.update({where:{companyId:tenant.companyId},data:{allowSalesWithoutEcf:false}});
    const denied=await http().post("/sales").set("Authorization",`Bearer ${tenant.token}`).send({
      fiscalVoucherType:"NORMAL", paymentMethod:"cash", paymentCashAmount:118,
      customerId:saved.customerId, expectedTotalSold:118,
      items:[{productId:(await prisma.saleItem.findFirstOrThrow({where:{saleId,sale:{companyId:tenant.companyId}}})).productId,
        productSource:"LOCAL",productName:"Artículo HTTP",qty:1,priceSoldUnit:118}],
    }).expect(409);
    expect(denied.body.code).toBe("ECF_NORMAL_SALES_DISABLED");
    expect(requests).toHaveLength(0);
  });

  it("sale intent is persisted before preparation, stays tenant-scoped and cannot use ordinary cancellation", async () => {
    const tenant = await registerTenant("intent", "1");
    await enableEcf(tenant); await registerSequence(tenant); await setCertification(tenant, "AUTHORIZED_SANDBOX");
    const saleId = await sell(tenant, "131000001", "E31");
    const saved = await prisma.sale.findFirstOrThrow({where: {companyId: tenant.companyId, id: saleId}});
    expect(saved.fiscalVoucherType).toBe("E31"); expect(saved.ncf).toBeNull();
    expect(saved.ncfExpirationDate?.toISOString().slice(0,10)).toBe("2028-12-31");
    const pending = await http().get("/ecf/sales/fiscal").query({ids: saleId}).set("Authorization", `Bearer ${tenant.token}`).expect(200);
    expect(pending.body.items[0]).toMatchObject({saleId, intent: "E31", documents: []});
    await http().delete(`/sales/${saleId}`).set("Authorization", `Bearer ${tenant.token}`).expect(409);
    const prepared = await http().post("/ecf/documents/prepare").set("Authorization", `Bearer ${tenant.token}`)
      .send({saleId, documentType:"E31", paymentType:1, incomeType:1, sequenceDueDate:"2029-12-31"}).expect(201);
    expect(prepared.body.ok).toBe(true);
    const doc = await documentOf(tenant, prepared.body.value.documentId);
    expect((doc.payloadSummary as any).emission.payload.idDoc.sequenceDueDate).toBe("2028-12-31");
    const foreign = await registerTenant("intent-foreign", "1");
    const hidden = await http().get("/ecf/sales/fiscal").query({ids: saleId}).set("Authorization", `Bearer ${foreign.token}`).expect(200);
    expect(hidden.body.items).toEqual([]);
  });

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
    expect(body.detallesItems.items.length).toBeGreaterThan(0);

    // 4) La respuesta del servidor quedó persistida con la huella de lo enviado.
    const attempt = await prisma.ecfElectronicDocumentAttempt.findFirstOrThrow({
      where: { companyId: tenant.companyId, documentId, operation: "SEND_TO_PROVIDER" },
    });
    expect(attempt.requestFingerprint).toBe(fingerprint(body));

    const doc = await documentOf(tenant, documentId);
    expect(doc.printStamp).toEqual({
      qrUrl: expect.stringContaining("https://ecf.dgii.gov.do/testecf/ConsultaTimbre?"),
      securityCode: "EAkbyR", signedAt: "15-11-2025 14:46:41",
    });
    const source = await prisma.ecfElectronicDocument.findFirstOrThrow({where:{companyId:tenant.companyId,id:documentId},select:{sourceId:true}});
    const printed = await http().get(`/ecf/sales/${source.sourceId}/print`).set("Authorization", `Bearer ${tenant.token}`).expect(200);
    expect(printed.body.document.state).toBe("SIGNED");
    expect(printed.body.document.encf).toBe(res.body.encf);
    expect(JSON.stringify(printed.body)).not.toContain(apiKey);
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

  it.each(["1", "0"])("documented DOSA result: real POS sale -> E31 evidence -> reserved E34 -> applied credit and QR (%s)", async scenario => {
    const oldFlag = process.env.DOSA_CONFIRMED_DGII_OUTCOMES_ENABLED;
    process.env.DOSA_CONFIRMED_DGII_OUTCOMES_ENABLED = "true";
    try {
      // All provider traffic stays on the local HTTP fixture. No real DGII acceptance.
      const { tenant, documentId } = await readyCompany(`confirmed-chain-${scenario}`, scenario);
      const originalSummary = (await documentOf(tenant, documentId)).payloadSummary;
      const first = await dispatch(tenant, documentId);
      expect(first.status).toBe(201);
      expect(first.body.confirmedFiscalOutcome).toBe(true);
      expect(first.body.result).toBe("FISCAL_RESULT_RECORDED");
      const original = await prisma.ecfElectronicDocument.findFirstOrThrow({ where: { companyId: tenant.companyId, id: documentId } });
      expect(original.status).toBe("DGII_ACCEPTED");
      expect(original.payloadSummary).toEqual(originalSummary);
      expect(original.fiscalSnapshot).toMatchObject({ providerContract: "DOSA_EMISSION_2026_11" });
      await http().patch("/ecf/config").set("Authorization", `Bearer ${tenant.token}`)
        .send({ allowedTypes: ["E31", "E34"] }).expect(200);
      await http().post("/ecf/dgii/authorized-sequences").set("Authorization", `Bearer ${tenant.token}`).send({
        documentType: "E34", authorizationNumber: "SYNTHETIC-E34-ONLY", rangeFrom: 1, rangeTo: 50, approvedQuantity: 50, declarationAccepted: true,
      }).expect(201);
      await http().post("/ecf/sequences").set("Authorization", `Bearer ${tenant.token}`).send({ documentType: "E34", startNumber: 1, endNumber: 50 }).expect(201);
      const prepared = await http().post("/ecf/documents/prepare-credit-note").set("Authorization", `Bearer ${tenant.token}`).send({
        originalDocumentId: documentId, clientRequestId: randomUUID(), refundKind: "TOTAL", modificationCode: 1,
        modificationReason: "Devolución total sintética local", paymentType: 1, creditNoteIndicator: 1,
      }).expect(201);
      if (!prepared.body.ok) throw new Error(`Synthetic credit preparation blocked: ${JSON.stringify(prepared.body)}`);
      const noteId = prepared.body.value.documentId as string;
      const frozenNote = await documentOf(tenant, noteId);
      const second = await dispatch(tenant, noteId);
      expect(second.status).toBe(201);
      expect(second.body.confirmedFiscalOutcome).toBe(true);
      const note = await documentOf(tenant, noteId);
      expect(note.status).toBe("DGII_ACCEPTED");
      expect(note.payloadSummary).toEqual(frozenNote.payloadSummary);
      expect(note.printStamp).not.toBeNull();
      await expect(prisma.ecfElectronicDocument.updateMany({ where: { companyId: tenant.companyId, id: noteId },
        data: { printStamp: { altered: true } } })).rejects.toThrow("ECF_PRINT_STAMP_IMMUTABLE");
      const reservation = await prisma.ecfCreditReservation.findUniqueOrThrow({ where: { companyId_creditDocumentId: { companyId: tenant.companyId, creditDocumentId: noteId } } });
      expect(reservation.state).toBe("APPLIED");
      const printed = await http().get(`/ecf/documents/${noteId}/print`).set("Authorization", `Bearer ${tenant.token}`).expect(200);
      expect(printed.body.document).toMatchObject({ state: "SIGNED", documentType: "E34", originalEncf: first.body.encf });
      expect(printed.body.document.qrUrl).toContain(prepared.body.value.encf);
      const again = await dispatch(tenant, noteId);
      expect(again.status).toBeGreaterThanOrEqual(400);
      expect(await prisma.ecfElectronicDocumentAttempt.count({ where: { companyId: tenant.companyId, documentId: noteId, operation: "SEND_TO_PROVIDER" } })).toBe(1);
      if (scenario === "0") {
        const audits = await prisma.ecfElectronicDocumentStatusLog.findMany({ where: { companyId: tenant.companyId,
          documentId: { in: [documentId, noteId] }, reasonCode: "DOSA_IDENTICAL_REQUEST_REPLAY" } });
        expect(audits).toHaveLength(2);
        for (const audit of audits) expect(audit.metadata).toMatchObject({ ordinal: 2, reason: "NETWORK", stage: "AUTHORIZED_BEFORE_TRANSPORT" });
        const ownRequests = requests.filter(sent => JSON.parse(sent.body).encabezado.emisor.RNCEmisor === tenant.rnc);
        expect(ownRequests).toHaveLength(4);
        for (const endpoint of ["/EnviarFactura", "/NotaDesdeFactura"]) {
          const calls = ownRequests.filter(sent => sent.path.includes(endpoint));
          expect(calls).toHaveLength(2); expect(calls[0].body).toBe(calls[1].body); expect(calls[0].path).toBe(calls[1].path);
        }
        expect([...providerAccepted.keys()].filter(key => key.startsWith(`${tenant.rnc}|`))).toHaveLength(2);
        const ranges = await prisma.ecfSequence.findMany({ where: { companyId: tenant.companyId, documentType: { in: ["E31", "E34"] } } });
        expect(ranges.map(row => row.nextNumber)).toEqual([2, 2]);
      }
    } finally {
      if (oldFlag === undefined) delete process.env.DOSA_CONFIRMED_DGII_OUTCOMES_ENABLED;
      else process.env.DOSA_CONFIRMED_DGII_OUTCOMES_ENABLED = oldFlag;
    }
  });

  it.each(["4", "5", "6", "8"])("enabled contract does not accept mismatched, invalid QR, pending or rejected response (%s)", async scenario => {
    const oldFlag = process.env.DOSA_CONFIRMED_DGII_OUTCOMES_ENABLED;
    process.env.DOSA_CONFIRMED_DGII_OUTCOMES_ENABLED = "true";
    try {
      const { tenant, documentId } = await readyCompany(`unconfirmed-${scenario}`, scenario);
      const result = await dispatch(tenant, documentId);
      expect(result.status).toBe(201);
      expect(result.body.confirmedFiscalOutcome).toBe(false);
      const document = await prisma.ecfElectronicDocument.findFirstOrThrow({ where: { companyId: tenant.companyId, id: documentId } });
      expect(document.status).not.toBe("DGII_ACCEPTED");
      expect(document.fiscalSnapshot).toBeNull();
      expect(await prisma.ecfElectronicDocumentStatusLog.count({ where: { companyId: tenant.companyId, documentId,
        reasonCode: "DOSA_CONFIRMED_DGII_ACCEPTED" } })).toBe(0);
    } finally {
      if (oldFlag === undefined) delete process.env.DOSA_CONFIRMED_DGII_OUTCOMES_ENABLED;
      else process.env.DOSA_CONFIRMED_DGII_OUTCOMES_ENABLED = oldFlag;
    }
  });

  it("dos empresas despachan simultáneamente TEST y PRODUCTION con credenciales, numeración y QR propios", async () => {
    const testing = await readyCompany("mixed-test", "1");
    const production = await registerTenant("mixed-production", "2");
    await enableEcf(production);
    // Only this synthetic local company is pre-authorized. The public commercial
    // This fixture isolates mixed-environment dispatch; activation is covered above.
    await prisma.ecfCompanyConfiguration.update({ where: { companyId: production.companyId },
      data: { environment: "PRODUCTION", productionEnabled: true, certificationStatus: "PRODUCTION_READY" } });
    await registerSequence(production);
    const productionKey = "sk_prod_HTTP_MIXED";
    await seedCredentials({ companyId: production.companyId, rnc: production.rnc, apiKeyTest: "sk_test_HTTP_MIXED_UNUSED",
      apiKeyProduccion: productionKey, environment: "production", status: "ACTIVE" });
    const prepareProduction = () => new EcfEmissionService(prisma).prepare({ id: production.userId, companyId: production.companyId, role: "ADMIN" }, {
      document: { ...validE31WithItbis, sender: { ...validE31WithItbis.sender, taxId: production.rnc },
        paymentForms: [{ code: "1", amount: String(validE31WithItbis.totals.total) }] },
      metadata: { paymentType: 1, incomeType: 1, sequenceDueDate: "2028-12-31" },
      sourceType: "MANUAL", clientRequestId: randomUUID(),
    });
    const prepared = await prepareProduction();
    setEnv("DOSA_PRODUCTION_EMISSION_ENABLED", "true");
    // The global legacy selector remains TEST throughout this mixed dispatch.
    await app.close(); await bootApp();
    try {
      requests.length = 0;
      const [testResult, prodResult] = await Promise.all([dispatch(testing.tenant, testing.documentId), dispatch(production, prepared.id)]);
      expect(testResult.body).toMatchObject({ ok: true, environment: "test", correlated: true });
      if (!prodResult.body.ok) throw new Error(`Synthetic production dispatch blocked: ${JSON.stringify(prodResult.body)}`);
      expect(prodResult.body).toMatchObject({ ok: true, environment: "production", correlated: true });
      expect(testResult.body.encf).toBe(prodResult.body.encf);
      expect(requests).toHaveLength(2);
      const keysByRnc = new Map(requests.map(sent => [JSON.parse(sent.body).encabezado.emisor.RNCEmisor, sent.headers["x-api-key"]]));
      expect(keysByRnc.get(testing.tenant.rnc)).toBe(testing.apiKey);
      expect(keysByRnc.get(production.rnc)).toBe(productionKey);
      const testPrint = await http().get(`/ecf/documents/${testing.documentId}/print`).set("Authorization", `Bearer ${testing.tenant.token}`).expect(200);
      const prodPrint = await http().get(`/ecf/documents/${prepared.id}/print`).set("Authorization", `Bearer ${production.token}`).expect(200);
      expect(testPrint.body.document.qrUrl).toContain("/testecf/");
      expect(prodPrint.body.document.qrUrl).toContain("/ecf/");
      await http().get(`/ecf/documents/${prepared.id}/print`).set("Authorization", `Bearer ${testing.tenant.token}`).expect(404);
      const ranges = await prisma.ecfSequence.findMany({ where: { companyId: { in: [production.companyId, testing.tenant.companyId] }, documentType: "E31" } });
      expect(ranges).toHaveLength(2);
      expect(ranges.map(row => row.nextNumber)).toEqual([2, 2]);
      const held = await prepareProduction();
      await prisma.ecfCompanyConfiguration.update({ where: { companyId: production.companyId }, data: { productionEnabled: false } });
      const refused = await dispatch(production, held.id);
      expect(refused.body).toMatchObject({ ok: false, code: "ECF_DOSA_GATE_BLOCKED" });
      expect(refused.body.blockingReasons).toContain("ECF_DOSA_GATE_PRODUCTION_NOT_AUTHORIZED");
      expect(requests).toHaveLength(2);
      expect(await prisma.ecfElectronicDocumentAttempt.count({ where: { companyId: production.companyId, documentId: held.id, operation: "SEND_TO_PROVIDER" } })).toBe(0);
    } finally {
      setEnv("DOSA_PRODUCTION_EMISSION_ENABLED", "false");
      await app.close(); await bootApp();
    }
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
