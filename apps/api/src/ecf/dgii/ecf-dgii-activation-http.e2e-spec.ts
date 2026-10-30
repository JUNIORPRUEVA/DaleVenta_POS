import { INestApplication, ValidationPipe } from "@nestjs/common";
import { Test } from "@nestjs/testing";
import {
  EcfAuditAction,
  EcfOnboardingStepKey,
  EcfOnboardingStepStatus,
} from "@prisma/client";
import { execFileSync } from "node:child_process";
import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { Client } from "pg";
import request from "supertest";
import { AppModule } from "../../app.module";
import { PrismaService } from "../../prisma/prisma.service";

/**
 * E2E HTTP del MOTOR DE ACTIVACIÓN (`/ecf/dgii/activation/*`).
 *
 * Se levanta la aplicación completa contra una base desechable propia y se habla
 * por HTTP real: `AuthGuard('jwt')`, `RolesGuard`, `ValidationPipe`, controlador,
 * servicio, Prisma y PostgreSQL.
 *
 * Lo que este archivo fija:
 *  - El motor solo ejecuta lo que es suyo y **no salta pasos**: sin certificado
 *    no se llega a la habilitación de producción.
 *  - Los pasos del cliente y de la DGII nunca se completan desde aquí.
 *  - La simulación se marca como simulación y no toca la autorización oficial.
 *  - El reintento es idempotente y acepta `key` y `stepKey` del catálogo.
 *  - El transporte real está bloqueado mientras no exista contrato verificado.
 *
 * Lo que NO hace: ninguna llamada a Alanube ni a la DGII. El archivo se niega a
 * correr si `ALANUBE_ENABLE_REAL_CALLS` no es `false`.
 */
jest.setTimeout(300000);

const PASSWORD = "EcfActivationE2E123!";
const SAFE_DB = /^fullpos_activation_http_e2e_/;
const TRANSPORT_ENV = "ECF_ACTIVATION_TRANSPORT";
const SCENARIO_ENV = "ECF_ACTIVATION_SIMULATION_SCENARIO";

// Opt-in explícito: solo corre contra la base efímera de pruebas.
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

uat("motor de activación e-CF — E2E HTTP + PostgreSQL desechable", () => {
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
    dbName = `fullpos_activation_http_e2e_${Date.now()}`;
    adminUrl = replaceDbName(baseUrl, "postgres");
    appUrl = replaceDbName(baseUrl, dbName);
    if (!SAFE_DB.test(dbName)) throw new Error("Unsafe E2E DB name");

    const admin = new Client({ connectionString: adminUrl });
    await admin.connect();
    await admin.query(`CREATE DATABASE ${dbName}`);
    await admin.end();

    process.env.DATABASE_URL = appUrl;
    process.env.JWT_SECRET =
      process.env.JWT_SECRET || "ecf-activation-http-e2e-secret";
    process.env[TRANSPORT_ENV] = "simulated";
    delete process.env[SCENARIO_ENV];

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
    process.env[TRANSPORT_ENV] = "simulated";
    delete process.env[SCENARIO_ENV];
  });

  /** Empresa + administrador reales, creados por HTTP. */
  async function registerTenant(suffix: string) {
    const email = `activation-e2e-${Date.now()}-${suffix}@example.test`;
    const res = await http()
      .post("/auth/register-business")
      .send({
        firstName: "Activation",
        lastName: suffix,
        email,
        phone: "8095550000",
        password: PASSWORD,
        confirmPassword: PASSWORD,
        commercialName: `Activation ${suffix}`,
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

  function auth(token: string) {
    return { Authorization: `Bearer ${token}` };
  }

  /** Deja el expediente en `APPLICATION_PENDING`, requisito para arrancar. */
  async function submitApplication(token: string) {
    await http().get("/ecf/dgii/habilitation").set(auth(token)).expect(200);
    await http()
      .patch("/ecf/dgii/habilitation")
      .set(auth(token))
      .send({ state: "APPLICATION_PENDING" })
      .expect(200);
  }

  /** Marca como COMPLETED los pasos que dependen del cliente. */
  async function resolveClientSteps(companyId: string) {
    await prisma.ecfOnboardingStep.updateMany({
      where: {
        companyId,
        stepKey: {
          in: [
            EcfOnboardingStepKey.REQUIREMENTS,
            EcfOnboardingStepKey.DIGITAL_CERTIFICATE,
            EcfOnboardingStepKey.SWORN_DECLARATION,
          ],
        },
      },
      data: { status: EcfOnboardingStepStatus.COMPLETED },
    });
  }

  async function stepOf(companyId: string, stepKey: EcfOnboardingStepKey) {
    return prisma.ecfOnboardingStep.findFirst({
      where: { companyId, stepKey },
    });
  }

  function viewStep(body: { steps: { key: string; status: string }[] }, key: string) {
    return body.steps.find((step) => step.key === key);
  }

  /** Empresa lista para ejecutar pasos de proveedor. */
  async function readyCompany(suffix: string) {
    const tenant = await registerTenant(suffix);
    await submitApplication(tenant.token);
    await http()
      .post("/ecf/dgii/activation/start")
      .set(auth(tenant.token))
      .send({})
      .expect(201);
    await resolveClientSteps(tenant.companyId);
    return tenant;
  }

  describe("vista y bloqueos de arranque", () => {
    it("exige autenticación", async () => {
      await http().get("/ecf/dgii/activation").expect(401);
    });

    it("expone el catálogo completo de 15 pasos desde el inicio", async () => {
      const tenant = await registerTenant("catalogo");
      const res = await http()
        .get("/ecf/dgii/activation")
        .set(auth(tenant.token))
        .expect(200);
      // 15 desde que la etapa V (ROLE_ASSIGNMENT) tiene paso propio.
      expect(res.body.steps).toHaveLength(15);
      expect(res.body.steps.map((step: { key: string }) => step.key)).toEqual(
        expect.arrayContaining([
          "FISCAL_DATA",
          "REQUIREMENTS",
          "DIGITAL_CERTIFICATE",
          "FINAL_AUTHORIZATION",
          "PRODUCTION_ENABLEMENT",
        ]),
      );
    });

    it("no arranca si el expediente no se ha enviado", async () => {
      const tenant = await registerTenant("sin-expediente");
      await http().get("/ecf/dgii/habilitation").set(auth(tenant.token)).expect(200);
      const res = await http()
        .post("/ecf/dgii/activation/start")
        .set(auth(tenant.token))
        .send({})
        .expect(400);
      expect(res.body.blockers).toContain(
        "ECF_ACTIVATION_APPLICATION_NOT_SUBMITTED",
      );
    });

    it("no arranca sin datos fiscales de la empresa", async () => {
      const tenant = await registerTenant("sin-rnc");
      await submitApplication(tenant.token);
      await prisma.appConfig.updateMany({
        where: { companyId: tenant.companyId },
        data: { rnc: "" },
      });
      const res = await http()
        .post("/ecf/dgii/activation/start")
        .set(auth(tenant.token))
        .send({})
        .expect(400);
      expect(res.body.blockers).toContain("ECF_ACTIVATION_FISCAL_DATA_MISSING");
    });
  });

  describe("ejecución y orden", () => {
    it("completa el paso automático y se detiene en el primero del cliente", async () => {
      const tenant = await registerTenant("orden");
      await submitApplication(tenant.token);
      const res = await http()
        .post("/ecf/dgii/activation/start")
        .set(auth(tenant.token))
        .send({})
        .expect(201);

      expect(viewStep(res.body, "FISCAL_DATA")?.status).toBe("COMPLETED");
      expect(viewStep(res.body, "REQUIREMENTS")?.status).not.toBe("COMPLETED");
      expect(res.body.summary.stage).toBe("BLOCKED_ON_CLIENT");
    });

    it("no salta pasos: un paso posterior sigue pendiente", async () => {
      const tenant = await registerTenant("no-salta");
      await submitApplication(tenant.token);
      await http()
        .post("/ecf/dgii/activation/start")
        .set(auth(tenant.token))
        .send({})
        .expect(201);

      const registration = await stepOf(
        tenant.companyId,
        EcfOnboardingStepKey.ALANUBE_REGISTRATION,
      );
      expect(registration?.status).not.toBe(EcfOnboardingStepStatus.COMPLETED);
    });

    it("los pasos del cliente no son ejecutables y explican qué falta", async () => {
      const tenant = await registerTenant("cliente");
      await submitApplication(tenant.token);
      const res = await http()
        .post("/ecf/dgii/activation/start")
        .set(auth(tenant.token))
        .send({})
        .expect(201);

      const requirement = res.body.steps.find(
        (step: { key: string }) => step.key === "REQUIREMENTS",
      );
      expect(requirement.className).toBe("CLIENT_ACTION");
      expect(requirement.executable).toBe(false);
      expect(requirement.awaiting).toBeTruthy();
    });

    it("es idempotente: repetir start no cambia el resultado", async () => {
      const tenant = await registerTenant("idempotente");
      await submitApplication(tenant.token);
      const first = await http()
        .post("/ecf/dgii/activation/start")
        .set(auth(tenant.token))
        .send({})
        .expect(201);
      const second = await http()
        .post("/ecf/dgii/activation/start")
        .set(auth(tenant.token))
        .send({})
        .expect(201);

      expect(second.body.summary).toEqual(first.body.summary);
      expect(
        second.body.steps.map((step: { status: string }) => step.status),
      ).toEqual(first.body.steps.map((step: { status: string }) => step.status));
    });
  });

  describe("reintento", () => {
    it("rechaza un paso desconocido", async () => {
      const tenant = await registerTenant("retry-desconocido");
      const res = await http()
        .post("/ecf/dgii/activation/steps/NO_EXISTE/retry")
        .set(auth(tenant.token))
        .send({})
        .expect(404);
      expect(res.body.message).toBe("ECF_ACTIVATION_STEP_UNKNOWN");
    });

    it("no permite reintentar un paso del cliente", async () => {
      const tenant = await registerTenant("retry-cliente");
      const res = await http()
        .post("/ecf/dgii/activation/steps/DIGITAL_CERTIFICATE/retry")
        .set(auth(tenant.token))
        .send({})
        .expect(400);
      expect(res.body.message).toBe("ECF_ACTIVATION_AWAITING_CLIENT");
    });

    it("no permite reintentar un paso de la DGII", async () => {
      const tenant = await registerTenant("retry-dgii");
      const res = await http()
        .post("/ecf/dgii/activation/steps/FINAL_AUTHORIZATION/retry")
        .set(auth(tenant.token))
        .send({})
        .expect(400);
      expect(res.body.message).toBe("ECF_ACTIVATION_AWAITING_AUTHORITY");
    });

    it("acepta el identificador de requisito (key)", async () => {
      const tenant = await registerTenant("retry-key");
      await submitApplication(tenant.token);
      await http()
        .post("/ecf/dgii/activation/steps/FISCAL_DATA/retry")
        .set(auth(tenant.token))
        .send({})
        .expect(201);
    });

    it("acepta el identificador de etapa (stepKey)", async () => {
      const tenant = await registerTenant("retry-stepkey");
      await submitApplication(tenant.token);
      await http()
        .post("/ecf/dgii/activation/steps/FISCAL_CONFIG/retry")
        .set(auth(tenant.token))
        .send({})
        .expect(201);
    });

    it("no revierte un bloqueo con motivo: es una decisión registrada", async () => {
      const tenant = await readyCompany("bloqueo-humano");
      await prisma.ecfOnboardingStep.updateMany({
        where: {
          companyId: tenant.companyId,
          stepKey: EcfOnboardingStepKey.ALANUBE_REGISTRATION,
        },
        data: {
          status: EcfOnboardingStepStatus.BLOCKED,
          blockedReason: "Proveedor suspendió la cuenta",
        },
      });

      const res = await http()
        .post("/ecf/dgii/activation/steps/ALANUBE_REGISTRATION/retry")
        .set(auth(tenant.token))
        .send({})
        .expect(409);

      expect(res.body.message).toBe("ECF_ACTIVATION_STEP_BLOCKED_BY_DECISION");
      expect(res.body.blockedReason).toBe("Proveedor suspendió la cuenta");

      const row = await stepOf(
        tenant.companyId,
        EcfOnboardingStepKey.ALANUBE_REGISTRATION,
      );
      expect(row?.status).toBe(EcfOnboardingStepStatus.BLOCKED);
      expect(row?.blockedReason).toBe("Proveedor suspendió la cuenta");
    });

    it("cura una etapa bloqueada sin motivo (huérfana del mapeo antiguo)", async () => {
      const tenant = await readyCompany("bloqueo-huerfano");
      await prisma.ecfOnboardingStep.updateMany({
        where: {
          companyId: tenant.companyId,
          stepKey: EcfOnboardingStepKey.ALANUBE_REGISTRATION,
        },
        data: {
          status: EcfOnboardingStepStatus.BLOCKED,
          blockedReason: null,
        },
      });

      await http()
        .post("/ecf/dgii/activation/steps/ALANUBE_REGISTRATION/retry")
        .set(auth(tenant.token))
        .send({})
        .expect(201);

      const row = await stepOf(
        tenant.companyId,
        EcfOnboardingStepKey.ALANUBE_REGISTRATION,
      );
      expect(row?.status).toBe(EcfOnboardingStepStatus.COMPLETED);
    });

    it("el reintento deja rastro en la auditoría", async () => {
      const tenant = await readyCompany("auditoria-retry");
      await prisma.ecfOnboardingStep.updateMany({
        where: {
          companyId: tenant.companyId,
          stepKey: EcfOnboardingStepKey.ALANUBE_REGISTRATION,
        },
        data: {
          status: EcfOnboardingStepStatus.FAILED,
          lastErrorCode: "ECF_FALLO_SINTETICO",
        },
      });

      await http()
        .post("/ecf/dgii/activation/steps/ALANUBE_REGISTRATION/retry")
        .set(auth(tenant.token))
        .send({})
        .expect(201);

      const rows = await prisma.ecfAuditLog.findMany({
        where: {
          companyId: tenant.companyId,
          action: EcfAuditAction.STEP_UPDATED,
        },
      });
      const retried = rows.some((row) =>
        JSON.stringify(row.after).includes('"retried":true'),
      );
      expect(retried).toBe(true);
    });
  });

  describe("transporte simulado", () => {
    it("un rechazo simulado deja el paso en FAILED con su código", async () => {
      const tenant = await readyCompany("reject");
      process.env[SCENARIO_ENV] = "reject";
      const res = await http()
        .post("/ecf/dgii/activation/start")
        .set(auth(tenant.token))
        .send({})
        .expect(201);

      const step = viewStep(res.body, "ALANUBE_REGISTRATION");
      expect(step?.status).toBe("FAILED");
      const row = await stepOf(
        tenant.companyId,
        EcfOnboardingStepKey.ALANUBE_REGISTRATION,
      );
      expect(row?.lastErrorCode).toBe("ECF_ACTIVATION_SIMULATED_REJECTION");
    });

    it("un rechazo detiene el motor y no avanza al paso siguiente", async () => {
      const tenant = await readyCompany("reject-stop");
      process.env[SCENARIO_ENV] = "reject";
      await http()
        .post("/ecf/dgii/activation/start")
        .set(auth(tenant.token))
        .send({})
        .expect(201);

      const next = await stepOf(
        tenant.companyId,
        EcfOnboardingStepKey.DGII_POSTULATION,
      );
      expect(next?.status).not.toBe(EcfOnboardingStepStatus.COMPLETED);
    });

    it("un timeout simulado se registra como fallo, no como éxito", async () => {
      const tenant = await readyCompany("timeout");
      process.env[SCENARIO_ENV] = "timeout";
      await http()
        .post("/ecf/dgii/activation/start")
        .set(auth(tenant.token))
        .send({})
        .expect(201);

      const row = await stepOf(
        tenant.companyId,
        EcfOnboardingStepKey.ALANUBE_REGISTRATION,
      );
      expect(row?.status).toBe(EcfOnboardingStepStatus.FAILED);
      expect(row?.lastErrorCode).toBe("ECF_ACTIVATION_SIMULATED_TIMEOUT");
    });

    it("tras un fallo, el reintento con transporte correcto completa el paso", async () => {
      const tenant = await readyCompany("retry-ok");
      process.env[SCENARIO_ENV] = "reject";
      await http()
        .post("/ecf/dgii/activation/start")
        .set(auth(tenant.token))
        .send({})
        .expect(201);

      delete process.env[SCENARIO_ENV];
      await http()
        .post("/ecf/dgii/activation/steps/ALANUBE_REGISTRATION/retry")
        .set(auth(tenant.token))
        .send({})
        .expect(201);

      const row = await stepOf(
        tenant.companyId,
        EcfOnboardingStepKey.ALANUBE_REGISTRATION,
      );
      expect(row?.status).toBe(EcfOnboardingStepStatus.COMPLETED);
    });

    it("con el transporte real sin contrato responde 503", async () => {
      const tenant = await registerTenant("transporte-real");
      await submitApplication(tenant.token);
      process.env[TRANSPORT_ENV] = "real";
      const res = await http()
        .post("/ecf/dgii/activation/start")
        .set(auth(tenant.token))
        .send({})
        .expect(503);
      expect(res.body.message).toBe(
        "ECF_ACTIVATION_REAL_TRANSPORT_NOT_CONFIGURED",
      );
    });
  });

  describe("garantías fiscales", () => {
    it("nunca completa un paso de la DGII aunque todo lo demás esté resuelto", async () => {
      const tenant = await registerTenant("autoridad");
      await submitApplication(tenant.token);
      await http()
        .post("/ecf/dgii/activation/start")
        .set(auth(tenant.token))
        .send({})
        .expect(201);
      await resolveClientSteps(tenant.companyId);
      const res = await http()
        .post("/ecf/dgii/activation/start")
        .set(auth(tenant.token))
        .send({})
        .expect(201);

      const authority = res.body.steps.find(
        (step: { key: string }) => step.key === "FINAL_AUTHORIZATION",
      );
      expect(authority.className).toBe("AUTHORITY_WAIT");
      expect(authority.resolved).toBe(false);

      const row = await stepOf(
        tenant.companyId,
        EcfOnboardingStepKey.FINAL_AUTHORIZATION,
      );
      expect(row?.status).not.toBe(EcfOnboardingStepStatus.COMPLETED);
    });

    it("la simulación no toca la autorización oficial del expediente", async () => {
      const tenant = await readyCompany("sin-aprobacion");
      const before = await prisma.ecfDgiiHabilitation.findUnique({
        where: { companyId: tenant.companyId },
      });
      await http()
        .post("/ecf/dgii/activation/start")
        .set(auth(tenant.token))
        .send({})
        .expect(201);
      const after = await prisma.ecfDgiiHabilitation.findUnique({
        where: { companyId: tenant.companyId },
      });

      expect(after?.authorizationSource).toBe(before?.authorizationSource);
      expect(after?.state).toBe(before?.state);
      expect(after?.state).not.toBe("APPROVED");
    });

    it("cada transición queda auditada como STEP_UPDATED", async () => {
      const tenant = await registerTenant("auditoria");
      await submitApplication(tenant.token);
      await http()
        .post("/ecf/dgii/activation/start")
        .set(auth(tenant.token))
        .send({})
        .expect(201);

      const rows = await prisma.ecfAuditLog.findMany({
        where: { companyId: tenant.companyId, action: EcfAuditAction.STEP_UPDATED },
      });
      expect(rows.length).toBeGreaterThan(0);
    });

    it("los pasos de proveedor completados quedan marcados como simulados", async () => {
      const tenant = await readyCompany("marcado");
      const res = await http()
        .post("/ecf/dgii/activation/start")
        .set(auth(tenant.token))
        .send({})
        .expect(201);
      expect(viewStep(res.body, "ALANUBE_REGISTRATION")?.status).toBe(
        "COMPLETED",
      );

      const row = await stepOf(
        tenant.companyId,
        EcfOnboardingStepKey.ALANUBE_REGISTRATION,
      );
      expect(row?.resultSummary ?? "").toContain("SIMULATED_OK");
    });
  });
});
