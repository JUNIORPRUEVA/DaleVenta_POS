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
 * E2E de PROPIEDAD DEL ESTADO del expediente DGII.
 *
 * La tabla de transiciones decía qué cambios son válidos; esto fija QUIÉN puede
 * declararlos. Antes, una empresa podía escribir `IN_CERTIFICATION` o
 * `TESTS_PENDING` y presentar como hecho un estado que solo producen la DGII o
 * el proveedor.
 *
 * Lo que se demuestra:
 *  - La empresa NO puede fijar estados de proveedor ni de la DGII.
 *  - La empresa SÍ conserva sus acciones legítimas (iniciar, preparar, postular).
 *  - El panel de plataforma conserva su camino (no se rompe la operación).
 */
jest.setTimeout(300000);

const PASSWORD = "EcfStateOwnershipE2E123!";
const SAFE_DB = /^fullpos_state_ownership_e2e_/;

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

uat("propiedad del estado del expediente DGII", () => {
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
    dbName = `fullpos_state_ownership_e2e_${Date.now()}`;
    adminUrl = replaceDbName(baseUrl, "postgres");
    const appUrl = replaceDbName(baseUrl, dbName);
    if (!SAFE_DB.test(dbName)) throw new Error("Unsafe E2E DB name");

    const admin = new Client({ connectionString: adminUrl });
    await admin.connect();
    await admin.query(`CREATE DATABASE ${dbName}`);
    await admin.end();

    process.env.DATABASE_URL = appUrl;
    process.env.JWT_SECRET =
      process.env.JWT_SECRET || "ecf-state-ownership-e2e-secret";
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
    const email = `state-e2e-${Date.now()}-${suffix}@example.test`;
    const res = await http()
      .post("/auth/register-business")
      .send({
        firstName: "State",
        lastName: suffix,
        email,
        phone: "8095550000",
        password: PASSWORD,
        confirmPassword: PASSWORD,
        commercialName: `State ${suffix}`,
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

  /** La empresa debe empezar con su expediente creado. */
  async function ensureDossier(token: string) {
    await http().get("/ecf/dgii/habilitation").set(auth(token)).expect(200);
  }

  describe("la empresa NO declara estados externos", () => {
    const forbidden = [
      "IN_CERTIFICATION",
      "TESTS_PENDING",
      "IN_PROGRESS",
      "APPROVED",
      "REJECTED",
    ];

    for (const state of forbidden) {
      it(`rechaza ${state} con 403 y código explícito`, async () => {
        const tenant = await registerTenant(state.toLowerCase());
        await ensureDossier(tenant.token);

        const res = await http()
          .patch("/ecf/dgii/habilitation")
          .set(auth(tenant.token))
          .send({ state })
          .expect(403);

        expect(res.body.message).toBe(
          "ECF_DGII_STATE_REQUIRES_EXTERNAL_EVIDENCE",
        );

        const row = await prisma.ecfDgiiHabilitation.findUnique({
          where: { companyId: tenant.companyId },
        });
        expect(row?.state).not.toBe(state);
      });
    }
  });

  describe("la empresa conserva sus acciones legítimas", () => {
    it("puede pasar a APPLICATION_PENDING", async () => {
      const tenant = await registerTenant("postular");
      await ensureDossier(tenant.token);

      const res = await http()
        .patch("/ecf/dgii/habilitation")
        .set(auth(tenant.token))
        .send({ state: "APPLICATION_PENDING" })
        .expect(200);
      expect(res.body.state).toBe("APPLICATION_PENDING");
    });

    it("puede pasar a PREPARING_REQUIREMENTS", async () => {
      const tenant = await registerTenant("preparar");
      await ensureDossier(tenant.token);

      const res = await http()
        .patch("/ecf/dgii/habilitation")
        .set(auth(tenant.token))
        .send({ state: "PREPARING_REQUIREMENTS" })
        .expect(200);
      expect(res.body.state).toBe("PREPARING_REQUIREMENTS");
    });
  });

  describe("el panel de plataforma conserva su operación", () => {
    it("el staff puede avanzar el expediente a IN_PROGRESS", async () => {
      const customer = await registerTenant("cliente");
      const staff = await registerTenant("staff");
      await ensureDossier(customer.token);
      await http()
        .patch("/ecf/dgii/habilitation")
        .set(auth(customer.token))
        .send({ state: "APPLICATION_PENDING" })
        .expect(200);

      // El personal de plataforma ya no accede sin concesión: la empresa debe
      // autorizar el alcance que la mutación requiere.
      await http()
        .post("/ecf/dgii/support-grants")
        .set(auth(customer.token))
        .send({
          scopes: ["REQUEST_CORRECTION"],
          expiresAt: new Date(Date.now() + 24 * 60 * 60 * 1000).toISOString(),
          reason: "UAT: transición administrativa supervisada",
        })
        .expect(201);

      process.env[PLATFORM_STAFF_ENV] = staff.userId;

      const res = await http()
        .patch(`/ecf/platform/dgii/applications/${customer.companyId}`)
        .set(auth(staff.token))
        .send({ state: "IN_PROGRESS" })
        .expect(200);
      expect(res.body.state).toBe("IN_PROGRESS");
    });
  });
});
