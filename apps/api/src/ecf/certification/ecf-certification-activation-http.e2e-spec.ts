import { INestApplication, ValidationPipe } from "@nestjs/common";
import { Test } from "@nestjs/testing";
import { EcfCertificationStatus } from "@prisma/client";
import { execFileSync } from "node:child_process";
import { randomUUID } from "node:crypto";
import { readFileSync } from "node:fs";
import { Client } from "pg";
import request from "supertest";

import { AppModule } from "../../app.module";
import { PrismaService } from "../../prisma/prisma.service";
import { resolvePrismaCliPath } from "../../testing/prisma-cli";
import { PLATFORM_STAFF_ENV } from "../platform/platform-staff.guard";

/**
 * E2E HTTP del CIRCUITO AUTOSERVICIO de emisión e-CF.
 *
 * Demuestra la propiedad que el producto exige: **el cliente completa todo su
 * trámite y queda autorizado para facturar sin que nadie de Fulltech
 * intervenga**.
 *
 * La prueba corre con `PLATFORM_STAFF_ENV` **vacío** a propósito: si algo
 * necesitara personal de plataforma, fallaría. Y no se crea ninguna concesión de
 * asistencia, así que las rutas de plataforma responderían 403.
 *
 * Qué se prueba:
 *  1. Con evidencia completa (credencial activa), el cliente se autoriza solo.
 *  2. La autorización es idempotente y no duplica auditoría.
 *  3. La derivación se registra con actor `null` (fue el sistema).
 *  4. Credencial de producción → `PRODUCTION_READY`.
 *  5. Credencial revocada no se resucita.
 *  6. `BLOCKED` no se salta y `SUSPENDED` no se levanta.
 *  7. Sin configuración e-CF no se inventa nada.
 *  8. Una empresa no puede autorizar a otra (no hay `companyId` en la ruta).
 *  9. Sin token no hay acceso.
 *
 * No llama a DOSA ni a la DGII: se siembra el estado de la credencial, que es lo
 * único que el servicio lee. `ALANUBE_ENABLE_REAL_CALLS=false` es obligatorio.
 */
jest.setTimeout(300000);

const PASSWORD = "EcfSelfActivationE2E123!";
const SAFE_DB = /^fullpos_self_activation_http_e2e_/;
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

uat("e-CF autoservicio — activación y autorización por el propio cliente", () => {
  let app: INestApplication;
  let prisma: PrismaService;
  let dbName: string;
  let adminUrl: string;

  const http = () => request(app.getHttpServer());
  const ATTEMPT_ROUTE = "/ecf/dosa/activation/attempt";

  beforeAll(async () => {
    if (process.env.ALANUBE_ENABLE_REAL_CALLS !== "false") {
      throw new Error("E2E_REFUSES_REAL_PROVIDER_CALLS");
    }
    const baseUrl = baseDatabaseUrl();
    dbName = `fullpos_self_activation_http_e2e_${Date.now()}`;
    adminUrl = replaceDbName(baseUrl, "postgres");
    const appUrl = replaceDbName(baseUrl, dbName);
    if (!SAFE_DB.test(dbName)) throw new Error("Unsafe E2E DB name");

    const admin = new Client({ connectionString: adminUrl });
    await admin.connect();
    await admin.query(`CREATE DATABASE ${dbName}`);
    await admin.end();

    process.env.DATABASE_URL = appUrl;
    process.env.JWT_SECRET =
      process.env.JWT_SECRET || "ecf-self-activation-http-e2e-secret";
    // Ningún personal de plataforma: si el circuito lo necesitara, fallaría.
    process.env[PLATFORM_STAFF_ENV] = "";
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

  async function registerTenant(suffix: string) {
    const email = `self-activation-${Date.now()}-${suffix}@example.test`;
    const res = await http()
      .post("/auth/register-business")
      .send({
        firstName: "Auto",
        lastName: suffix,
        email,
        phone: "8095550000",
        password: PASSWORD,
        confirmPassword: PASSWORD,
        commercialName: `Auto ${suffix}`,
        taxId: `3${Date.now().toString().slice(-8)}${Math.floor(Math.random() * 9)}`,
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

  async function seedConfiguration(
    companyId: string,
    certificationStatus: EcfCertificationStatus = EcfCertificationStatus.NOT_STARTED,
    provider: "DOSA" | "ALANUBE" = "DOSA",
  ) {
    await prisma.ecfCompanyConfiguration.upsert({
      where: { companyId },
      create: {
        companyId,
        enabled: false,
        provider,
        environment: "SANDBOX",
        certificationStatus,
      },
      update: { certificationStatus },
    });
  }

  /**
   * Siembra una credencial DOSA.
   *
   * `listForCompany` no descifra (solo devuelve metadatos), así que el
   * criptograma puede ser ficticio: lo que importa es el estado.
   */
  async function seedCredential(input: {
    companyId: string;
    environment: "test" | "production";
    status: string;
    rnc?: string;
  }) {
    await prisma.$executeRawUnsafe(
      `INSERT INTO "ecf_dosa_company_credentials"
         ("id","company_id","rnc","environment","status","source","key_version","ciphertext","iv","auth_tag","fingerprint","present")
       VALUES ($1::uuid,$2::uuid,$3,$4,$5,'WEBHOOK',1,'ficticio','0000','0000',$6,'{"apiKeyTest":true}'::jsonb)
       ON CONFLICT ("company_id","rnc","environment")
       DO UPDATE SET "status" = EXCLUDED."status"`,
      // El `id` no tiene valor por defecto en la base: Prisma lo genera en el
      // cliente, así que aquí se suministra explícitamente.
      randomUUID(),
      input.companyId,
      input.rnc ?? "101010101",
      input.environment,
      input.status,
      `fp-${input.environment}-${Date.now()}`,
    );
  }

  async function certificationOf(companyId: string) {
    const row = await prisma.ecfCompanyConfiguration.findUnique({
      where: { companyId },
      select: { certificationStatus: true, enabled: true },
    });
    return row;
  }

  async function derivedAudit(companyId: string) {
    return prisma.ecfAuditLog.findMany({
      where: {
        companyId,
        targetType: "ECF_CERTIFICATION_AUTHORIZATION",
      },
    });
  }

  it("el cliente se autoriza solo con su credencial activa, sin personal de plataforma", async () => {
    const tenant = await registerTenant("test");
    await seedConfiguration(tenant.companyId, EcfCertificationStatus.IN_PROGRESS);
    await seedCredential({
      companyId: tenant.companyId,
      environment: "test",
      status: "ACTIVE",
    });

    const res = await http()
      .post(ATTEMPT_ROUTE)
      .set("Authorization", `Bearer ${tenant.token}`)
      .expect(200);

    expect(res.body).toMatchObject({
      ok: true,
      companyId: tenant.companyId,
      changed: true,
      certificationStatus: "AUTHORIZED_SANDBOX",
    });

    expect((await certificationOf(tenant.companyId))?.certificationStatus).toBe(
      EcfCertificationStatus.AUTHORIZED_SANDBOX,
    );

    // La autorización se atribuye al sistema, no a una persona.
    const audit = await derivedAudit(tenant.companyId);
    expect(audit).toHaveLength(1);
    expect(audit[0]).toMatchObject({
      actorUserId: null,
      before: { certificationStatus: "IN_PROGRESS" },
      after: { certificationStatus: "AUTHORIZED_SANDBOX" },
    });
    expect(audit[0].metadata).toMatchObject({
      operation: "CERTIFICATION_STATUS_DERIVED",
    });

    // Y no se habilitó la emisión por sí sola: la bandera global sigue apagada.
    expect((await certificationOf(tenant.companyId))?.enabled).toBe(false);
    expect(process.env.DOSA_EMISSION_ENABLED).toBe("false");
  });

  it("repetirlo es idempotente y no duplica auditoría", async () => {
    const tenant = await registerTenant("idem");
    await seedConfiguration(tenant.companyId, EcfCertificationStatus.IN_PROGRESS);
    await seedCredential({
      companyId: tenant.companyId,
      environment: "test",
      status: "ACTIVE",
    });

    const first = await http()
      .post(ATTEMPT_ROUTE)
      .set("Authorization", `Bearer ${tenant.token}`)
      .expect(200);
    const second = await http()
      .post(ATTEMPT_ROUTE)
      .set("Authorization", `Bearer ${tenant.token}`)
      .expect(200);

    expect(first.body.changed).toBe(true);
    expect(second.body.changed).toBe(false);
    expect(second.body.certificationStatus).toBe("AUTHORIZED_SANDBOX");
    expect(await derivedAudit(tenant.companyId)).toHaveLength(1);
  });

  it("una credencial de producción autoriza producción", async () => {
    const tenant = await registerTenant("prod");
    await seedConfiguration(
      tenant.companyId,
      EcfCertificationStatus.AUTHORIZED_SANDBOX,
    );
    await seedCredential({
      companyId: tenant.companyId,
      environment: "production",
      status: "ACTIVE",
    });

    const res = await http()
      .post(ATTEMPT_ROUTE)
      .set("Authorization", `Bearer ${tenant.token}`)
      .expect(200);

    expect(res.body.certificationStatus).toBe("PRODUCTION_READY");
    expect((await certificationOf(tenant.companyId))?.certificationStatus).toBe(
      EcfCertificationStatus.PRODUCTION_READY,
    );
  });

  it("una credencial revocada no se resucita ni autoriza", async () => {
    const tenant = await registerTenant("revoked");
    await seedConfiguration(tenant.companyId, EcfCertificationStatus.IN_PROGRESS);
    await seedCredential({
      companyId: tenant.companyId,
      environment: "test",
      status: "REVOKED",
    });

    const res = await http()
      .post(ATTEMPT_ROUTE)
      .set("Authorization", `Bearer ${tenant.token}`)
      .expect(200);

    expect(res.body.changed).toBe(false);
    expect(res.body.certificationStatus).toBe("IN_PROGRESS");
    expect(res.body.environments[0]).toMatchObject({
      environment: "test",
      status: "REVOKED",
      activated: false,
      blockingReasons: ["ECF_DOSA_CREDENTIALS_REVOKED"],
    });
    expect(await derivedAudit(tenant.companyId)).toHaveLength(0);
  });

  it("no salta un bloqueo ni levanta una suspensión", async () => {
    const blocked = await registerTenant("blocked");
    await seedConfiguration(blocked.companyId, EcfCertificationStatus.BLOCKED);
    await seedCredential({
      companyId: blocked.companyId,
      environment: "test",
      status: "ACTIVE",
    });

    const blockedRes = await http()
      .post(ATTEMPT_ROUTE)
      .set("Authorization", `Bearer ${blocked.token}`)
      .expect(200);
    expect(blockedRes.body.code).toBe("ECF_CERTIFICATION_STATE_BLOCKED");
    expect((await certificationOf(blocked.companyId))?.certificationStatus).toBe(
      EcfCertificationStatus.BLOCKED,
    );

    const suspended = await registerTenant("suspended");
    await seedConfiguration(
      suspended.companyId,
      EcfCertificationStatus.SUSPENDED,
    );
    await seedCredential({
      companyId: suspended.companyId,
      environment: "test",
      status: "ACTIVE",
    });

    const suspendedRes = await http()
      .post(ATTEMPT_ROUTE)
      .set("Authorization", `Bearer ${suspended.token}`)
      .expect(200);
    expect(suspendedRes.body.changed).toBe(false);
    expect(
      (await certificationOf(suspended.companyId))?.certificationStatus,
    ).toBe(EcfCertificationStatus.SUSPENDED);
  });

  it("sin configuración e-CF responde con el código y no inventa nada", async () => {
    const tenant = await registerTenant("nocfg");
    await prisma.ecfCompanyConfiguration.deleteMany({
      where: { companyId: tenant.companyId },
    });

    const res = await http()
      .post(ATTEMPT_ROUTE)
      .set("Authorization", `Bearer ${tenant.token}`)
      .expect(200);

    expect(res.body.code).toBe("ECF_CERTIFICATION_CONFIGURATION_NOT_FOUND");
    expect(await certificationOf(tenant.companyId)).toBeNull();
  });

  it("cada empresa solo puede evaluar la suya: la ruta no acepta companyId", async () => {
    const a = await registerTenant("iso-a");
    const b = await registerTenant("iso-b");
    await seedConfiguration(a.companyId, EcfCertificationStatus.IN_PROGRESS);
    await seedConfiguration(b.companyId, EcfCertificationStatus.IN_PROGRESS);
    await seedCredential({
      companyId: a.companyId,
      environment: "test",
      status: "ACTIVE",
    });

    // B llama al mismo endpoint: se evalúa B, no A.
    const res = await http()
      .post(ATTEMPT_ROUTE)
      .set("Authorization", `Bearer ${b.token}`)
      .expect(200);

    expect(res.body.companyId).toBe(b.companyId);
    expect(res.body.changed).toBe(false);
    expect((await certificationOf(a.companyId))?.certificationStatus).toBe(
      EcfCertificationStatus.IN_PROGRESS,
    );
    expect(await derivedAudit(a.companyId)).toHaveLength(0);
  });

  it("sin token no hay acceso", async () => {
    await http().post(ATTEMPT_ROUTE).expect(401);
  });
});
