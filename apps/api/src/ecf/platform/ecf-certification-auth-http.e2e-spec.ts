import { INestApplication, ValidationPipe } from "@nestjs/common";
import { Test } from "@nestjs/testing";
import { EcfCertificationStatus } from "@prisma/client";
import { execFileSync } from "node:child_process";
import { readFileSync } from "node:fs";
import { Client } from "pg";
import request from "supertest";

import { AppModule } from "../../app.module";
import { PrismaService } from "../../prisma/prisma.service";
import { resolvePrismaCliPath } from "../../testing/prisma-cli";
import { PLATFORM_STAFF_ENV } from "./platform-staff.guard";

/**
 * E2E HTTP de la AUTORIZACIÓN DE EMISIÓN por empresa.
 *
 * Cierra el hueco que quedaba: `deriveCertificationStatus` solo puede producir
 * `NOT_STARTED`, `IN_PROGRESS`, `BLOCKED` y `READY_FOR_REVIEW`, así que los dos
 * estados que el orquestador exige para despachar (`AUTHORIZED_SANDBOX`,
 * `PRODUCTION_READY`) solo se podían escribir con un `UPDATE` manual.
 *
 * Este archivo habla por HTTP real (JWT real, `PlatformStaffGuard` real,
 * `EcfSupportGrantGuard` real, `ValidationPipe` real) contra PostgreSQL
 * desechable y demuestra, en este orden:
 *
 *  1. Un administrador de empresa NO se autoriza a sí mismo (403).
 *  2. Sin concesión de soporte, el staff tampoco (403).
 *  3. Con concesión, la transición se aplica y queda auditada con actor y motivo.
 *  4. La repetición es idempotente: ni escritura ni auditoría duplicada.
 *  5. Producción exige sandbox previo; no hay rebaja de producción a sandbox.
 *  6. `BLOCKED` no se autoriza: la evidencia manda.
 *  7. Revocar deja `SUSPENDED` y reactivar exige otra autorización.
 *  8. La autorización NO habilita la emisión (enabled/banderas intactas).
 *  9. Tocar una etapa de onboarding no degrada la autorización (regresión).
 * 10. El aislamiento entre empresas se mantiene.
 *
 * No llama a DOSA ni a la DGII: `ALANUBE_ENABLE_REAL_CALLS=false` es
 * obligatorio y ninguna bandera de emisión se toca.
 */
jest.setTimeout(300000);

const PASSWORD = "EcfCertAuthE2E123!";
const SAFE_DB = /^fullpos_cert_auth_http_e2e_/;
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

uat("e-CF autorización de emisión — E2E HTTP + PostgreSQL desechable", () => {
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
    dbName = `fullpos_cert_auth_http_e2e_${Date.now()}`;
    adminUrl = replaceDbName(baseUrl, "postgres");
    const appUrl = replaceDbName(baseUrl, dbName);
    if (!SAFE_DB.test(dbName)) throw new Error("Unsafe E2E DB name");

    const admin = new Client({ connectionString: adminUrl });
    await admin.connect();
    await admin.query(`CREATE DATABASE ${dbName}`);
    await admin.end();

    process.env.DATABASE_URL = appUrl;
    process.env.JWT_SECRET =
      process.env.JWT_SECRET || "ecf-cert-auth-http-e2e-secret";
    process.env[PLATFORM_STAFF_ENV] = "";
    // Ninguna bandera de emisión se activa en este archivo.
    process.env.DOSA_EMISSION_ENABLED = "false";
    process.env.DOSA_PRODUCTION_EMISSION_ENABLED = "false";

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
      const adminClient = new Client({ connectionString: adminUrl });
      await adminClient.connect();
      await adminClient.query(
        `SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = $1 AND pid <> pg_backend_pid()`,
        [dbName],
      );
      await adminClient.query(`DROP DATABASE IF EXISTS ${dbName}`);
      await adminClient.end();
    }
  }, 120000);

  afterEach(() => {
    process.env[PLATFORM_STAFF_ENV] = "";
  });

  /** Empresa + administrador reales, creados por HTTP. */
  async function registerTenant(suffix: string) {
    const email = `cert-auth-e2e-${Date.now()}-${suffix}@example.test`;
    const res = await http()
      .post("/auth/register-business")
      .send({
        firstName: "Cert",
        lastName: suffix,
        email,
        phone: "8095550000",
        password: PASSWORD,
        confirmPassword: PASSWORD,
        commercialName: `Cert ${suffix}`,
        taxId: `1${Date.now().toString().slice(-8)}${Math.floor(
          Math.random() * 9,
        )}`,
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

  async function grantSupport(token: string) {
    await http()
      .post("/ecf/dgii/support-grants")
      .set("Authorization", `Bearer ${token}`)
      .send({
        scopes: ["VIEW_DOSSIER", "REVIEW_EVIDENCE", "REQUEST_CORRECTION"],
        expiresAt: new Date(Date.now() + 7 * 24 * 60 * 60 * 1000).toISOString(),
        reason: "UAT: asistencia de plataforma para certificación",
      })
      .expect(201);
  }

  /** Configuración e-CF en un estado concreto. Es preparación, no lo probado. */
  async function seedConfiguration(
    companyId: string,
    certificationStatus: EcfCertificationStatus = EcfCertificationStatus.NOT_STARTED,
  ) {
    await prisma.ecfCompanyConfiguration.upsert({
      where: { companyId },
      create: {
        companyId,
        enabled: false,
        provider: "DOSA",
        environment: "SANDBOX",
        certificationStatus,
      },
      update: { certificationStatus },
    });
  }

  function statusUrl(companyId: string) {
    return `/ecf/platform/dosa/certification/${companyId}`;
  }

  function authorizeUrl(companyId: string) {
    return `/ecf/platform/dosa/certification/${companyId}/authorize`;
  }

  function revokeUrl(companyId: string) {
    return `/ecf/platform/dosa/certification/${companyId}/revoke`;
  }

  async function certificationOf(companyId: string) {
    const row = await prisma.ecfCompanyConfiguration.findUnique({
      where: { companyId },
      select: { certificationStatus: true, enabled: true, productionEnabled: true },
    });
    return row;
  }

  async function auditRows(companyId: string) {
    return prisma.ecfAuditLog.findMany({
      where: { companyId, targetType: "ECF_CERTIFICATION_AUTHORIZATION" },
      orderBy: { createdAt: "asc" },
    });
  }

  it("un administrador de empresa no puede autorizar su propia emisión (403)", async () => {
    const tenant = await registerTenant("tenant");
    await seedConfiguration(tenant.companyId);

    await http()
      .post(authorizeUrl(tenant.companyId))
      .set("Authorization", `Bearer ${tenant.token}`)
      .send({ target: "PRODUCTION_READY", reason: "Autoconcesión indebida" })
      .expect(403);

    expect((await certificationOf(tenant.companyId))?.certificationStatus).toBe(
      EcfCertificationStatus.NOT_STARTED,
    );
  });

  it("sin concesión de soporte, el personal de plataforma tampoco (403)", async () => {
    const tenant = await registerTenant("nogr");
    const staff = await registerTenant("staff");
    await seedConfiguration(tenant.companyId);
    setStaff(staff.userId);

    await http()
      .post(authorizeUrl(tenant.companyId))
      .set("Authorization", `Bearer ${staff.token}`)
      .send({ target: "AUTHORIZED_SANDBOX", reason: "Sin concesión del cliente" })
      .expect(403);
  });

  it("con concesión, el staff autoriza sandbox y queda actor, motivo y auditoría", async () => {
    const tenant = await registerTenant("grant");
    const staff = await registerTenant("staffok");
    await seedConfiguration(tenant.companyId);
    await grantSupport(tenant.token);
    setStaff(staff.userId);

    const res = await http()
      .post(authorizeUrl(tenant.companyId))
      .set("Authorization", `Bearer ${staff.token}`)
      .send({
        target: "AUTHORIZED_SANDBOX",
        reason: "Pruebas de emisión en ambiente de certificación",
        evidenceReference: "DOSA-TEST-2026-001",
      })
      .expect(201);

    expect(res.body).toMatchObject({
      companyId: tenant.companyId,
      changed: true,
      from: "NOT_STARTED",
      to: "AUTHORIZED_SANDBOX",
    });

    const config = await certificationOf(tenant.companyId);
    expect(config?.certificationStatus).toBe(
      EcfCertificationStatus.AUTHORIZED_SANDBOX,
    );

    const audit = await auditRows(tenant.companyId);
    expect(audit).toHaveLength(1);
    expect(audit[0]).toMatchObject({
      companyId: tenant.companyId,
      actorUserId: staff.userId,
      before: { certificationStatus: "NOT_STARTED" },
      after: { certificationStatus: "AUTHORIZED_SANDBOX" },
    });
    expect(audit[0].metadata).toMatchObject({
      operation: "CERTIFICATION_STATUS_AUTHORIZED",
      reason: "Pruebas de emisión en ambiente de certificación",
      evidenceReference: "DOSA-TEST-2026-001",
      target: "AUTHORIZED_SANDBOX",
    });
  });

  it("repetir la misma autorización no duplica escritura ni auditoría", async () => {
    const tenant = await registerTenant("idem");
    const staff = await registerTenant("staffidem");
    await seedConfiguration(tenant.companyId);
    await grantSupport(tenant.token);
    setStaff(staff.userId);

    const body = {
      target: "AUTHORIZED_SANDBOX",
      reason: "Autorización de sandbox para pruebas",
    };
    const first = await http()
      .post(authorizeUrl(tenant.companyId))
      .set("Authorization", `Bearer ${staff.token}`)
      .send(body)
      .expect(201);
    const second = await http()
      .post(authorizeUrl(tenant.companyId))
      .set("Authorization", `Bearer ${staff.token}`)
      .send(body)
      .expect(201);

    expect(first.body.changed).toBe(true);
    expect(second.body.changed).toBe(false);
    expect(await auditRows(tenant.companyId)).toHaveLength(1);
  });

  it("producción exige sandbox previo y luego se concede", async () => {
    const tenant = await registerTenant("prod");
    const staff = await registerTenant("staffprod");
    await seedConfiguration(tenant.companyId);
    await grantSupport(tenant.token);
    setStaff(staff.userId);

    const refused = await http()
      .post(authorizeUrl(tenant.companyId))
      .set("Authorization", `Bearer ${staff.token}`)
      .send({
        target: "PRODUCTION_READY",
        reason: "Intento de saltar el ambiente de certificación",
      })
      .expect(409);
    expect(refused.body.message).toBe("ECF_CERTIFICATION_SANDBOX_REQUIRED");
    expect((await certificationOf(tenant.companyId))?.certificationStatus).toBe(
      EcfCertificationStatus.NOT_STARTED,
    );

    await http()
      .post(authorizeUrl(tenant.companyId))
      .set("Authorization", `Bearer ${staff.token}`)
      .send({
        target: "AUTHORIZED_SANDBOX",
        reason: "Sandbox autorizado antes de producción",
      })
      .expect(201);

    const granted = await http()
      .post(authorizeUrl(tenant.companyId))
      .set("Authorization", `Bearer ${staff.token}`)
      .send({
        target: "PRODUCTION_READY",
        reason: "Certificación de producción aprobada por dirección",
      })
      .expect(201);
    expect(granted.body).toMatchObject({
      from: "AUTHORIZED_SANDBOX",
      to: "PRODUCTION_READY",
      changed: true,
    });
  });

  it("no rebaja una autorización de producción a sandbox (409)", async () => {
    const tenant = await registerTenant("down");
    const staff = await registerTenant("staffdown");
    await seedConfiguration(tenant.companyId, EcfCertificationStatus.PRODUCTION_READY);
    await grantSupport(tenant.token);
    setStaff(staff.userId);

    const res = await http()
      .post(authorizeUrl(tenant.companyId))
      .set("Authorization", `Bearer ${staff.token}`)
      .send({
        target: "AUTHORIZED_SANDBOX",
        reason: "Rebajar la autorización vigente sin motivo fiscal",
      })
      .expect(409);
    expect(res.body.message).toBe("ECF_CERTIFICATION_DOWNGRADE_NOT_ALLOWED");
  });

  it("una empresa bloqueada no se autoriza: la evidencia manda", async () => {
    const tenant = await registerTenant("blocked");
    const staff = await registerTenant("staffblocked");
    await seedConfiguration(tenant.companyId, EcfCertificationStatus.BLOCKED);
    await grantSupport(tenant.token);
    setStaff(staff.userId);

    const res = await http()
      .post(authorizeUrl(tenant.companyId))
      .set("Authorization", `Bearer ${staff.token}`)
      .send({
        target: "AUTHORIZED_SANDBOX",
        reason: "Autorizar pese al bloqueo vigente del expediente",
      })
      .expect(409);
    expect(res.body.message).toBe("ECF_CERTIFICATION_STATE_BLOCKED");
    expect((await certificationOf(tenant.companyId))?.certificationStatus).toBe(
      EcfCertificationStatus.BLOCKED,
    );
  });

  it("revocar deja SUSPENDED, y reactivar exige una autorización nueva", async () => {
    const tenant = await registerTenant("revoke");
    const staff = await registerTenant("staffrevoke");
    await seedConfiguration(tenant.companyId, EcfCertificationStatus.PRODUCTION_READY);
    await grantSupport(tenant.token);
    setStaff(staff.userId);

    const revoked = await http()
      .post(revokeUrl(tenant.companyId))
      .set("Authorization", `Bearer ${staff.token}`)
      .send({ reason: "Incidente fiscal: se retira la autorización de emisión" })
      .expect(201);
    expect(revoked.body).toMatchObject({
      changed: true,
      from: "PRODUCTION_READY",
      to: "SUSPENDED",
    });
    expect((await certificationOf(tenant.companyId))?.certificationStatus).toBe(
      EcfCertificationStatus.SUSPENDED,
    );

    // Repetir la revocación es idempotente, no un error.
    const again = await http()
      .post(revokeUrl(tenant.companyId))
      .set("Authorization", `Bearer ${staff.token}`)
      .send({ reason: "Se repite la revocación por reintento de la interfaz" })
      .expect(201);
    expect(again.body.changed).toBe(false);

    // Reactivar: sandbox primero (no salta a producción).
    const lift = await http()
      .post(authorizeUrl(tenant.companyId))
      .set("Authorization", `Bearer ${staff.token}`)
      .send({
        target: "AUTHORIZED_SANDBOX",
        reason: "Reactivación tras resolver el incidente fiscal",
      })
      .expect(201);
    expect(lift.body).toMatchObject({
      from: "SUSPENDED",
      to: "AUTHORIZED_SANDBOX",
      changed: true,
    });

    // Las dos operaciones quedaron auditadas, la revocación con su motivo.
    const audit = await auditRows(tenant.companyId);
    expect(audit.map((row) => (row.metadata as { operation: string }).operation)).toEqual([
      "CERTIFICATION_STATUS_REVOKED",
      "CERTIFICATION_STATUS_AUTHORIZED",
    ]);
  });

  it("sin configuración e-CF responde 404 y no crea la fila", async () => {
    const tenant = await registerTenant("nocfg");
    const staff = await registerTenant("staffnocfg");
    await grantSupport(tenant.token);
    setStaff(staff.userId);

    await prisma.ecfCompanyConfiguration.deleteMany({
      where: { companyId: tenant.companyId },
    });

    await http()
      .post(authorizeUrl(tenant.companyId))
      .set("Authorization", `Bearer ${staff.token}`)
      .send({
        target: "AUTHORIZED_SANDBOX",
        reason: "Autorizar una empresa que no inició el trámite e-CF",
      })
      .expect(404);

    expect(await certificationOf(tenant.companyId)).toBeNull();
  });

  it("un objetivo fuera del catálogo o un motivo corto son 400", async () => {
    const tenant = await registerTenant("valida");
    const staff = await registerTenant("staffvalida");
    await seedConfiguration(tenant.companyId);
    await grantSupport(tenant.token);
    setStaff(staff.userId);

    await http()
      .post(authorizeUrl(tenant.companyId))
      .set("Authorization", `Bearer ${staff.token}`)
      .send({ target: "DGII_ACCEPTED", reason: "Estado inventado por el cliente" })
      .expect(400);

    await http()
      .post(authorizeUrl(tenant.companyId))
      .set("Authorization", `Bearer ${staff.token}`)
      .send({ target: "AUTHORIZED_SANDBOX", reason: "corto" })
      .expect(400);
  });

  it("autorizar una empresa no toca el estado de otra", async () => {
    const a = await registerTenant("iso-a");
    const b = await registerTenant("iso-b");
    const staff = await registerTenant("staffiso");
    await seedConfiguration(a.companyId);
    await seedConfiguration(b.companyId);
    await grantSupport(a.token);
    await grantSupport(b.token);
    setStaff(staff.userId);

    await http()
      .post(authorizeUrl(a.companyId))
      .set("Authorization", `Bearer ${staff.token}`)
      .send({
        target: "AUTHORIZED_SANDBOX",
        reason: "Autorización de la empresa A únicamente",
      })
      .expect(201);

    expect((await certificationOf(a.companyId))?.certificationStatus).toBe(
      EcfCertificationStatus.AUTHORIZED_SANDBOX,
    );
    expect((await certificationOf(b.companyId))?.certificationStatus).toBe(
      EcfCertificationStatus.NOT_STARTED,
    );
    expect(await auditRows(b.companyId)).toHaveLength(0);
  });

  it("la autorización NO habilita la emisión: enabled y banderas siguen apagadas", async () => {
    const tenant = await registerTenant("noemit");
    const staff = await registerTenant("staffnoemit");
    await seedConfiguration(tenant.companyId);
    await grantSupport(tenant.token);
    setStaff(staff.userId);

    await http()
      .post(authorizeUrl(tenant.companyId))
      .set("Authorization", `Bearer ${staff.token}`)
      .send({
        target: "AUTHORIZED_SANDBOX",
        reason: "Autorización de sandbox sin habilitar la emisión",
      })
      .expect(201);

    const config = await certificationOf(tenant.companyId);
    // La compuerta de certificación se levantó, pero la empresa sigue sin e-CF
    // habilitado: la autorización no es un interruptor de emisión.
    expect(config?.certificationStatus).toBe(
      EcfCertificationStatus.AUTHORIZED_SANDBOX,
    );
    expect(config?.enabled).toBe(false);
    expect(config?.productionEnabled).toBe(false);
    expect(process.env.DOSA_EMISSION_ENABLED).toBe("false");
    expect(process.env.DOSA_PRODUCTION_EMISSION_ENABLED).toBe("false");
  });

  it("tocar una etapa de onboarding no degrada la autorización concedida", async () => {
    const tenant = await registerTenant("step");
    const staff = await registerTenant("staffstep");
    await seedConfiguration(tenant.companyId);
    await grantSupport(tenant.token);
    setStaff(staff.userId);

    await http()
      .post(authorizeUrl(tenant.companyId))
      .set("Authorization", `Bearer ${staff.token}`)
      .send({
        target: "AUTHORIZED_SANDBOX",
        reason: "Autorización previa a la actualización de etapas",
      })
      .expect(201);

    await prisma.ecfOnboardingStep.create({
      data: {
        companyId: tenant.companyId,
        stepKey: "FISCAL_CONFIG",
        status: "IN_PROGRESS",
      },
    });

    await http()
      .patch("/ecf/onboarding/steps/FISCAL_CONFIG")
      .set("Authorization", `Bearer ${tenant.token}`)
      .send({ status: "COMPLETED", resultSummary: "Configuración revisada" })
      .expect(200);

    // `resolveCertificationStatus` solo promociona: la etapa no puede rebajar
    // una autorización legítima.
    expect((await certificationOf(tenant.companyId))?.certificationStatus).toBe(
      EcfCertificationStatus.AUTHORIZED_SANDBOX,
    );
  });

  it("el snapshot informa el estado y los objetivos alcanzables", async () => {
    const tenant = await registerTenant("snap");
    const staff = await registerTenant("staffsnap");
    await seedConfiguration(tenant.companyId);
    await grantSupport(tenant.token);
    setStaff(staff.userId);

    const before = await http()
      .get(statusUrl(tenant.companyId))
      .set("Authorization", `Bearer ${staff.token}`)
      .expect(200);
    expect(before.body).toMatchObject({
      companyId: tenant.companyId,
      certificationStatus: "NOT_STARTED",
      enabled: false,
      // Sin sandbox previo, producción no está disponible.
      availableTargets: ["AUTHORIZED_SANDBOX"],
      history: [],
    });

    await http()
      .post(authorizeUrl(tenant.companyId))
      .set("Authorization", `Bearer ${staff.token}`)
      .send({
        target: "AUTHORIZED_SANDBOX",
        reason: "Autorización de sandbox para ver el histórico",
      })
      .expect(201);

    const after = await http()
      .get(statusUrl(tenant.companyId))
      .set("Authorization", `Bearer ${staff.token}`)
      .expect(200);
    expect(after.body.certificationStatus).toBe("AUTHORIZED_SANDBOX");
    expect(after.body.availableTargets).toEqual([
      "AUTHORIZED_SANDBOX",
      "PRODUCTION_READY",
    ]);
    expect(after.body.history).toHaveLength(1);
    expect(after.body.history[0]).toMatchObject({
      operation: "CERTIFICATION_STATUS_AUTHORIZED",
      from: "NOT_STARTED",
      to: "AUTHORIZED_SANDBOX",
      actorUserId: staff.userId,
    });
  });
});
