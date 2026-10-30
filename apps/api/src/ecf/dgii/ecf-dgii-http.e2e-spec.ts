import { INestApplication, ValidationPipe } from "@nestjs/common";
import { Test } from "@nestjs/testing";
import { randomUUID } from "node:crypto";
import { execFileSync } from "node:child_process";
import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { Client } from "pg";
import request from "supertest";
import { AppModule } from "../../app.module";
import { PrismaService } from "../../prisma/prisma.service";

/**
 * E2E HTTP de la HABILITACIÓN DGII: guardas reales → controlador → servicio →
 * PostgreSQL, todo por HTTP de verdad (login real, JWT real, `AuthGuard` y
 * `RolesGuard` reales, validación de DTO real).
 *
 * Alcance declarado y límites:
 *  - Se levanta la aplicación completa contra una base DESECHABLE creada para
 *    esta ejecución y se destruye al terminar.
 *  - No hay proveedor, no hay emisión fiscal y no se declara ninguna aceptación
 *    de la DGII: la «autorización oficial» que se registra aquí es un documento
 *    SINTÉTICO de UAT, y el propio módulo sigue diciendo
 *    `realEmissionAuthorized: false`.
 *  - Lo que se prueba de verdad son las GUARDAS y las REGLAS: quién puede tocar
 *    qué, que una declaración manual no se pueda convertir en autorización
 *    oficial, y que los datos no crucen de empresa.
 */
jest.setTimeout(240000);

const PASSWORD = "EcfDgiiHttpE2E123!";
const SAFE_DB = /^fullpos_dgii_http_e2e_/;
// Opt-in: solo corre contra la base efímera de pruebas.
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

uat("e-CF habilitación DGII — E2E HTTP + PostgreSQL desechable", () => {
  let app: INestApplication;
  let prisma: PrismaService;
  let dbName: string;
  let appUrl: string;
  let adminUrl: string;

  const http = () => request(app.getHttpServer());

  // `numeroFlota` es obligatorio al crear un usuario y debe ser numérico.
  let fleetCounter = 0;
  function nextFleetNumber() {
    fleetCounter += 1;
    return String(900000 + fleetCounter);
  }

  beforeAll(async () => {
    if (process.env.ALANUBE_ENABLE_REAL_CALLS !== "false") {
      throw new Error("E2E_REFUSES_REAL_PROVIDER_CALLS");
    }
    const baseUrl = baseDatabaseUrl();
    dbName = `fullpos_dgii_http_e2e_${Date.now()}`;
    adminUrl = replaceDbName(baseUrl, "postgres");
    appUrl = replaceDbName(baseUrl, dbName);
    if (!SAFE_DB.test(dbName)) throw new Error("Unsafe E2E DB name");

    const admin = new Client({ connectionString: adminUrl });
    await admin.connect();
    await admin.query(`CREATE DATABASE ${dbName}`);
    await admin.end();

    process.env.DATABASE_URL = appUrl;
    process.env.JWT_SECRET = process.env.JWT_SECRET || "ecf-dgii-http-e2e-secret";
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
    // Misma validación global que `main.ts`: sin ella el arnés no probaría el
    // contrato real (campos desconocidos, enums y formatos pasarían sin filtro).
    app.useGlobalPipes(
      new ValidationPipe({
        whitelist: true,
        forbidNonWhitelisted: true,
        transform: true,
      }),
    );
    await app.init();
    prisma = app.get(PrismaService);
  }, 240000);

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

  /** Empresa + administrador reales, creados por HTTP. */
  async function registerTenant(suffix: string) {
    const email = `dgii-e2e-${Date.now()}-${suffix}@example.test`;
    const res = await http()
      .post("/auth/register-business")
      .send({
        firstName: "Dgii",
        lastName: suffix,
        email,
        phone: "8095550000",
        password: PASSWORD,
        confirmPassword: PASSWORD,
        commercialName: `DGII ${suffix}`,
        taxId: `1${Date.now().toString().slice(-8)}`,
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

  /** Usuario NO administrador de la misma empresa, con permisos explícitos. */
  async function createOperator(
    adminToken: string,
    permissions: Record<string, boolean>,
  ) {
    const email = `dgii-op-${Date.now()}-${randomUUID().slice(0, 6)}@example.test`;
    const fleet = nextFleetNumber();
    await http()
      .post("/users")
      .set("Authorization", `Bearer ${adminToken}`)
      .send({
        email,
        password: PASSWORD,
        nombreCompleto: "Operador e-CF",
        telefono: `809555${fleet.slice(-4)}`,
        numeroFlota: fleet,
        edad: 30,
        role: "VENDEDOR",
        userPermissions: permissions,
      })
      .expect(201);
    return { email, token: await login(email) };
  }

  type Entry = {
    method: "get" | "post" | "patch";
    path: string;
    body?: Record<string, unknown>;
  };

  /** Toda la superficie DGII, para comprobar sus guardas de una sola vez. */
  function dgiiSurface(evidenceId: string): Entry[] {
    return [
      { method: "get", path: "/ecf/dgii/habilitation" },
      { method: "get", path: "/ecf/dgii/history" },
      { method: "get", path: "/ecf/dgii/evidence" },
      {
        method: "patch",
        path: "/ecf/dgii/habilitation",
        body: { reviewState: "sonda-de-guarda" },
      },
      {
        method: "patch",
        path: "/ecf/dgii/requirements/FISCAL_DATA",
        body: { status: "IN_PROGRESS" },
      },
      {
        method: "post",
        path: "/ecf/dgii/evidence",
        body: {
          source: "MANUAL_DECLARATION",
          kind: "nota",
          storageRef: "uat://synthetic/nota-de-guarda",
        },
      },
      {
        method: "patch",
        path: `/ecf/dgii/evidence/${evidenceId}/review`,
        body: { decision: "REVIEWED" },
      },
      {
        method: "post",
        path: "/ecf/dgii/authorization",
        body: {
          source: "DGII_OFFICIAL_RECORD",
          evidenceId,
          externalId: "DGII-SONDA",
        },
      },
      { method: "post", path: "/ecf/dgii/authorization/revoke" },
    ];
  }

  it("sin token, ninguna ruta de habilitación DGII responde", async () => {
    for (const entry of dgiiSurface(randomUUID())) {
      await http()[entry.method](entry.path).send(entry.body ?? {}).expect(401);
    }
  });

  it("un usuario sin permisos e-CF no puede tocar ninguna ruta DGII", async () => {
    const tenant = await registerTenant("sin-permisos");
    const operator = await createOperator(tenant.token, {});

    for (const entry of dgiiSurface(randomUUID())) {
      await http()
        [entry.method](entry.path)
        .set("Authorization", `Bearer ${operator.token}`)
        .send(entry.body ?? {})
        .expect(403);
    }

    // El administrador de la misma empresa sí entra: la guarda no bloquea por
    // accidente, discrimina por permiso.
    await http()
      .get("/ecf/dgii/habilitation")
      .set("Authorization", `Bearer ${tenant.token}`)
      .expect(200);
  });

  it("los permisos son granulares: gestionar no es revisar ni autorizar", async () => {
    const tenant = await registerTenant("granular");
    // Permiso de GESTIÓN: alcanza para la habilitación y los requisitos, y para
    // registrar evidencia; NO para revisarla, ni para autorizar, ni para consultar.
    const manager = await createOperator(tenant.token, {
      manageEcfOnboarding: true,
    });

    await http()
      .patch("/ecf/dgii/habilitation")
      .set("Authorization", `Bearer ${manager.token}`)
      .send({ reviewState: "en-preparacion-por-gestor" })
      .expect(200);

    await http()
      .patch("/ecf/dgii/requirements/FISCAL_DATA")
      .set("Authorization", `Bearer ${manager.token}`)
      .send({ status: "IN_PROGRESS" })
      .expect(200);

    await http()
      .post("/ecf/dgii/evidence")
      .set("Authorization", `Bearer ${manager.token}`)
      .send({
        source: "MANUAL_DECLARATION",
        kind: "nota",
        storageRef: "uat://synthetic/nota-del-gestor",
      })
      .expect(201);

    // Revisar evidencia: SOLO con `reviewEcfDgiiEvidence`, sin alias.
    await http()
      .patch(`/ecf/dgii/evidence/${randomUUID()}/review`)
      .set("Authorization", `Bearer ${manager.token}`)
      .send({ decision: "REVIEWED" })
      .expect(403);

    // Autorizar y revocar: SOLO con `recordEcfDgiiOfficialVerification`.
    await http()
      .post("/ecf/dgii/authorization")
      .set("Authorization", `Bearer ${manager.token}`)
      .send({
        source: "DGII_OFFICIAL_RECORD",
        evidenceId: randomUUID(),
        externalId: "DGII-GESTOR",
      })
      .expect(403);

    await http()
      .post("/ecf/dgii/authorization/revoke")
      .set("Authorization", `Bearer ${manager.token}`)
      .expect(403);

    // Y consultar exige permiso de VISTA, que el gestor no tiene.
    await http()
      .get("/ecf/dgii/habilitation")
      .set("Authorization", `Bearer ${manager.token}`)
      .expect(403);

    // Reciprocidad: un perfil de SOLO LECTURA consulta pero no modifica nada.
    // Va en otra empresa porque el plan STANDARD limita a 2 usuarios por empresa
    // (`PLAN_LIMIT_REACHED`), regla real de licencia que no se debe sortear.
    const viewerTenant = await registerTenant("solo-lectura");
    const viewer = await createOperator(viewerTenant.token, {
      viewEcfDgiiHabilitation: true,
    });
    await http()
      .get("/ecf/dgii/habilitation")
      .set("Authorization", `Bearer ${viewer.token}`)
      .expect(200);
    await http()
      .get("/ecf/dgii/evidence")
      .set("Authorization", `Bearer ${viewer.token}`)
      .expect(200);
    await http()
      .patch("/ecf/dgii/habilitation")
      .set("Authorization", `Bearer ${viewer.token}`)
      .send({ reviewState: "no-deberia-poder" })
      .expect(403);
    await http()
      .patch(`/ecf/dgii/evidence/${randomUUID()}/review`)
      .set("Authorization", `Bearer ${viewer.token}`)
      .send({ decision: "REVIEWED" })
      .expect(403);
  });

  it("la empresa arranca sin autorización y con la emisión real bloqueada", async () => {
    const tenant = await registerTenant("inicial");
    const res = await http()
      .get("/ecf/dgii/habilitation")
      .set("Authorization", `Bearer ${tenant.token}`)
      .expect(200);

    expect(res.body.companyId).toBe(tenant.companyId);
    expect(res.body.state).toBe("NOT_STARTED");
    expect(res.body.officialAuthorization).toBe(false);
    expect(res.body.authorizedAt).toBeNull();
    expect(res.body.isInternalTrackingOnly).toBe(true);
    // Ninguna ruta HTTP puede aprobar una empresa: `APPROVED` no es alcanzable
    // por PATCH administrativo.
    await http()
      .patch("/ecf/dgii/habilitation")
      .set("Authorization", `Bearer ${tenant.token}`)
      .send({ state: "APPROVED" })
        // Propiedad del estado: la empresa no declara estados de la DGII. El
        // rechazo es previo (403) y más estricto que el viejo 409 de evidencia.
        .expect(403);
      // `res` es la vista del expediente (lectura previa), no el cuerpo del
      // error: el rechazo se prueba con el 403 y con la emisión real bloqueada.
      expect(res.body.emission.realEmissionAuthorized).toBe(false);
      expect(res.body.emission.productionEmissionImplemented).toBe(false);
  });

  it("no se puede inventar una autorización oficial por HTTP", async () => {
    const tenant = await registerTenant("autorizacion-falsa");

    // Declaración manual: NO produce autorización.
    await http()
      .post("/ecf/dgii/authorization")
      .set("Authorization", `Bearer ${tenant.token}`)
      .send({
        source: "MANUAL_OPERATOR_DECLARATION",
        externalId: "DECLARADO-A-MANO",
      })
      .expect(201);

    const afterManual = await http()
      .get("/ecf/dgii/habilitation")
      .set("Authorization", `Bearer ${tenant.token}`)
      .expect(200);
    expect(afterManual.body.officialAuthorization).toBe(false);
    expect(afterManual.body.authorizedAt).toBeNull();

    // Fuente oficial sin evidencia: rechazada por el propio contrato.
    const noEvidence = await http()
      .post("/ecf/dgii/authorization")
      .set("Authorization", `Bearer ${tenant.token}`)
      .send({ source: "DGII_OFFICIAL_RECORD", externalId: "OFICIAL-SIN-EVIDENCIA" })
      .expect(400);
    expect(JSON.stringify(noEvidence.body)).toContain(
      "ECF_DGII_OFFICIAL_EVIDENCE_REQUIRED",
    );

    // Evidencia manual (aunque se revise) tampoco sostiene una fuente oficial.
    const manual = await http()
      .post("/ecf/dgii/evidence")
      .set("Authorization", `Bearer ${tenant.token}`)
      .send({
        source: "MANUAL_DECLARATION",
        kind: "nota-interna",
        storageRef: "uat://synthetic/nota-manual",
      })
      .expect(201);
    expect(manual.body.reviewStatus).toBe("PENDING");
    expect(manual.body.grantsOfficialAuthorization).toBe(false);
    expect(manual.body.supportsOfficialAuthorization).toBe(false);

    // Rechazar sin motivo no es auditable.
    await http()
      .patch(`/ecf/dgii/evidence/${manual.body.id}/review`)
      .set("Authorization", `Bearer ${tenant.token}`)
      .send({ decision: "REJECTED" })
      .expect(400);

    await http()
      .patch(`/ecf/dgii/evidence/${manual.body.id}/review`)
      .set("Authorization", `Bearer ${tenant.token}`)
      .send({ decision: "REVIEWED", note: "Revisada, pero es nuestra" })
      .expect(200);

    const manualOfficial = await http()
      .post("/ecf/dgii/authorization")
      .set("Authorization", `Bearer ${tenant.token}`)
      .send({
        source: "DGII_OFFICIAL_RECORD",
        evidenceId: manual.body.id,
        externalId: "OFICIAL-FALSA",
      })
      .expect(400);
    expect(JSON.stringify(manualOfficial.body)).toContain(
      "ECF_DGII_AUTHORIZATION_REQUIRES_OFFICIAL_EVIDENCE",
    );

    const finalView = await http()
      .get("/ecf/dgii/habilitation")
      .set("Authorization", `Bearer ${tenant.token}`)
      .expect(200);
    expect(finalView.body.officialAuthorization).toBe(false);
    expect(finalView.body.state).not.toBe("APPROVED");

    // La revisión interna SÍ es un hecho auditable y visible para la empresa.
    const history = await http()
      .get("/ecf/dgii/history")
      .set("Authorization", `Bearer ${tenant.token}`)
      .expect(200);
    expect(history.body.map((row: { action: string }) => row.action)).toContain(
      "DGII_EVIDENCE_REVIEWED",
    );
  });

  it("un documento oficial sin revisar no autoriza; revisado, sí (y sin emitir)", async () => {
    const tenant = await registerTenant("documento-oficial");
    const evidence = await http()
      .post("/ecf/dgii/evidence")
      .set("Authorization", `Bearer ${tenant.token}`)
      .send({
        source: "OFFICIAL_DOCUMENT",
        kind: "dgii-resolution",
        storageRef: "uat://synthetic-official/resolucion-e2e",
      })
      .expect(201);
    expect(evidence.body.level).toBe("OFFICIAL_DOCUMENT_PENDING_REVIEW");
    expect(evidence.body.supportsOfficialAuthorization).toBe(false);

    const pending = await http()
      .post("/ecf/dgii/authorization")
      .set("Authorization", `Bearer ${tenant.token}`)
      .send({
        source: "DGII_OFFICIAL_RECORD",
        evidenceId: evidence.body.id,
        externalId: "DGII-E2E-2026-1",
      })
      .expect(400);
    expect(JSON.stringify(pending.body)).toContain(
      "ECF_DGII_AUTHORIZATION_REQUIRES_REVIEWED_EVIDENCE",
    );

    const reviewed = await http()
      .patch(`/ecf/dgii/evidence/${evidence.body.id}/review`)
      .set("Authorization", `Bearer ${tenant.token}`)
      .send({ decision: "REVIEWED", note: "Cotejada contra el portal" })
      .expect(200);
    expect(reviewed.body.level).toBe("OFFICIAL_DOCUMENT_REVIEWED");
    expect(reviewed.body.supportsOfficialAuthorization).toBe(true);

    const approval = await http()
      .post("/ecf/dgii/authorization")
      .set("Authorization", `Bearer ${tenant.token}`)
      .send({
        source: "DGII_OFFICIAL_RECORD",
        evidenceId: evidence.body.id,
        externalId: "DGII-E2E-2026-1",
      })
      .expect(201);
    expect(approval.body.state).toBe("APPROVED");
    expect(approval.body.officialAuthorization).toBe(true);
    // Autorización oficial registrada NO significa emisión implementada.
    expect(approval.body.emission.realEmissionAuthorized).toBe(false);
    expect(
      approval.body.blockers.map((b: { code: string }) => b.code),
    ).toContain("ECF_REAL_EMISSION_NOT_IMPLEMENTED");

    // La revisión queda en el historial visible de la empresa.
    const history = await http()
      .get("/ecf/dgii/history")
      .set("Authorization", `Bearer ${tenant.token}`)
      .expect(200);
    expect(history.body.map((row: { action: string }) => row.action)).toContain(
      "DGII_EVIDENCE_REVIEWED",
    );
  });

  it("el seguimiento por requisito es por empresa y no inventa requisitos", async () => {
    const tenant = await registerTenant("seguimiento");
    const res = await http()
      .patch("/ecf/dgii/requirements/SET_TESTS")
      .set("Authorization", `Bearer ${tenant.token}`)
      .send({
        status: "IN_PROGRESS",
        note: "Faltan las pruebas de contingencia",
        dueDate: "2026-11-30",
      })
      .expect(200);

    const tracked = res.body.progress.requirements.find(
      (r: { key: string }) => r.key === "SET_TESTS",
    );
    expect(tracked.tracking.status).toBe("IN_PROGRESS");
    expect(tracked.tracking.note).toBe("Faltan las pruebas de contingencia");
    expect(tracked.tracking.dueDate).toBe("2026-11-30");
    // El seguimiento es gestión interna: no altera el progreso real.
    expect(tracked.status).not.toBe("IN_PROGRESS");

    await http()
      .patch("/ecf/dgii/requirements/REQUISITO_INVENTADO")
      .set("Authorization", `Bearer ${tenant.token}`)
      .send({ status: "COMPLETED" })
      .expect(404);

    // Estado inválido: el contrato lo rechaza antes de tocar la base.
    await http()
      .patch("/ecf/dgii/requirements/SET_TESTS")
      .set("Authorization", `Bearer ${tenant.token}`)
      .send({ status: "APROBADO_A_MANO" })
      .expect(400);

    // Otra empresa no ve este seguimiento.
    const other = await registerTenant("seguimiento-otra");
    const otherView = await http()
      .get("/ecf/dgii/habilitation")
      .set("Authorization", `Bearer ${other.token}`)
      .expect(200);
    expect(
      otherView.body.progress.requirements.every(
        (r: { tracking: unknown }) => r.tracking === null,
      ),
    ).toBe(true);
  });

  it("los datos de habilitación no cruzan de empresa", async () => {
    const a = await registerTenant("aislamiento-a");
    const b = await registerTenant("aislamiento-b");

    const evidenceA = await http()
      .post("/ecf/dgii/evidence")
      .set("Authorization", `Bearer ${a.token}`)
      .send({
        source: "MANUAL_DECLARATION",
        kind: "nota",
        storageRef: "uat://synthetic/nota-de-a",
      })
      .expect(201);

    await http()
      .patch("/ecf/dgii/habilitation")
      .set("Authorization", `Bearer ${a.token}`)
      .send({ observations: "Observación privada de A" })
      .expect(200);

    // B no ve nada de A.
    const viewB = await http()
      .get("/ecf/dgii/habilitation")
      .set("Authorization", `Bearer ${b.token}`)
      .expect(200);
    expect(viewB.body.companyId).toBe(b.companyId);
    expect(viewB.body.observations).toBeNull();

    const evidenceB = await http()
      .get("/ecf/dgii/evidence")
      .set("Authorization", `Bearer ${b.token}`)
      .expect(200);
    expect(evidenceB.body).toHaveLength(0);

    const historyB = await http()
      .get("/ecf/dgii/history")
      .set("Authorization", `Bearer ${b.token}`)
      .expect(200);
    expect(historyB.body).toHaveLength(0);

    // B no puede revisar la evidencia de A: la respuesta no confirma siquiera
    // que exista en otra empresa.
    await http()
      .patch(`/ecf/dgii/evidence/${evidenceA.body.id}/review`)
      .set("Authorization", `Bearer ${b.token}`)
      .send({ decision: "REVIEWED" })
      .expect(404);

    // Y tampoco puede usarla para autorizarse a sí misma.
    await http()
      .post("/ecf/dgii/authorization")
      .set("Authorization", `Bearer ${b.token}`)
      .send({
        source: "DGII_OFFICIAL_RECORD",
        evidenceId: evidenceA.body.id,
        externalId: "ROBO-DE-EVIDENCIA",
      })
      .expect(404);

    // La evidencia de A sigue intacta y sin revisar.
    const evidenceAStillPending = await http()
      .get("/ecf/dgii/evidence")
      .set("Authorization", `Bearer ${a.token}`)
      .expect(200);
    expect(evidenceAStillPending.body[0].reviewStatus).toBe("PENDING");
  });

  it("no se expone la referencia interna de almacenamiento de la evidencia", async () => {
    const tenant = await registerTenant("redaccion");
    const created = await http()
      .post("/ecf/dgii/evidence")
      .set("Authorization", `Bearer ${tenant.token}`)
      .send({
        source: "OFFICIAL_DOCUMENT",
        kind: "certificado",
        storageRef: "uat://synthetic-official/certificado-e2e",
      })
      .expect(201);

    // `storageRef` es interna: no debe salir por HTTP.
    expect(created.body.storageRef).toBeUndefined();
    const listed = await http()
      .get("/ecf/dgii/evidence")
      .set("Authorization", `Bearer ${tenant.token}`)
      .expect(200);
    expect(Object.keys(listed.body[0])).not.toContain("storageRef");

    // El esquema del DTO sí exige una referencia con forma válida.
    await http()
      .post("/ecf/dgii/evidence")
      .set("Authorization", `Bearer ${tenant.token}`)
      .send({ source: "OFFICIAL_DOCUMENT", kind: "x", storageRef: "javascript:alert(1)" })
      .expect(400);
  });
});
