import { INestApplication, ValidationPipe } from "@nestjs/common";
import { Test } from "@nestjs/testing";
import { randomUUID } from "node:crypto";
import { execFileSync } from "node:child_process";
import { existsSync, readFileSync } from "node:fs";
import { resolve } from "node:path";
import { Client } from "pg";
import request from "supertest";

import { AppModule } from "../../app.module";
import { PrismaService } from "../../prisma/prisma.service";
import { ECF_DOSA_SESSION_CLIENT } from "../provider/dosa/dosa-certification-session.service";
import type { DosaSessionClientPort } from "../provider/dosa/dosa-certification-session.service";

/**
 * E2E HTTP real del modo de integración declarado y del boleto del portal.
 *
 * PostgreSQL desechable, JWT real y proveedor DOSA SIMULADO: no hay llamadas
 * externas ni emisión. Se ejecuta con `ECF_POSTGRES_UAT=true` y
 * `ALANUBE_ENABLE_REAL_CALLS=false`.
 *
 * Demuestra, sobre el camino que rompió producción:
 *  1. Con la apertura privada apagada el estado declara
 *     `certificationMode: PUBLIC_PORTAL` y el proveedor NO se llama.
 *  2. Registrar la intención crea el Intento 1 y no abre sesión privada.
 *  3. El boleto se crea (201) y se canjea UNA sola vez (201) devolviendo el
 *     contexto de la empresa y el Intento 1.
 *  4. Un segundo canje del mismo boleto se rechaza.
 *  5. El boleto no crea postulación de proveedor: `NOT_STARTED`, sin
 *     `providerPostulationId`.
 */
jest.setTimeout(300000);

const PASSWORD = "PortalTicketE2E123!";
const SAFE_DB = /^fullpos_portal_ticket_e2e_/;
const uat = process.env.ECF_POSTGRES_UAT === "true" ? describe : describe.skip;

function baseDatabaseUrl() {
  const envUrl = process.env.DATABASE_URL?.trim();
  if (envUrl) return envUrl;
  const raw = readFileSync(".env", "utf8");
  const line = raw
    .split(/\r?\n/)
    .find((entry) => entry.startsWith("DATABASE_URL="));
  if (!line) throw new Error("DATABASE_URL missing");
  return line.slice("DATABASE_URL=".length).trim();
}

function replaceDbName(url: string, dbName: string) {
  const parsed = new URL(url);
  parsed.pathname = `/${dbName}`;
  return parsed.toString();
}

function prismaCliPath(): string {
  const candidates = [
    resolve(process.cwd(), "node_modules", "prisma", "build", "index.js"),
    resolve(process.cwd(), "..", "..", "node_modules", "prisma", "build", "index.js"),
  ];
  const found = candidates.find((candidate) => existsSync(candidate));
  if (!found) throw new Error("PRISMA_CLI_NOT_FOUND");
  return found;
}

uat("Portal de certificación — boleto real de un solo uso", () => {
  let app: INestApplication;
  let prisma: PrismaService;
  let dbName: string;
  let adminUrl: string;
  const createSession = jest.fn();

  const http = () => request(app.getHttpServer());

  beforeAll(async () => {
    if (process.env.ALANUBE_ENABLE_REAL_CALLS !== "false") {
      throw new Error("E2E_REFUSES_REAL_PROVIDER_CALLS");
    }
    const base = baseDatabaseUrl();
    dbName = `fullpos_portal_ticket_e2e_${Date.now()}`;
    if (!SAFE_DB.test(dbName)) throw new Error("Unsafe E2E DB name");
    adminUrl = replaceDbName(base, "postgres");
    const appUrl = replaceDbName(base, dbName);

    const admin = new Client({ connectionString: adminUrl });
    await admin.connect();
    await admin.query(`CREATE DATABASE ${dbName}`);
    await admin.end();

    process.env.DATABASE_URL = appUrl;
    process.env.JWT_SECRET = process.env.JWT_SECRET || "portal-ticket-e2e-secret";
    // Producción: apertura privada APAGADA (modo portal público).
    process.env.DOSA_CERTIFICATION_SESSIONS_ENABLED = "false";
    process.env.DOSA_EMISSION_ENABLED = "false";
    process.env.DOSA_PRODUCTION_EMISSION_ENABLED = "false";
    process.env.DOSA_WEBHOOK_ENABLED = "false";

    execFileSync(process.execPath, [prismaCliPath(), "migrate", "deploy"], {
      cwd: process.cwd(),
      env: { ...process.env, DATABASE_URL: appUrl },
      stdio: "pipe",
    });

    const fakeClient: DosaSessionClientPort = {
      describeReadiness: () => ({
        ready: false,
        blockingReasons: ["DOSA_CERTIFICATION_SESSIONS_DISABLED"],
      }),
      createSession,
    };

    const moduleRef = await Test.createTestingModule({ imports: [AppModule] })
      .overrideProvider(ECF_DOSA_SESSION_CLIENT)
      .useValue(fakeClient)
      .compile();
    app = moduleRef.createNestApplication();
    app.useGlobalPipes(
      new ValidationPipe({
        whitelist: true,
        forbidNonWhitelisted: true,
        transform: true,
      }),
    );
    await app.init();
    prisma = app.get(PrismaService);
  }, 300000);

  afterAll(async () => {
    if (app) await app.close();
    if (adminUrl && dbName && SAFE_DB.test(dbName)) {
      const admin = new Client({ connectionString: adminUrl });
      await admin.connect();
      await admin.query(
        `SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = $1 AND pid <> pg_backend_pid()`,
        [dbName],
      );
      await admin.query(`DROP DATABASE IF EXISTS ${dbName}`);
      await admin.end();
    }
  }, 120000);

  let token = "";
  let companyId = "";

  it("registra la empresa administradora", async () => {
    const email = `portal-ticket-${Date.now()}-${randomUUID().slice(0, 6)}@example.test`;
    const res = await http()
      .post("/auth/register-business")
      .send({
        firstName: "Portal",
        lastName: "Ticket",
        email,
        phone: "8095550000",
        password: PASSWORD,
        confirmPassword: PASSWORD,
        commercialName: "PORTAL TICKET E2E",
        taxId: `1${Date.now().toString().slice(-8)}`,
        businessPhone: "8095551111",
        address: "Av. Sintética 1",
        country: "DO",
      })
      .expect(201);
    token = res.body.accessToken as string;
    // El portal está cerrado por defecto: esta empresa entra al piloto.
    // El portal está cerrado por defecto: esta empresa entra al piloto.
    process.env.ECF_PORTAL_PILOT_COMPANY_IDS = res.body.activeCompany.id as string;
    companyId = res.body.activeCompany.id as string;
    expect(token.length).toBeGreaterThan(20);
  }, 120000);

  it("el estado declara PUBLIC_PORTAL sin llamar al proveedor", async () => {
    await prisma.appConfig.upsert({
      where: { companyId },
      create: {
        id: companyId,
        companyId,
        companyName: "PORTAL TICKET E2E",
        rnc: `1${Date.now().toString().slice(-8)}`,
        ecfContactEmail: "factura-portal@example.test",
      },
      update: { ecfContactEmail: "factura-portal@example.test" },
    });

    const res = await http()
      .get("/ecf/dosa/certification-intent")
      .set("Authorization", `Bearer ${token}`)
      .expect(200);
    expect(res.body.certificationMode).toBe("PUBLIC_PORTAL");
    expect(createSession).not.toHaveBeenCalled();
  }, 120000);

  it("registra la intención (Preparar certificación) sin abrir sesión privada", async () => {
    const res = await http()
      .post("/ecf/dosa/certification-intent")
      .set("Authorization", `Bearer ${token}`)
      .send({})
      .expect(200);
    expect(res.body.sessionId).toBeTruthy();
    expect(res.body.provider).toBe("DOSA");
    expect(createSession).not.toHaveBeenCalled();

    const state = await http()
      .get("/ecf/dosa/certification-intent")
      .set("Authorization", `Bearer ${token}`)
      .expect(200);
    expect(state.body.session?.id).toBe(res.body.sessionId);
    expect(state.body.certificationMode).toBe("PUBLIC_PORTAL");
    // Sin la autorización histórica no hay bloqueo: el expediente es nuevo.
    expect(state.body.historicalReviewRequired).toBe(false);
  }, 120000);

  let ticket = "";
  let portalToken = "";

  it("crea un boleto de un solo uso (201)", async () => {
    const res = await http()
      .post("/ecf/certification-portal/tickets")
      .set("Authorization", `Bearer ${token}`)
      .expect(201);
    ticket = res.body.ticket as string;
    expect(typeof ticket).toBe("string");
    expect(ticket.length).toBeGreaterThan(20);
    expect(res.body.ticketTtlSeconds).toBe(120);
  }, 120000);

  it("canjea el boleto una sola vez y devuelve la sesión del portal", async () => {
    const res = await http()
      .post("/ecf/certification-portal/sessions")
      .send({ ticket })
      .expect(201);
    portalToken = res.body.token as string;
    expect(typeof portalToken).toBe("string");
    expect(portalToken.length).toBeGreaterThan(20);
    // El contexto confirma la empresa del boleto y el Intento 1 sin abrir nada.
    expect(res.body.context?.company?.id).toBe(companyId);
    expect(res.body.context?.postulation?.attemptNo).toBe(1);
    expect(res.body.context?.ecfEnabled).toBe(false);

    const context = await http()
      .get("/ecf/certification-portal/context")
      .set("x-fullpos-portal", portalToken)
      .expect(200);
    expect(context.body.ok).toBe(true);
  }, 120000);

  it("rechaza el segundo canje del mismo boleto", async () => {
    const res = await http()
      .post("/ecf/certification-portal/sessions")
      .send({ ticket });
    expect(res.status).toBeGreaterThanOrEqual(400);
    expect(res.status).toBeLessThan(500);
  }, 120000);

  it("no se creó ninguna sesión privada ni postulación", async () => {
    expect(createSession).not.toHaveBeenCalled();
    // Un solo Intento 1, sin referencia de proveedor ni URL de sesión: el
    // boleto del portal no abre nada por sí mismo.
    const rows = await prisma.ecfDosaCertificationSession.findMany({
      where: { companyId },
    });
    expect(rows).toHaveLength(1);
    expect(rows[0].attemptNo).toBe(1);
    expect(rows[0].status).toBe("NOT_STARTED");
    expect(rows[0].providerPostulationId ?? null).toBeNull();
  }, 120000);
});
