import { INestApplication, ValidationPipe } from "@nestjs/common";
import { Test } from "@nestjs/testing";
import { EcfAuditAction } from "@prisma/client";
import { execFileSync } from "node:child_process";
import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { Client } from "pg";
import request from "supertest";
import { AppModule } from "../../app.module";
import { PrismaService } from "../../prisma/prisma.service";

/**
 * E2E HTTP de la etapa V del instructivo de certificación: `ROLE_ASSIGNMENT`.
 *
 * Lo que este archivo demuestra:
 *  - El paso aparece como responsabilidad del CLIENTE y el motor no lo ejecuta.
 *  - Sin evidencia NO se puede dar por resuelto (ni `COMPLETED` ni `CONFIRMED`).
 *  - Con evidencia oficial sí, y queda auditado.
 *  - El aislamiento multiempresa se mantiene: cada empresa solo toca su fila.
 *  - Ni con el paso resuelto se puede declarar la empresa certificada: la
 *    autorización oficial sigue siendo un hecho externo.
 *
 * Se levanta la aplicación completa contra una base desechable propia.
 */
jest.setTimeout(300000);

const PASSWORD = "EcfRoleAssignmentE2E123!";
const SAFE_DB = /^fullpos_role_assignment_e2e_/;

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

uat("etapa V — asignación de roles (ROLE_ASSIGNMENT)", () => {
  let app: INestApplication;
  let prisma: PrismaService;
  let dbName: string;
  let adminUrl: string;
  let appUrl: string;

  const http = () => request(app.getHttpServer());

  beforeAll(async () => {
    if (process.env.ALANUBE_ENABLE_REAL_CALLS !== "false") {
      throw new Error("E2E_REFUSES_REAL_PROVIDER_CALLS");
    }
    const baseUrl = baseDatabaseUrl();
    dbName = `fullpos_role_assignment_e2e_${Date.now()}`;
    adminUrl = replaceDbName(baseUrl, "postgres");
    appUrl = replaceDbName(baseUrl, dbName);
    if (!SAFE_DB.test(dbName)) throw new Error("Unsafe E2E DB name");

    const admin = new Client({ connectionString: adminUrl });
    await admin.connect();
    await admin.query(`CREATE DATABASE ${dbName}`);
    await admin.end();

    process.env.DATABASE_URL = appUrl;
    process.env.JWT_SECRET =
      process.env.JWT_SECRET || "ecf-role-assignment-e2e-secret";

    const prismaCli = resolve(
      process.cwd(),
      "..",
      "..",
      "node_modules",
      "prisma",
      "build",
      "index.js",
    );
    execFileSync(process.execPath, [prismaCli, "migrate", "deploy"], {
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

  async function registerTenant(suffix: string) {
    const email = `role-e2e-${Date.now()}-${suffix}@example.test`;
    const res = await http()
      .post("/auth/register-business")
      .send({
        firstName: "Role",
        lastName: suffix,
        email,
        phone: "8095550000",
        password: PASSWORD,
        confirmPassword: PASSWORD,
        commercialName: `Role ${suffix}`,
        taxId: `1${Date.now().toString().slice(-8)}`,
        businessPhone: "8095551111",
        address: `Calle Sintética ${suffix}`,
        country: "DO",
      })
      .expect(201);
    return {
      email,
      token: res.body.accessToken as string,
      companyId: res.body.activeCompany.id as string,
    };
  }

  const auth = (token: string) => ({ Authorization: `Bearer ${token}` });

  /** Registra una evidencia y devuelve su id. */
  async function registerEvidence(
    token: string,
    source: "MANUAL_DECLARATION" | "OFFICIAL_DOCUMENT" | "PROVIDER_ARTIFACT",
    kind: string,
  ): Promise<string> {
    const res = await http()
      .post("/ecf/dgii/evidence")
      .set(auth(token))
      .send({
        source,
        kind,
        storageRef: `uat://role-assignment/${kind.toLowerCase()}-${Date.now()}`,
        fileName: `${kind}.pdf`,
        mimeType: "application/pdf",
        description: "Evidencia sintética de UAT",
      })
      .expect(201);
    return (res.body.id ?? res.body.evidence?.id) as string;
  }

  async function stepOf(companyId: string) {
    return prisma.ecfOnboardingStep.findFirst({
      where: { companyId, stepKey: "ROLE_ASSIGNMENT" as never },
    });
  }

  describe("visibilidad y responsabilidad", () => {
    it("aparece en la activación como paso del CLIENTE y no ejecutable", async () => {
      const tenant = await registerTenant("visible");
      const res = await http()
        .get("/ecf/dgii/activation")
        .set(auth(tenant.token))
        .expect(200);

      const step = res.body.steps.find(
        (item: { key: string }) => item.key === "ROLE_ASSIGNMENT",
      );
      expect(step).toBeDefined();
      expect(step.className).toBe("CLIENT_ACTION");
      expect(step.executable).toBe(false);
      expect(step.awaiting).toBeTruthy();
    });
  });

  describe("evidencia obligatoria", () => {
    it("rechaza COMPLETED sin evidencia", async () => {
      const tenant = await registerTenant("sin-evidencia-completed");
      const res = await http()
        .patch("/ecf/onboarding/steps/ROLE_ASSIGNMENT")
        .set(auth(tenant.token))
        .send({ status: "COMPLETED" })
        .expect(400);
      expect(String(res.body.message)).toContain("Oficina Virtual");

      const row = await stepOf(tenant.companyId);
      expect(row?.status).not.toBe("COMPLETED");
    });

    it("rechaza CONFIRMED sin evidencia", async () => {
      const tenant = await registerTenant("sin-evidencia-confirmed");
      await http()
        .patch("/ecf/onboarding/steps/ROLE_ASSIGNMENT")
        .set(auth(tenant.token))
        .send({ status: "CONFIRMED" })
        .expect(400);

      const row = await stepOf(tenant.companyId);
      expect(row?.status).not.toBe("CONFIRMED");
    });

    it("exige autenticación para tocar el paso", async () => {
      await http()
        .patch("/ecf/onboarding/steps/ROLE_ASSIGNMENT")
        .send({ status: "COMPLETED" })
        .expect(401);
    });

    it("acepta el paso con evidencia oficial y lo deja auditado", async () => {
      const tenant = await registerTenant("con-evidencia");
      const evidenceId = await registerEvidence(
        tenant.token,
        "OFFICIAL_DOCUMENT",
        "OFV_ROLE_ACCEPTANCE",
      );

      const res = await http()
        .patch("/ecf/onboarding/steps/ROLE_ASSIGNMENT")
        .set(auth(tenant.token))
        .send({ status: "CONFIRMED", evidenceId })
        .expect(200);
      expect(res.body.status).toBe("CONFIRMED");

      const row = await stepOf(tenant.companyId);
      expect(row?.status).toBe("CONFIRMED");
      expect(row?.evidenceId).toBe(evidenceId);

      const audits = await prisma.ecfAuditLog.findMany({
        where: {
          companyId: tenant.companyId,
          action: EcfAuditAction.STEP_UPDATED,
        },
      });
      const audited = audits.some((entry) =>
        JSON.stringify(entry.after ?? {}).includes("ROLE_ASSIGNMENT"),
      );
      expect(audited).toBe(true);
    });
  });

  describe("aislamiento multiempresa", () => {
    it("resolver el paso en una empresa no toca el de la otra", async () => {
      const a = await registerTenant("aislamiento-a");
      const b = await registerTenant("aislamiento-b");

      const evidenceA = await registerEvidence(
        a.token,
        "OFFICIAL_DOCUMENT",
        "OFV_ROLE_ACCEPTANCE",
      );
      await http()
        .patch("/ecf/onboarding/steps/ROLE_ASSIGNMENT")
        .set(auth(a.token))
        .send({ status: "CONFIRMED", evidenceId: evidenceA })
        .expect(200);

      const rowA = await stepOf(a.companyId);
      const rowB = await stepOf(b.companyId);
      expect(rowA?.status).toBe("CONFIRMED");
      expect(rowB?.status).not.toBe("CONFIRMED");
    });
  });

  describe("la certificación sigue siendo un hecho externo", () => {
    it("con el paso de roles resuelto, la empresa NO queda certificada", async () => {
      const tenant = await registerTenant("no-certificada");
      const evidenceId = await registerEvidence(
        tenant.token,
        "OFFICIAL_DOCUMENT",
        "OFV_ROLE_ACCEPTANCE",
      );
      await http()
        .patch("/ecf/onboarding/steps/ROLE_ASSIGNMENT")
        .set(auth(tenant.token))
        .send({ status: "CONFIRMED", evidenceId })
        .expect(200);

      const habilitation = await http()
        .get("/ecf/dgii/habilitation")
        .set(auth(tenant.token))
        .expect(200);

      expect(habilitation.body.officialAuthorization).toBe(false);
      expect(habilitation.body.state).not.toBe("APPROVED");
    });
  });
});
