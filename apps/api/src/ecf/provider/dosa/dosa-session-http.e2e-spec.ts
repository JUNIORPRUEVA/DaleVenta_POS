import { INestApplication, ValidationPipe } from "@nestjs/common";
import { Test } from "@nestjs/testing";
import { randomUUID } from "node:crypto";
import { execFileSync } from "node:child_process";
import { existsSync, readFileSync } from "node:fs";
import { resolve } from "node:path";
import { Client } from "pg";
import request from "supertest";

import { AppModule } from "../../../app.module";
import { PrismaService } from "../../../prisma/prisma.service";
import { ECF_DOSA_SESSION_CLIENT } from "./dosa-certification-session.service";
import type { DosaSessionClientPort } from "./dosa-certification-session.service";

/**
 * E2E HTTP real de la apertura de sesiones DOSA, con PostgreSQL desechable y
 * proveedor DOSA SIMULADO. No hay llamadas externas ni emisión.
 *
 * Cubre:
 *  - sesión creada por HTTP con JWT real;
 *  - URL cifrada en reposo y devuelta descifrada solo a la empresa;
 *  - expediente reconciliado bloqueado sin autorización;
 *  - autorización explícita auditada que desbloquea UNA transición;
 *  - el Intento 1 conserva su historial y no se crea un segundo intento.
 */
jest.setTimeout(300000);

const PASSWORD = "DosaSessionE2E123!";
const SAFE_DB = /^fullpos_dosa_session_e2e_/;
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
    resolve(
      process.cwd(),
      "..",
      "..",
      "node_modules",
      "prisma",
      "build",
      "index.js",
    ),
  ];
  const found = candidates.find((candidate) => existsSync(candidate));
  if (!found) throw new Error("PRISMA_CLI_NOT_FOUND");
  return found;
}

uat("Sesiones DOSA — E2E HTTP con PostgreSQL desechable", () => {
  let app: INestApplication;
  let prisma: PrismaService;
  let dbName: string;
  let appUrl: string;
  let adminUrl: string;
  const createSession = jest.fn();

  const http = () => request(app.getHttpServer());

  beforeAll(async () => {
    if (process.env.ALANUBE_ENABLE_REAL_CALLS !== "false") {
      throw new Error("E2E_REFUSES_REAL_PROVIDER_CALLS");
    }
    const base = baseDatabaseUrl();
    dbName = `fullpos_dosa_session_e2e_${Date.now()}`;
    if (!SAFE_DB.test(dbName)) throw new Error("Unsafe E2E DB name");
    adminUrl = replaceDbName(base, "postgres");
    appUrl = replaceDbName(base, dbName);

    const admin = new Client({ connectionString: adminUrl });
    await admin.connect();
    await admin.query(`CREATE DATABASE ${dbName}`);
    await admin.end();

    process.env.DATABASE_URL = appUrl;
    process.env.JWT_SECRET =
      process.env.JWT_SECRET || "dosa-session-http-e2e-secret";
    process.env.DOSA_CERTIFICATION_SESSIONS_ENABLED = "true";
    process.env.DOSA_SECRET_KEY = "sk_e2e_test_key";
    process.env.DOSA_SESSION_BASE_URL = "https://dosasystem.test";
    process.env.DOSA_SESSION_URL_KEYS = `1:${Buffer.alloc(32, 9).toString("base64")}`;
    process.env.ECF_DOSA_HISTORICAL_TRANSITION_ENABLED = "true";

    execFileSync(process.execPath, [prismaCliPath(), "migrate", "deploy"], {
      cwd: process.cwd(),
      env: { ...process.env, DATABASE_URL: appUrl },
      stdio: "pipe",
    });

    const fakeClient: DosaSessionClientPort = {
      describeReadiness: () => ({ ready: true, blockingReasons: [] }),
      createSession,
    };

    const moduleRef = await Test.createTestingModule({
      imports: [AppModule],
    })
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

  beforeEach(() => {
    createSession.mockReset();
    createSession.mockResolvedValue({
      ok: true,
      status: 201,
      session: {
        url: "https://dosasystem.test/sesion/e2e",
        path: "/sesion/e2e",
        token: "token-e2e-12345678",
        expiresAt: new Date(Date.now() + 60 * 60 * 1000).toISOString(),
        postulacionId: "post-e2e",
        prueba: true,
      },
    });
  });

  async function registerTenant(suffix: string) {
    const email = `dosa-session-${Date.now()}-${suffix}-${randomUUID().slice(0, 6)}@example.test`;
    const res = await http()
      .post("/auth/register-business")
      .send({
        firstName: "Dosa",
        lastName: suffix,
        email,
        phone: "8095550000",
        password: PASSWORD,
        confirmPassword: PASSWORD,
        commercialName: `DOSA ${suffix}`,
        taxId: `1${Date.now().toString().slice(-8)}`,
        businessPhone: "8095551111",
        address: `Av. Sintética ${suffix}`,
        country: "DO",
      })
      .expect(201);
    return {
      token: res.body.accessToken as string,
      userId: res.body.user.id as string,
      companyId: res.body.activeCompany.id as string,
    };
  }

  async function seedCompanyConfig(
    companyId: string,
    suffix: string,
  ) {
    const rnc = `1${Date.now().toString().slice(-8)}`;
    await prisma.appConfig.upsert({
      where: { companyId },
      create: {
        id: companyId,
        companyId,
        companyName: `DOSA ${suffix}`,
        rnc,
        ecfContactEmail: `factura-${suffix}@example.test`,
      },
      update: {
        companyName: `DOSA ${suffix}`,
        rnc,
        ecfContactEmail: `factura-${suffix}@example.test`,
      },
    });
    return rnc;
  }

  it("crea la sesión, la guarda cifrada y devuelve la URL a su empresa", async () => {
    const tenant = await registerTenant("ok");
    await seedCompanyConfig(tenant.companyId, "ok");

    const res = await http()
      .post("/ecf/dosa/certification-session")
      .set("Authorization", `Bearer ${tenant.token}`)
      .expect(200);

    expect(res.body).toMatchObject({
      ok: true,
      companyId: tenant.companyId,
      sessionUrl: "https://dosasystem.test/sesion/e2e",
      providerPostulationId: "post-e2e",
      reused: false,
      fiscalAuthorizationGranted: false,
    });

    const row = await prisma.ecfDosaCertificationSession.findFirstOrThrow({
      where: { companyId: tenant.companyId },
    });
    expect(row.sessionUrl?.startsWith("fpv1:")).toBe(true);
    expect(row.sessionUrl).not.toContain("dosasystem.test");
    expect(row.status).toBe("RUNNING");

    const intent = await http()
      .get("/ecf/dosa/certification-intent")
      .set("Authorization", `Bearer ${tenant.token}`)
      .expect(200);
    // El estado informa de la presencia, nunca de la URL ni del criptograma.
    expect(intent.body.session?.sessionUrl).toBeNull();
    expect(JSON.stringify(intent.body)).not.toContain("dosasystem.test");
    expect(JSON.stringify(intent.body)).not.toContain("fpv1:");
  });

  it("bloquea el expediente reconciliado, autoriza y conserva su historial", async () => {
    const tenant = await registerTenant("reconciled");
    const rnc = await seedCompanyConfig(tenant.companyId, "reconciled");
    const intentId = randomUUID();
    await prisma.ecfDosaCertificationSession.create({
      data: {
        id: intentId,
        companyId: tenant.companyId,
        rnc,
        attemptNo: 1,
        activeKey: `${tenant.companyId}:${rnc}`,
        status: "NOT_STARTED",
        createdByUserId: tenant.userId,
      },
    });
    await prisma.ecfAuditLog.create({
      data: {
        companyId: tenant.companyId,
        actorUserId: tenant.userId,
        action: "INTENT_PROVIDER_RECONCILED",
        targetType: "DOSA_CERTIFICATION_INTENT",
        targetId: intentId,
        metadata: {
          provider: "DOSA",
          attemptNo: 1,
          rnc,
        },
        before: { provider: "ALANUBE" },
        after: { provider: "DOSA" },
      },
    });
    const before = await prisma.ecfDosaCertificationSession.findUniqueOrThrow({
      where: { id: intentId },
    });

    await http()
      .post("/ecf/dosa/certification-session")
      .set("Authorization", `Bearer ${tenant.token}`)
      .expect(409)
      .expect((response) => {
        expect(response.body.message).toBe(
          "ECF_DOSA_SESSION_HISTORICAL_REVIEW_REQUIRED",
        );
      });
    const afterBlocked =
      await prisma.ecfDosaCertificationSession.findUniqueOrThrow({
        where: { id: intentId },
      });
    expect(afterBlocked.updatedAt.getTime()).toBe(before.updatedAt.getTime());
    expect(afterBlocked.status).toBe("NOT_STARTED");

    process.env.ECF_PORTAL_PILOT_COMPANY_IDS = tenant.companyId;
    const authorization = await http()
      .post("/ecf/dosa/certification-intent/authorize-historical-transition")
      .set("Authorization", `Bearer ${tenant.token}`)
      .send({
        intentId,
        ownerApprovalReference: "ACTA-UAT-2026-001",
        reason: "Revisión interna autorizada para iniciar la transición.",
        confirmation: "AUTHORIZE_HISTORICAL_TRANSITION",
      })
      .expect(200);
    expect(authorization.body).toMatchObject({
      ok: true,
      intentId,
      attemptNo: 1,
      ttlHours: 24,
      fiscalAuthorizationGranted: false,
    });

    const session = await http()
      .post("/ecf/dosa/certification-session")
      .set("Authorization", `Bearer ${tenant.token}`)
      .expect(200);
    expect(session.body.sessionUrl).toBe(
      "https://dosasystem.test/sesion/e2e",
    );

    const rows = await prisma.$queryRaw<
      Array<{ id: string; attempt_no: number; status: string; session_url: string | null }>
    >`
      SELECT "id", "attempt_no", "status", "session_url"
        FROM "ecf_dosa_certification_sessions"
       WHERE "company_id" = ${tenant.companyId}::uuid
    `;
    expect(rows).toHaveLength(1);
    expect(rows[0].id).toBe(intentId);
    expect(rows[0].attempt_no).toBe(1);
    expect(rows[0].status).toBe("RUNNING");
    expect(rows[0].session_url?.startsWith("fpv1:")).toBe(true);

    const history = await prisma.ecfAuditLog.findMany({
      where: { companyId: tenant.companyId, targetId: intentId },
      orderBy: { createdAt: "asc" },
    });
    expect(history.map((entry) => entry.action)).toEqual(
      expect.arrayContaining([
        "INTENT_PROVIDER_RECONCILED",
        "INTENT_HISTORICAL_TRANSITION_AUTHORIZED",
      ]),
    );
  });

  it("no crea una segunda autorización vigente", async () => {
    const tenant = await registerTenant("double");
    const rnc = await seedCompanyConfig(tenant.companyId, "double");
    const intentId = randomUUID();
    await prisma.ecfDosaCertificationSession.create({
      data: {
        id: intentId,
        companyId: tenant.companyId,
        rnc,
        attemptNo: 1,
        activeKey: `${tenant.companyId}:${rnc}`,
        status: "NOT_STARTED",
        createdByUserId: tenant.userId,
      },
    });
    await prisma.ecfAuditLog.create({
      data: {
        companyId: tenant.companyId,
        actorUserId: tenant.userId,
        action: "INTENT_PROVIDER_RECONCILED",
        targetType: "DOSA_CERTIFICATION_INTENT",
        targetId: intentId,
        metadata: { provider: "DOSA" },
      },
    });
    process.env.ECF_PORTAL_PILOT_COMPANY_IDS = tenant.companyId;
    const payload = {
      intentId,
      ownerApprovalReference: "ACTA-UAT-2026-002",
      reason: "Primera autorización controlada del expediente histórico.",
      confirmation: "AUTHORIZE_HISTORICAL_TRANSITION",
    };
    await http()
      .post("/ecf/dosa/certification-intent/authorize-historical-transition")
      .set("Authorization", `Bearer ${tenant.token}`)
      .send(payload)
      .expect(200);

    await http()
      .post("/ecf/dosa/certification-intent/authorize-historical-transition")
      .set("Authorization", `Bearer ${tenant.token}`)
      .send(payload)
      .expect(409)
      .expect((response) => {
        expect(response.body.message).toBe(
          "DOSA_HISTORICAL_TRANSITION_ALREADY_AUTHORIZED",
        );
      });
  });
});
