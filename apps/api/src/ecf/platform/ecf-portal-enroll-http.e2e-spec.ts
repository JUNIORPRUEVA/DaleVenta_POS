import { INestApplication, ValidationPipe } from "@nestjs/common";
import { Test } from "@nestjs/testing";
import { execFileSync } from "node:child_process";
import { readFileSync } from "node:fs";
import { Client } from "pg";
import request from "supertest";

import { AppModule } from "../../app.module";
import { PrismaService } from "../../prisma/prisma.service";
import { resolvePrismaCliPath } from "../../testing/prisma-cli";
import { PLATFORM_STAFF_ENV } from "./platform-staff.guard";

/**
 * E2E HTTP de las rutas de AUTORIZACIÓN del asistente e-CF por empresa.
 *
 * Sustituyen a `ECF_PORTAL_PILOT_COMPANY_IDS`: el alta de un cliente deja de ser
 * una edición del entorno y pasa a ser un registro con autor, motivo y
 * caducidad. Este archivo habla por HTTP real (JWT real, `PlatformStaffGuard`
 * real, `EcfSupportGrantGuard` real, `ValidationPipe` real) contra PostgreSQL
 * desechable, y demuestra:
 *
 *  1. Un administrador de empresa NO puede autorizar a nadie (403).
 *  2. Sin concesión de soporte, el staff tampoco (403).
 *  3. Con concesión, el staff autoriza y la empresa pasa a ser elegible en el
 *     portal — sin tocar ninguna variable de entorno.
 *  4. El motivo es obligatorio (400) y un origen fuera del catálogo se rechaza.
 *  5. Revocar corta el acceso y conserva el histórico.
 *  6. La autorización de una empresa no habilita a otra.
 *
 * No llama a DOSA ni a la DGII: `ALANUBE_ENABLE_REAL_CALLS=false` es obligatorio.
 */
jest.setTimeout(300000);

const PASSWORD = "EcfPortalEnrollHttpE2E123!";
const SAFE_DB = /^fullpos_portal_enroll_http_e2e_/;
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

uat("e-CF autorización del portal — E2E HTTP + PostgreSQL desechable", () => {
  let app: INestApplication;
  let prisma: PrismaService;
  let dbName: string;
  let adminUrl: string;

  const http = () => request(app.getHttpServer());

  beforeAll(async () => {
    if (process.env.ALANUBE_ENABLE_REAL_CALLS !== "false") {
      throw new Error("E2E_REFUSES_REAL_PROVIDER_CALLS");
    }
    const baseUrl = baseDatabaseUrl();
    dbName = `fullpos_portal_enroll_http_e2e_${Date.now()}`;
    adminUrl = replaceDbName(baseUrl, "postgres");
    const appUrl = replaceDbName(baseUrl, dbName);
    if (!SAFE_DB.test(dbName)) throw new Error("Unsafe E2E DB name");

    const admin = new Client({ connectionString: adminUrl });
    await admin.connect();
    await admin.query(`CREATE DATABASE ${dbName}`);
    await admin.end();

    process.env.DATABASE_URL = appUrl;
    process.env.JWT_SECRET =
      process.env.JWT_SECRET || "ecf-portal-enroll-http-e2e-secret";
    process.env[PLATFORM_STAFF_ENV] = "";
    // El portal debe estar APAGADO salvo por la autorización de la base: así se
    // demuestra que la variable de entorno ya no decide nada.
    process.env.ECF_PORTAL_PILOT_COMPANY_IDS = "";
    process.env.ECF_PORTAL_AUTO_ENROLL_ENABLED = "false";

    execFileSync(process.execPath, [resolvePrismaCliPath(), "migrate", "deploy"], {
      cwd: process.cwd(),
      env: { ...process.env, DATABASE_URL: appUrl },
      stdio: "pipe",
    });

    const moduleRef = await Test.createTestingModule({
      imports: [AppModule],
    }).compile();
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

  afterEach(() => {
    process.env[PLATFORM_STAFF_ENV] = "";
  });

  /** Empresa + administrador reales, creados por HTTP. */
  async function registerTenant(suffix: string) {
    const email = `portal-enroll-e2e-${Date.now()}-${suffix}@example.test`;
    const res = await http()
      .post("/auth/register-business")
      .send({
        firstName: "Portal",
        lastName: suffix,
        email,
        phone: "8095550000",
        password: PASSWORD,
        confirmPassword: PASSWORD,
        commercialName: `Portal ${suffix}`,
        taxId: `2${Date.now().toString().slice(-8)}`,
        businessPhone: "8095551111",
        address: `Calle Sintética ${suffix}`,
        country: "DO",
      })
      .expect(201);
    return {
      email,
      token: res.body.accessToken as string,
      userId: res.body.user.id as string,
      companyId: res.body.activeCompany.id as string,
    };
  }

  function setStaff(...userIds: string[]) {
    process.env[PLATFORM_STAFF_ENV] = userIds.join(",");
  }

  /** El cliente autoriza asistencia de plataforma (endpoint real del cliente). */
  async function grantSupport(token: string) {
    await http()
      .post("/ecf/dgii/support-grants")
      .set("Authorization", `Bearer ${token}`)
      .send({
        scopes: ["VIEW_DOSSIER", "REVIEW_EVIDENCE", "REQUEST_CORRECTION"],
        expiresAt: new Date(Date.now() + 7 * 24 * 60 * 60 * 1000).toISOString(),
        reason: "UAT: asistencia de plataforma",
      })
      .expect(201);
  }

  function grantUrl(companyId: string) {
    return `/ecf/platform/dosa/portal-enrollments/${companyId}/grant`;
  }

  function revokeUrl(companyId: string) {
    return `/ecf/platform/dosa/portal-enrollments/${companyId}/revoke`;
  }

  it("un administrador de empresa no puede autorizar el asistente (403)", async () => {
    const tenant = await registerTenant("tenant");
    await http()
      .post(grantUrl(tenant.companyId))
      .set("Authorization", `Bearer ${tenant.token}`)
      .send({ source: "ADMIN_AUTHORIZATION", reason: "Intento de autoconcesión" })
      .expect(403);
  });

  it("sin concesión de soporte, el personal de plataforma tampoco (403)", async () => {
    const tenant = await registerTenant("nogr");
    const staff = await registerTenant("staff");
    setStaff(staff.userId);

    await http()
      .post(grantUrl(tenant.companyId))
      .set("Authorization", `Bearer ${staff.token}`)
      .send({ source: "ADMIN_AUTHORIZATION", reason: "Sin concesión del cliente" })
      .expect(403);
  });

  it("con concesión, el staff autoriza y la empresa entra al portal sin tocar el entorno", async () => {
    const tenant = await registerTenant("grant");
    const staff = await registerTenant("staffok");
    await grantSupport(tenant.token);
    setStaff(staff.userId);

    // Antes: no elegible (la lista de entorno está vacía a propósito).
    const before = await http()
      .get("/ecf/certification-portal/eligibility")
      .set("Authorization", `Bearer ${tenant.token}`)
      .expect(200);
    expect(before.body.eligible).toBe(false);

    const granted = await http()
      .post(grantUrl(tenant.companyId))
      .set("Authorization", `Bearer ${staff.token}`)
      .send({
        source: "ADMIN_AUTHORIZATION",
        reason: "Alta comercial autorizada por dirección",
        contractReference: "CTR-2026-E2E-001",
      })
      .expect(201);
    expect(granted.body.created).toBe(true);
    expect(typeof granted.body.enrollmentId).toBe("string");

    // Después: elegible, y por la razón correcta.
    const after = await http()
      .get("/ecf/certification-portal/eligibility")
      .set("Authorization", `Bearer ${tenant.token}`)
      .expect(200);
    expect(after.body.eligible).toBe(true);
    expect(after.body.reason).toBe("ENROLLED");

    // La fila existe con autor y motivo.
    const row = await prisma.ecfPortalEnrollment.findFirst({
      where: { companyId: tenant.companyId },
    });
    expect(row).toMatchObject({
      status: "ACTIVE",
      source: "ADMIN_AUTHORIZATION",
      contractReference: "CTR-2026-E2E-001",
      authorizedByUserId: staff.userId,
    });
  });

  it("autorizar dos veces no duplica la vigente", async () => {
    const tenant = await registerTenant("idem");
    const staff = await registerTenant("staffidem");
    await grantSupport(tenant.token);
    setStaff(staff.userId);

    const first = await http()
      .post(grantUrl(tenant.companyId))
      .set("Authorization", `Bearer ${staff.token}`)
      .send({ source: "ADMIN_AUTHORIZATION", reason: "Primera autorización" })
      .expect(201);
    const second = await http()
      .post(grantUrl(tenant.companyId))
      .set("Authorization", `Bearer ${staff.token}`)
      .send({ source: "CONTRACT_REFERENCE", reason: "Segunda autorización" })
      .expect(201);

    expect(first.body.created).toBe(true);
    expect(second.body.created).toBe(false);
    expect(await prisma.ecfPortalEnrollment.count({
      where: { companyId: tenant.companyId },
    })).toBe(1);
  });

  it("el motivo es obligatorio y el origen debe estar en el catálogo", async () => {
    const tenant = await registerTenant("valida");
    const staff = await registerTenant("staffvalida");
    await grantSupport(tenant.token);
    setStaff(staff.userId);

    await http()
      .post(grantUrl(tenant.companyId))
      .set("Authorization", `Bearer ${staff.token}`)
      .send({ source: "ADMIN_AUTHORIZATION", reason: "corto" })
      .expect(400);

    await http()
      .post(grantUrl(tenant.companyId))
      .set("Authorization", `Bearer ${staff.token}`)
      .send({ source: "AUTO_ELIGIBLE", reason: "Origen reservado al sistema" })
      .expect(400);

    expect(await prisma.ecfPortalEnrollment.count({
      where: { companyId: tenant.companyId },
    })).toBe(0);
  });

  it("revocar corta el acceso y conserva el histórico", async () => {
    const tenant = await registerTenant("revoke");
    const staff = await registerTenant("staffrevoke");
    await grantSupport(tenant.token);
    setStaff(staff.userId);

    await http()
      .post(grantUrl(tenant.companyId))
      .set("Authorization", `Bearer ${staff.token}`)
      .send({ source: "ADMIN_AUTHORIZATION", reason: "Autorización inicial" })
      .expect(201);

    await http()
      .post(revokeUrl(tenant.companyId))
      .set("Authorization", `Bearer ${staff.token}`)
      .send({ reason: "Baja solicitada por el cliente" })
      .expect(201);

    const eligibility = await http()
      .get("/ecf/certification-portal/eligibility")
      .set("Authorization", `Bearer ${tenant.token}`)
      .expect(200);
    expect(eligibility.body.eligible).toBe(false);
    expect(eligibility.body.reason).toBe("AUTHORIZATION_REVOKED");

    // La fila sigue ahí, revocada y explicada.
    const rows = await prisma.ecfPortalEnrollment.findMany({
      where: { companyId: tenant.companyId },
    });
    expect(rows).toHaveLength(1);
    expect(rows[0]).toMatchObject({
      status: "REVOKED",
      revocationReason: "Baja solicitada por el cliente",
    });
  });

  it("la autorización de una empresa no habilita a otra", async () => {
    const companyA = await registerTenant("iso-a");
    const companyB = await registerTenant("iso-b");
    const staff = await registerTenant("staffiso");
    await grantSupport(companyA.token);
    await grantSupport(companyB.token);
    setStaff(staff.userId);

    await http()
      .post(grantUrl(companyA.companyId))
      .set("Authorization", `Bearer ${staff.token}`)
      .send({ source: "ADMIN_AUTHORIZATION", reason: "Autorización de A" })
      .expect(201);

    const eligibilityB = await http()
      .get("/ecf/certification-portal/eligibility")
      .set("Authorization", `Bearer ${companyB.token}`)
      .expect(200);
    expect(eligibilityB.body.eligible).toBe(false);
    expect(eligibilityB.body.reason).toBe("NO_AUTHORIZATION");
  });

  it("la consulta de estado devuelve la decisión y el histórico", async () => {
    const tenant = await registerTenant("estado");
    const staff = await registerTenant("staffestado");
    await grantSupport(tenant.token);
    setStaff(staff.userId);

    await http()
      .post(grantUrl(tenant.companyId))
      .set("Authorization", `Bearer ${staff.token}`)
      .send({ source: "CONTRACT_REFERENCE", reason: "Contrato firmado" })
      .expect(201);

    const status = await http()
      .get(`/ecf/platform/dosa/portal-enrollments/${tenant.companyId}`)
      .set("Authorization", `Bearer ${staff.token}`)
      .expect(200);

    expect(status.body.eligibility).toMatchObject({
      eligible: true,
      reason: "ENROLLED",
      companyId: tenant.companyId,
      legacy: false,
    });
    expect(status.body.history).toHaveLength(1);
    expect(status.body.history[0].source).toBe("CONTRACT_REFERENCE");
  });
});
