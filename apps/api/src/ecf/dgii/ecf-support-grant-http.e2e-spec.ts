import { INestApplication, ValidationPipe } from "@nestjs/common";
import { Test } from "@nestjs/testing";
import { execFileSync } from "node:child_process";
import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { Client } from "pg";
import request from "supertest";
import { AppModule } from "../../app.module";
import { PrismaService } from "../../prisma/prisma.service";
import { PLATFORM_STAFF_ENV } from "../platform/platform-staff.guard";

/**
 * MATRIZ DE SEGURIDAD de la asistencia autorizada (empresa → FULLTECH).
 *
 * Cada caso comprueba que la barrera FALLA CUANDO DEBE FALLAR. Ser staff de
 * plataforma no basta: hace falta una concesión vigente de la empresa dueña del
 * expediente, con el alcance adecuado.
 */
jest.setTimeout(300000);

const PASSWORD = "EcfSupportGrantE2E123!";
const SAFE_DB = /^fullpos_support_grant_e2e_/;

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

uat("asistencia autorizada — matriz de seguridad", () => {
  let app: INestApplication;
  let prisma: PrismaService;
  let dbName: string;
  let adminUrl: string;

  const http = () => request(app.getHttpServer());
  const auth = (token: string) => ({ Authorization: `Bearer ${token}` });

  beforeAll(async () => {
    if (process.env.ALANUBE_ENABLE_REAL_CALLS !== "false") {
      throw new Error("E2E_REFUSES_REAL_PROVIDER_CALLS");
    }
    const baseUrl = baseDatabaseUrl();
    dbName = `fullpos_support_grant_e2e_${Date.now()}`;
    adminUrl = replaceDbName(baseUrl, "postgres");
    const appUrl = replaceDbName(baseUrl, dbName);
    if (!SAFE_DB.test(dbName)) throw new Error("Unsafe E2E DB name");

    const admin = new Client({ connectionString: adminUrl });
    await admin.connect();
    await admin.query(`CREATE DATABASE ${dbName}`);
    await admin.end();

    process.env.DATABASE_URL = appUrl;
    process.env.JWT_SECRET = process.env.JWT_SECRET || "ecf-grant-e2e-secret";
    process.env[PLATFORM_STAFF_ENV] = "";

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

  afterEach(() => {
    process.env[PLATFORM_STAFF_ENV] = "";
  });

  async function registerTenant(suffix: string) {
    const email = `grant-e2e-${Date.now()}-${suffix}@example.test`;
    const res = await http()
      .post("/auth/register-business")
      .send({
        firstName: "Grant",
        lastName: suffix,
        email,
        phone: "8095550000",
        password: PASSWORD,
        confirmPassword: PASSWORD,
        commercialName: `Grant ${suffix}`,
        taxId: `1${Date.now().toString().slice(-8)}`,
        businessPhone: "8095551111",
        address: `Calle Sintética ${suffix}`,
        country: "DO",
      })
      .expect(201);
    return {
      token: res.body.accessToken as string,
      userId: res.body.user.id as string,
      companyId: res.body.activeCompany.id as string,
    };
  }

  function expiresIn(days: number) {
    return new Date(Date.now() + days * 24 * 60 * 60 * 1000).toISOString();
  }

  async function grant(
    token: string,
    scopes: string[],
    days = 7,
  ): Promise<string> {
    const res = await http()
      .post("/ecf/dgii/support-grants")
      .set(auth(token))
      .send({ scopes, expiresAt: expiresIn(days) })
      .expect(201);
    return res.body.id as string;
  }

  /** Staff válido apuntando a la empresa indicada. */
  async function staffFor(suffix: string) {
    const staff = await registerTenant(`staff-${suffix}`);
    process.env[PLATFORM_STAFF_ENV] = staff.userId;
    return staff;
  }

  const detailUrl = (companyId: string) =>
    `/ecf/platform/dgii/applications/${companyId}`;

  describe("denegaciones", () => {
    it("sin concesión, el staff no accede al expediente", async () => {
      const company = await registerTenant("sin-grant");
      const staff = await staffFor("sin-grant");
      const res = await http()
        .get(detailUrl(company.companyId))
        .set(auth(staff.token))
        .expect(403);
      expect(JSON.stringify(res.body)).toContain(
        "ECF_SUPPORT_GRANT_MISSING",
      );
    });

    it("una concesión expirada no concede acceso", async () => {
      const company = await registerTenant("expirada");
      await prisma.ecfSupportGrant.create({
        data: {
          companyId: company.companyId,
          grantedByUserId: company.userId,
          scopes: ["VIEW_DOSSIER"],
          expiresAt: new Date(Date.now() - 60_000),
        },
      });
      const staff = await staffFor("expirada");
      const res = await http()
        .get(detailUrl(company.companyId))
        .set(auth(staff.token))
        .expect(403);
      expect(JSON.stringify(res.body)).toContain("ECF_SUPPORT_GRANT_EXPIRED");
    });

    it("una concesión revocada no concede acceso", async () => {
      const company = await registerTenant("revocada");
      const grantId = await grant(company.token, ["VIEW_DOSSIER"]);
      await http()
        .post(`/ecf/dgii/support-grants/${grantId}/revoke`)
        .set(auth(company.token))
        .send({})
        .expect(201);
      const staff = await staffFor("revocada");
      const res = await http()
        .get(detailUrl(company.companyId))
        .set(auth(staff.token))
        .expect(403);
      expect(JSON.stringify(res.body)).toContain("ECF_SUPPORT_GRANT_REVOKED");
    });

    it("la concesión de una empresa no abre el expediente de otra", async () => {
      const a = await registerTenant("empresa-a");
      const b = await registerTenant("empresa-b");
      // El expediente debe existir para que el acceso autorizado dé 200.
      await http().get("/ecf/dgii/habilitation").set(auth(a.token)).expect(200);
      await http().get("/ecf/dgii/habilitation").set(auth(b.token)).expect(200);
      await grant(a.token, ["VIEW_DOSSIER"]);
      const staff = await staffFor("cruzado");
      await http()
        .get(detailUrl(a.companyId))
        .set(auth(staff.token))
        .expect(200);
      const res = await http()
        .get(detailUrl(b.companyId))
        .set(auth(staff.token))
        .expect(403);
      expect(JSON.stringify(res.body)).toContain(
        "ECF_SUPPORT_GRANT_MISSING",
      );
    });

    it("un alcance insuficiente no permite revisar requisitos", async () => {
      const company = await registerTenant("alcance");
      await http().get("/ecf/dgii/habilitation").set(auth(company.token)).expect(200);
      await grant(company.token, ["VIEW_DOSSIER"]);
      const staff = await staffFor("alcance");
      await http()
        .get(detailUrl(company.companyId))
        .set(auth(staff.token))
        .expect(200);
      const res = await http()
        .patch(
          `/ecf/platform/dgii/applications/${company.companyId}/requirements/FISCAL_DATA`,
        )
        .set(auth(staff.token))
        .send({ status: "IN_PROGRESS" })
        .expect(403);
      expect(JSON.stringify(res.body)).toContain(
        "ECF_SUPPORT_SCOPE_NOT_GRANTED",
      );
    });

    it("el staff no puede crear una concesión para otra empresa", async () => {
      const company = await registerTenant("autoconcesion");
      const staff = await staffFor("autoconcesion");
      // La concesión que crea el staff es sobre SU propia empresa, no sobre la
      // del cliente: el companyId sale del token, nunca del cuerpo.
      await http()
        .post("/ecf/dgii/support-grants")
        .set(auth(staff.token))
        .send({
          scopes: ["VIEW_DOSSIER", "REVIEW_EVIDENCE", "REQUEST_CORRECTION"],
          expiresAt: expiresIn(7),
        })
        .expect(201);
      await http()
        .get(detailUrl(company.companyId))
        .set(auth(staff.token))
        .expect(403);
    });
  });

  describe("revocación inmediata", () => {
    it("tras revocar, la siguiente petición ya se deniega", async () => {
      const company = await registerTenant("inmediata");
      await http().get("/ecf/dgii/habilitation").set(auth(company.token)).expect(200);
      const grantId = await grant(company.token, ["VIEW_DOSSIER"]);
      const staff = await staffFor("inmediata");

      await http()
        .get(detailUrl(company.companyId))
        .set(auth(staff.token))
        .expect(200);

      await http()
        .post(`/ecf/dgii/support-grants/${grantId}/revoke`)
        .set(auth(company.token))
        .send({})
        .expect(201);

      await http()
        .get(detailUrl(company.companyId))
        .set(auth(staff.token))
        .expect(403);
    });
  });

  describe("renovación tras caducidad", () => {
    it("una concesión caducada puede sustituirse por una nueva", async () => {
      const company = await registerTenant("renovacion");
      // Caducada y NO revocada: antes bloqueaba el índice único parcial.
      await prisma.ecfSupportGrant.create({
        data: {
          companyId: company.companyId,
          grantedByUserId: company.userId,
          scopes: ["VIEW_DOSSIER"],
          expiresAt: new Date(Date.now() - 1000),
        },
      });

      const newGrantId = await grant(company.token, ["VIEW_DOSSIER"]);
      expect(newGrantId).toBeTruthy();

      // La caducada se cierra con rastro, no se borra.
      const rows = await prisma.ecfSupportGrant.findMany({
        where: { companyId: company.companyId },
      });
      expect(rows).toHaveLength(2);
      expect(rows.filter((row) => row.revokedAt === null)).toHaveLength(1);
    });

    it("dos altas simultáneas no dejan dos concesiones efectivas", async () => {
      const company = await registerTenant("concurrente");
      const results = await Promise.all([
        http()
          .post("/ecf/dgii/support-grants")
          .set(auth(company.token))
          .send({ scopes: ["VIEW_DOSSIER"], expiresAt: expiresIn(7) }),
        http()
          .post("/ecf/dgii/support-grants")
          .set(auth(company.token))
          .send({ scopes: ["VIEW_DOSSIER"], expiresAt: expiresIn(7) }),
      ]);
      const created = results.filter((res) => res.status === 201).length;
      expect(created).toBeGreaterThanOrEqual(1);
      const active = await prisma.ecfSupportGrant.count({
        where: { companyId: company.companyId, revokedAt: null },
      });
      expect(active).toBe(1);
    });
  });

  describe("la concesión no fabrica evidencia oficial", () => {
    it("con todos los alcances, el staff no puede marcar APPROVED", async () => {
      const company = await registerTenant("no-fabricar");
      await grant(company.token, [
        "VIEW_DOSSIER",
        "REVIEW_EVIDENCE",
        "REQUEST_CORRECTION",
      ]);
      const staff = await staffFor("no-fabricar");

      const res = await http()
        .patch(detailUrl(company.companyId))
        .set(auth(staff.token))
        .send({ state: "APPROVED" });
      expect([400, 403, 409]).toContain(res.status);

      const row = await prisma.ecfDgiiHabilitation.findUnique({
        where: { companyId: company.companyId },
      });
      expect(row?.state).not.toBe("APPROVED");
    });
  });
});
