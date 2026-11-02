import { INestApplication, ValidationPipe } from "@nestjs/common";
import { Test } from "@nestjs/testing";
import { randomUUID } from "node:crypto";
import { execFileSync } from "node:child_process";
import { existsSync, readFileSync } from "node:fs";
import { resolve } from "node:path";
import { Client } from "pg";
import jwt from "jsonwebtoken";
import request from "supertest";
import { AppModule } from "../../../app.module";
import { PrismaService } from "../../../prisma/prisma.service";

/**
 * E2E HTTP REAL de la preasociación empresa ↔ RNC de DOSA.
 *
 * A diferencia de la prueba de controlador, aquí **no se inyecta `req.user`**:
 * se levanta la aplicación completa, se crean empresas y administradores por
 * HTTP con `POST /auth/register-business`, se obtiene un JWT real con
 * `POST /auth/login` y se llama al endpoint con `Authorization: Bearer …`. Pasan
 * de verdad el `AuthGuard`, el `JwtStrategy` (sesión activa en base), el
 * `RolesGuard`, el `ValidationPipe` global y el controlador.
 *
 * Límites declarados:
 *  - Base de datos DESECHABLE creada para esta ejecución y destruida al final.
 *  - No se llama a DOSA, no se emite nada, no se toca DGII ni UAT ni producción.
 *  - El proveedor no interviene en ningún momento: solo se prueba el vínculo
 *    interno empresa ↔ RNC.
 */
jest.setTimeout(300000);

const PASSWORD = "DosaIntentHttpE2E123!";
const SAFE_DB = /^fullpos_dosa_intent_jwt_e2e_/;
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

/** El CLI de Prisma puede estar hoisteado en la raíz o en el paquete. */
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

uat("Preasociación DOSA — E2E HTTP con JWT real", () => {
  let app: INestApplication;
  let prisma: PrismaService;
  let dbName: string;
  let appUrl: string;
  let adminUrl: string;
  let jwtSecret: string;

  const http = () => request(app.getHttpServer());

  let fleetCounter = 0;
  function nextFleetNumber() {
    fleetCounter += 1;
    return String(950000 + fleetCounter);
  }

  beforeAll(async () => {
    if (process.env.ALANUBE_ENABLE_REAL_CALLS !== "false") {
      throw new Error("E2E_REFUSES_REAL_PROVIDER_CALLS");
    }
    const base = baseDatabaseUrl();
    dbName = `fullpos_dosa_intent_jwt_e2e_${Date.now()}`;
    if (!SAFE_DB.test(dbName)) throw new Error("Unsafe E2E DB name");
    adminUrl = replaceDbName(base, "postgres");
    appUrl = replaceDbName(base, dbName);

    const admin = new Client({ connectionString: adminUrl });
    await admin.connect();
    await admin.query(`CREATE DATABASE ${dbName}`);
    await admin.end();

    process.env.DATABASE_URL = appUrl;
    jwtSecret = process.env.JWT_SECRET || "dosa-intent-http-e2e-secret";
    process.env.JWT_SECRET = jwtSecret;

    const prismaCli = prismaCliPath();
    execFileSync(process.execPath, [prismaCli, "migrate", "deploy"], {
      cwd: process.cwd(),
      env: { ...process.env, DATABASE_URL: appUrl },
      stdio: "pipe",
    });

    const moduleRef = await Test.createTestingModule({
      imports: [AppModule],
    }).compile();
    app = moduleRef.createNestApplication();
    // Misma validación global que `main.ts`: si aquí no estuviera, el arnés no
    // probaría el contrato real (un `companyId` colado pasaría sin filtro).
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

  /** Empresa + administrador reales, creados por la vía legítima de la app. */
  async function registerTenant(suffix: string, taxId?: string) {
    const email = `dosa-e2e-${Date.now()}-${suffix}-${randomUUID().slice(0, 6)}@example.test`;
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
        taxId: taxId ?? `1${Date.now().toString().slice(-8)}`,
        businessPhone: "8095551111",
        address: `Av. Sintética ${suffix}`,
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

  async function login(email: string) {
    const res = await http()
      .post("/auth/login")
      .send({ email, password: PASSWORD })
      .expect(201);
    return res.body.accessToken as string;
  }

  async function createOperator(
    adminToken: string,
    permissions: Record<string, boolean>,
  ) {
    const email = `dosa-op-${Date.now()}-${randomUUID().slice(0, 6)}@example.test`;
    const fleet = nextFleetNumber();
    await http()
      .post("/users")
      .set("Authorization", `Bearer ${adminToken}`)
      .send({
        email,
        password: PASSWORD,
        nombreCompleto: "Operador sin e-CF",
        telefono: `809555${fleet.slice(-4)}`,
        numeroFlota: fleet,
        edad: 30,
        role: "VENDEDOR",
        userPermissions: permissions,
      })
      .expect(201);
    return { email, token: await login(email) };
  }

  async function sessions(companyId: string) {
    return prisma.$queryRaw<Array<{ id: string; rnc: string; status: string }>>`
      SELECT "id","rnc","status" FROM "ecf_dosa_certification_sessions"
       WHERE "company_id" = ${companyId}::uuid
    `;
  }

  /**
   * La configuración fiscal se lee con SQL crudo y `provider::text` porque el
   * cliente Prisma generado en este entorno solo conoce `ALANUBE`; el módulo de
   * producción lee exactamente igual por el mismo motivo.
   */
  async function fiscalConfig(companyId: string) {
    const rows = await prisma.$queryRaw<
      Array<{
        enabled: boolean;
        production_enabled: boolean;
        certification_status: string;
        provider: string;
      }>
    >`
      SELECT "enabled", "production_enabled",
             "certification_status"::text AS "certification_status",
             "provider"::text AS "provider"
        FROM "ecf_company_configurations"
       WHERE "company_id" = ${companyId}::uuid
    `;
    return rows[0] ?? null;
  }

  it("un administrador prepara DOSA con la emisión DESACTIVADA (HTTP real)", async () => {
    const tenant = await registerTenant("admin-desactivado");

    // Estado de partida: empresa recién creada, sin nada de e-CF.
    expect(await fiscalConfig(tenant.companyId)).toBeNull();

    const res = await http()
      .post("/ecf/dosa/certification-intent")
      .set("Authorization", `Bearer ${tenant.token}`)
      .send({})
      .expect(200);

    expect(res.body).toMatchObject({
      ok: true,
      companyId: tenant.companyId,
      created: true,
      ecfEnabled: false,
      fiscalAuthorizationGranted: false,
    });
    // El RNC lo puso el servidor desde el expediente fiscal, no el cliente.
    expect(res.body.rnc).toBeTruthy();

    // La intención EXISTE en PostgreSQL antes de abrir el asistente.
    const rows = await sessions(tenant.companyId);
    expect(rows).toHaveLength(1);
    expect(rows[0].rnc).toBe(res.body.rnc);

    // Y preparar no ha inventado configuración fiscal ni credenciales.
    expect(await fiscalConfig(tenant.companyId)).toBeNull();
    const credentials = await prisma.$queryRaw<Array<{ n: number }>>`
      SELECT count(*)::int AS "n" FROM "ecf_dosa_company_credentials"
       WHERE "company_id" = ${tenant.companyId}::uuid
    `;
    expect(credentials[0].n).toBe(0);

    // El estado se puede consultar al regresar.
    const state = await http()
      .get("/ecf/dosa/certification-intent")
      .set("Authorization", `Bearer ${tenant.token}`)
      .expect(200);
    expect(state.body.canRegister).toBe(true);
    expect(state.body.blockingReasons).toEqual([]);
    expect(state.body.session?.id).toBe(rows[0].id);
  });

  it("con configuración fiscal presente y `enabled=false` tampoco se bloquea", async () => {
    const tenant = await registerTenant("config-apagada");
    await prisma.$executeRaw`
      INSERT INTO "ecf_company_configurations" ("id","company_id","enabled","provider","production_enabled")
      VALUES (gen_random_uuid(), ${tenant.companyId}::uuid, false, 'DOSA', false)
    `;

    await http()
      .post("/ecf/dosa/certification-intent")
      .set("Authorization", `Bearer ${tenant.token}`)
      .send({})
      .expect(200);

    const config = await fiscalConfig(tenant.companyId);
    // Preparar no enciende nada: ni el módulo ni la emisión.
    expect(config).toMatchObject({
      enabled: false,
      production_enabled: false,
      certification_status: "NOT_STARTED",
    });
    expect(await sessions(tenant.companyId)).toHaveLength(1);
  });

  it("un usuario sin privilegios recibe 403 y no crea nada", async () => {
    const tenant = await registerTenant("sin-privilegios");
    const operator = await createOperator(tenant.token, {});

    await http()
      .post("/ecf/dosa/certification-intent")
      .set("Authorization", `Bearer ${operator.token}`)
      .send({})
      .expect(403);

    await http()
      .get("/ecf/dosa/certification-intent")
      .set("Authorization", `Bearer ${operator.token}`)
      .expect(403);

    expect(await sessions(tenant.companyId)).toHaveLength(0);
  });

  it("un JWT inválido o vencido no pasa de la guarda", async () => {
    const bogus = "Bearer este-token-no-es-un-jwt";
    await http()
      .post("/ecf/dosa/certification-intent")
      .set("Authorization", bogus)
      .send({})
      .expect(401);

    const tenant = await registerTenant("jwt-vencido");
    const expired = jwt.sign(
      {
        sub: tenant.userId,
        companyId: tenant.companyId,
        role: "ADMIN",
        tokenType: "access",
      },
      jwtSecret,
      { expiresIn: "-10s" },
    );
    await http()
      .post("/ecf/dosa/certification-intent")
      .set("Authorization", `Bearer ${expired}`)
      .send({})
      .expect(401);

    expect(await sessions(tenant.companyId)).toHaveLength(0);
  });

  it("no se puede tocar otra empresa: ni por cuerpo ni por token ajeno", async () => {
    const a = await registerTenant("empresa-a");
    const b = await registerTenant("empresa-b");

    // Un `companyId` en el cuerpo lo rechaza el ValidationPipe global.
    await http()
      .post("/ecf/dosa/certification-intent")
      .set("Authorization", `Bearer ${a.token}`)
      .send({ companyId: b.companyId })
      .expect(400);

    // Con su token limpio, A solo afecta a A.
    const res = await http()
      .post("/ecf/dosa/certification-intent")
      .set("Authorization", `Bearer ${a.token}`)
      .send({})
      .expect(200);
    expect(res.body.companyId).toBe(a.companyId);

    expect(await sessions(a.companyId)).toHaveLength(1);
    expect(await sessions(b.companyId)).toHaveLength(0);

    // B consulta su estado y no ve la sesión de A.
    const stateB = await http()
      .get("/ecf/dosa/certification-intent")
      .set("Authorization", `Bearer ${b.token}`)
      .expect(200);
    expect(stateB.body.session).toBeNull();
  });

  it("sin RNC verificado en el expediente se rechaza con 409", async () => {
    const tenant = await registerTenant("sin-rnc");
    // `app_config.rnc` es NOT NULL: el estado realista es cadena vacía, no nulo.
    await prisma.$executeRaw`
      UPDATE "app_config" SET "rnc" = '' WHERE "company_id" = ${tenant.companyId}::uuid
    `;

    const res = await http()
      .post("/ecf/dosa/certification-intent")
      .set("Authorization", `Bearer ${tenant.token}`)
      .send({})
      .expect(409);
    expect(res.body.message).toBe("COMPANY_RNC_NOT_VERIFIED");
    expect(await sessions(tenant.companyId)).toHaveLength(0);
  });

  it("dos empresas con el mismo RNC quedan AMBAS bloqueadas", async () => {
    const a = await registerTenant("rnc-compartido-a");
    const b = await registerTenant("rnc-compartido-b");

    const rncA = (
      await prisma.appConfig.findFirst({ where: { companyId: a.companyId } })
    )?.rnc;
    expect(rncA).toBeTruthy();
    // B pasa a declarar el mismo RNC (estado de configuración, no un bug).
    await prisma.$executeRaw`
      UPDATE "app_config" SET "rnc" = ${rncA} WHERE "company_id" = ${b.companyId}::uuid
    `;

    const resA = await http()
      .post("/ecf/dosa/certification-intent")
      .set("Authorization", `Bearer ${a.token}`)
      .send({})
      .expect(409);
    expect(resA.body.message).toBe("AMBIGUOUS_RNC");

    const resB = await http()
      .post("/ecf/dosa/certification-intent")
      .set("Authorization", `Bearer ${b.token}`)
      .send({})
      .expect(409);
    expect(resB.body.message).toBe("AMBIGUOUS_RNC");

    // Ninguna de las dos se asocia: no se elige "la primera que llegó".
    expect(await sessions(a.companyId)).toHaveLength(0);
    expect(await sessions(b.companyId)).toHaveLength(0);
  });

  it("repetir es idempotente y una ráfaga simultánea crea UNA sola sesión", async () => {
    const tenant = await registerTenant("idempotencia");

    const first = await http()
      .post("/ecf/dosa/certification-intent")
      .set("Authorization", `Bearer ${tenant.token}`)
      .send({})
      .expect(200);
    expect(first.body.created).toBe(true);

    const second = await http()
      .post("/ecf/dosa/certification-intent")
      .set("Authorization", `Bearer ${tenant.token}`)
      .send({})
      .expect(200);
    expect(second.body.created).toBe(false);
    expect(second.body.sessionId).toBe(first.body.sessionId);

    // Ráfaga simultánea: el corte por empresa responde 409, no duplica.
    const burst = await Promise.all(
      Array.from({ length: 5 }, () =>
        http()
          .post("/ecf/dosa/certification-intent")
          .set("Authorization", `Bearer ${tenant.token}`)
          .send({}),
      ),
    );
    for (const res of burst) {
      expect([200, 409]).toContain(res.status);
    }

    expect(await sessions(tenant.companyId)).toHaveLength(1);
  });
});
