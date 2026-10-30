import { INestApplication, ValidationPipe } from "@nestjs/common";
import { Test } from "@nestjs/testing";
import { EcfAuditAction } from "@prisma/client";
import { randomUUID } from "node:crypto";
import { execFileSync } from "node:child_process";
import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { Client } from "pg";
import request from "supertest";
import { AppModule } from "../../app.module";
import { PrismaService } from "../../prisma/prisma.service";
import { PLATFORM_STAFF_ENV } from "./platform-staff.guard";

/**
 * E2E HTTP de la superficie de PLATAFORMA (`/ecf/platform/*`).
 *
 * Se levanta la aplicación COMPLETA contra una base desechable propia y se habla
 * por HTTP de verdad: `AuthGuard('jwt')` real, `PlatformStaffGuard` real,
 * `ValidationPipe` real, controlador, servicio y PostgreSQL.
 *
 * Lo que este archivo demuestra —y lo que no:
 *  - Sí: quién entra y quién no (401/403), aislamiento entre dos empresas,
 *    transiciones, motivo obligatorio, doble solicitud y auditoría persistida.
 *  - Sí: que la aprobación oficial es inalcanzable por esta vía.
 *  - No: ninguna llamada a Alanube ni a la DGII. `ALANUBE_ENABLE_REAL_CALLS`
 *    debe ser `false` o el archivo se niega a correr.
 */
jest.setTimeout(300000);

const PASSWORD = "EcfPlatformHttpE2E123!";
const SAFE_DB = /^fullpos_platform_http_e2e_/;
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

uat("e-CF plataforma — E2E HTTP + PostgreSQL desechable", () => {
  let app: INestApplication;
  let prisma: PrismaService;
  let dbName: string;
  let appUrl: string;
  let adminUrl: string;

  const http = () => request(app.getHttpServer());

  beforeAll(async () => {
    if (process.env.ALANUBE_ENABLE_REAL_CALLS !== "false") {
      throw new Error("E2E_REFUSES_REAL_PROVIDER_CALLS");
    }
    const baseUrl = baseDatabaseUrl();
    dbName = `fullpos_platform_http_e2e_${Date.now()}`;
    adminUrl = replaceDbName(baseUrl, "postgres");
    appUrl = replaceDbName(baseUrl, dbName);
    if (!SAFE_DB.test(dbName)) throw new Error("Unsafe E2E DB name");

    const admin = new Client({ connectionString: adminUrl });
    await admin.connect();
    await admin.query(`CREATE DATABASE ${dbName}`);
    await admin.end();

    process.env.DATABASE_URL = appUrl;
    process.env.JWT_SECRET =
      process.env.JWT_SECRET || "ecf-platform-http-e2e-secret";
    // La lista de personal se deja VACÍA durante el arranque: cada prueba la
    // fija a lo que necesita. Así se comprueba de paso que el guard lee la
    // configuración en cada petición y no una instantánea del arranque.
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

  /** Empresa + administrador reales, creados por HTTP. */
  async function registerTenant(suffix: string) {
    const email = `platform-e2e-${Date.now()}-${suffix}@example.test`;
    const res = await http()
      .post("/auth/register-business")
      .send({
        firstName: "Platform",
        lastName: suffix,
        email,
        phone: "8095550000",
        password: PASSWORD,
        confirmPassword: PASSWORD,
        commercialName: `Platform ${suffix}`,
        taxId: `1${Date.now().toString().slice(-8)}`,
        businessPhone: "8095551111",
        address: `Calle Sintética ${suffix}`,
        country: "DO",
      })
      .expect(201);
    // Asistencia autorizada: el staff ya no puede abrir un expediente sin
    // concesión. Se crea por el endpoint REAL del cliente (no se salta el
    // guard): esto también comprueba que el cliente puede otorgarla.
    await http()
      .post("/ecf/dgii/support-grants")
      .set("Authorization", `Bearer ${res.body.accessToken as string}`)
      .send({
        scopes: ["VIEW_DOSSIER", "REVIEW_EVIDENCE", "REQUEST_CORRECTION"],
        expiresAt: new Date(Date.now() + 7 * 24 * 60 * 60 * 1000).toISOString(),
        reason: "UAT: asistencia de plataforma",
      })
      .expect(201);
    return {
      email,
      token: res.body.accessToken as string,
      userId: res.body.user.id as string,
      companyId: res.body.activeCompany.id as string,
    };
  }

  /** Fija la lista de personal de plataforma (identificadores de usuario). */
  function setStaff(...userIds: string[]) {
    process.env[PLATFORM_STAFF_ENV] = userIds.join(",");
  }

  /** Prepara el expediente de una empresa hasta `APPLICATION_PENDING`. */
  async function submitApplication(token: string) {
    const created = await http()
      .get("/ecf/dgii/habilitation")
      .set("Authorization", `Bearer ${token}`)
      .expect(200);
    expect(created.body.state).toBe("NOT_STARTED");
    await http()
      .patch("/ecf/dgii/habilitation")
      .set("Authorization", `Bearer ${token}`)
      .send({
        state: "APPLICATION_PENDING",
        reviewState: "PENDING_FULLTECH_REVIEW",
        observations: "Expediente sintético de UAT",
      })
      .expect(200);
  }

  /**
   * Envío SIN observaciones previas.
   *
   * Necesario para probar el motivo obligatorio: la regla acepta el motivo
   * nuevo **o el ya registrado**, así que un expediente que ya trae motivo no
   * puede demostrar que la regla existe.
   */
  async function submitApplicationWithoutReason(token: string) {
    await http()
      .get("/ecf/dgii/habilitation")
      .set("Authorization", `Bearer ${token}`)
      .expect(200);
    await http()
      .patch("/ecf/dgii/habilitation")
      .set("Authorization", `Bearer ${token}`)
      .send({ state: "APPLICATION_PENDING" })
      .expect(200);
  }

  /** Lleva el expediente hasta `IN_CERTIFICATION`, predecesor legal de `APPROVED`. */
  async function driveToCertification(staffToken: string, companyId: string) {
    for (const state of ["IN_PROGRESS", "TESTS_PENDING", "IN_CERTIFICATION"]) {
      await http()
        .patch(`/ecf/platform/dgii/applications/${companyId}`)
        .set("Authorization", `Bearer ${staffToken}`)
        .send({ state })
        .expect(200);
    }
  }

  function platformSurface(companyId: string) {
    return [
      { method: "get" as const, path: "/ecf/platform/me" },
      { method: "get" as const, path: "/ecf/platform/dgii/applications" },
      {
        method: "get" as const,
        path: `/ecf/platform/dgii/applications/${companyId}`,
      },
      {
        method: "patch" as const,
        path: `/ecf/platform/dgii/applications/${companyId}`,
        body: { state: "IN_PROGRESS" },
      },
      {
        method: "get" as const,
        path: `/ecf/platform/dgii/applications/${companyId}/requirements`,
      },
      {
        method: "patch" as const,
        path: `/ecf/platform/dgii/applications/${companyId}/requirements/FISCAL_DATA`,
        body: { status: "IN_PROGRESS" },
      },
      {
        method: "patch" as const,
        path: `/ecf/platform/dgii/applications/${companyId}/evidence/${randomUUID()}`,
        body: { decision: "REVIEWED" },
      },
      {
        method: "get" as const,
        path: `/ecf/platform/dgii/applications/${companyId}/documents/${randomUUID()}/file`,
      },
    ];
  }

  /** PNG sintético mínimo: la clase documental se decide por el contenido. */
  function syntheticPng() {
    return Buffer.concat([
      Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
      Buffer.alloc(64, 7),
    ]);
  }

  it("sin token, toda la superficie de plataforma responde 401", async () => {
    for (const entry of platformSurface(randomUUID())) {
      await http()[entry.method](entry.path).send(entry.body ?? {}).expect(401);
    }
  });

  it("un administrador de empresa NO listado recibe 403 en todas las rutas", async () => {
    const tenant = await registerTenant("admin-normal");
    setStaff();

    for (const entry of platformSurface(tenant.companyId)) {
      await http()
        [entry.method](entry.path)
        .set("Authorization", `Bearer ${tenant.token}`)
        .send(entry.body ?? {})
        .expect(403);
    }
  });

  it("el personal listado consulta expedientes de DOS empresas distintas", async () => {
    const companyA = await registerTenant("empresa-a");
    const companyB = await registerTenant("empresa-b");
    const staff = await registerTenant("fulltech");

    await submitApplication(companyA.token);
    await submitApplication(companyB.token);
    setStaff(staff.userId);

    const me = await http()
      .get("/ecf/platform/me")
      .set("Authorization", `Bearer ${staff.token}`)
      .expect(200);
    expect(me.body.isPlatformStaff).toBe(true);

    const queue = await http()
      .get("/ecf/platform/dgii/applications")
      .set("Authorization", `Bearer ${staff.token}`)
      .expect(200);
    expect(queue.body.total).toBeGreaterThanOrEqual(2);
    const ids = queue.body.items.map((row: { companyId: string }) => row.companyId);
    expect(ids).toContain(companyA.companyId);
    expect(ids).toContain(companyB.companyId);

    // El filtro por estado es real, no decorativo.
    const filtered = await http()
      .get("/ecf/platform/dgii/applications")
      .query({ state: "APPLICATION_PENDING", take: 5 })
      .set("Authorization", `Bearer ${staff.token}`)
      .expect(200);
    expect(filtered.body.items.length).toBeLessThanOrEqual(5);
    for (const row of filtered.body.items) {
      expect(row.state).toBe("APPLICATION_PENDING");
    }
  });

  it("el detalle expone metadatos y evidencias SIN rutas de almacenamiento", async () => {
    const companyA = await registerTenant("detalle");
    const staff = await registerTenant("fulltech-detalle");
    await submitApplication(companyA.token);

    const storageRef = `uat://synthetic/expediente-${randomUUID()}`;
    const evidence = await http()
      .post("/ecf/dgii/evidence")
      .set("Authorization", `Bearer ${companyA.token}`)
      .send({
        source: "MANUAL_DECLARATION",
        kind: "nota",
        storageRef,
        fileName: "nota.txt",
        mimeType: "text/plain",
        description: "Nota sintética",
      })
      .expect(201);

    setStaff(staff.userId);
    const detail = await http()
      .get(`/ecf/platform/dgii/applications/${companyA.companyId}`)
      .set("Authorization", `Bearer ${staff.token}`)
      .expect(200);

    expect(detail.body.companyId).toBe(companyA.companyId);
    expect(detail.body.state).toBe("APPLICATION_PENDING");
    expect(detail.body.hasOfficialAuthorization).toBe(false);
    expect(detail.body.evidence).toHaveLength(1);
    expect(detail.body.evidence[0].id).toBe(evidence.body.id);
    expect(detail.body.evidence[0].kind).toBe("nota");

    // La ubicación interna no se filtra por ninguna vía, ni el hash de contraseña.
    const serialized = JSON.stringify(detail.body);
    expect(serialized).not.toContain(storageRef);
    expect(serialized).not.toContain("storageRef");
    expect(serialized.toLowerCase()).not.toContain("passwordhash");
    expect(serialized).not.toContain("DATABASE_URL");
  });

  it("una decisión válida se aplica y queda AUDITADA con el actor real", async () => {
    const companyA = await registerTenant("decision-ok");
    const staff = await registerTenant("fulltech-decision");
    await submitApplication(companyA.token);
    setStaff(staff.userId);

    const decided = await http()
      .patch(`/ecf/platform/dgii/applications/${companyA.companyId}`)
      .set("Authorization", `Bearer ${staff.token}`)
      .send({
        state: "IN_PROGRESS",
        reviewState: "IN_REVIEW",
        observations: "Documentación en revisión",
      })
      .expect(200);

    expect(decided.body.state).toBe("IN_PROGRESS");
    expect(decided.body.reviewState).toBe("IN_REVIEW");
    expect(decided.body.observations).toBe("Documentación en revisión");

    const audit = await prisma.ecfAuditLog.findFirst({
      where: {
        companyId: companyA.companyId,
        action: EcfAuditAction.DGII_HABILITATION_UPDATED,
      },
      orderBy: { createdAt: "desc" },
      select: { actorUserId: true, after: true, targetId: true },
    });
    expect(audit).not.toBeNull();
    expect(audit?.actorUserId).toBe(staff.userId);

    // Y la empresa lo ve en su propio historial: la decisión no vive solo en
    // la tabla de plataforma.
    const history = await http()
      .get("/ecf/dgii/history")
      .set("Authorization", `Bearer ${companyA.token}`)
      .expect(200);
    const actions = history.body.map((row: { action: string }) => row.action);
    expect(actions).toContain("DGII_HABILITATION_UPDATED");
  });

  it("una transición ilegal se rechaza y no toca el estado", async () => {
    const companyA = await registerTenant("transicion-ilegal");
    const staff = await registerTenant("fulltech-transicion");
    await submitApplication(companyA.token);
    setStaff(staff.userId);

    // APPLICATION_PENDING no puede volver a NOT_STARTED.
    const refused = await http()
      .patch(`/ecf/platform/dgii/applications/${companyA.companyId}`)
      .set("Authorization", `Bearer ${staff.token}`)
      .send({ state: "NOT_STARTED" })
      .expect(409);
    expect(JSON.stringify(refused.body)).toContain(
      "ECF_DGII_TRANSITION_NOT_ALLOWED",
    );

    const detail = await http()
      .get(`/ecf/platform/dgii/applications/${companyA.companyId}`)
      .set("Authorization", `Bearer ${staff.token}`)
      .expect(200);
    expect(detail.body.state).toBe("APPLICATION_PENDING");
  });

  it("pedir corrección o rechazar EXIGE motivo", async () => {
    const companyA = await registerTenant("motivo");
    const staff = await registerTenant("fulltech-motivo");
    // Sin motivo previo: es el único escenario en el que la regla es observable.
    await submitApplicationWithoutReason(companyA.token);
    setStaff(staff.userId);

    // Ambos estados se prueban sobre expedientes limpios: pedir corrección
    // cambia el estado, así que el siguiente caso necesita su propia empresa.
    const companyB = await registerTenant("motivo-b");
    await submitApplicationWithoutReason(companyB.token);

    for (const [companyId, state] of [
      [companyA.companyId, "REQUIRES_CORRECTION"],
      [companyB.companyId, "REJECTED"],
    ] as const) {
      const refused = await http()
        .patch(`/ecf/platform/dgii/applications/${companyId}`)
        .set("Authorization", `Bearer ${staff.token}`)
        .send({ state })
        .expect(400);
      expect(JSON.stringify(refused.body)).toContain(
        "ECF_DGII_CORRECTION_REASON_REQUIRED",
      );
    }

    const corrected = await http()
      .patch(`/ecf/platform/dgii/applications/${companyA.companyId}`)
      .set("Authorization", `Bearer ${staff.token}`)
      .send({
        state: "REQUIRES_CORRECTION",
        observations: "Falta el documento de autorización",
      })
      .expect(200);
    expect(corrected.body.state).toBe("REQUIRES_CORRECTION");
    expect(corrected.body.observations).toBe(
      "Falta el documento de autorización",
    );
  });

  it("la aprobación oficial es INALCANZABLE incluso desde IN_CERTIFICATION", async () => {
    const companyA = await registerTenant("aprobar");
    const staff = await registerTenant("fulltech-aprobar");
    await submitApplication(companyA.token);
    setStaff(staff.userId);

    // Se recorre la secuencia legal completa hasta el predecesor de APPROVED.
    await driveToCertification(staff.token, companyA.companyId);

    // Aquí la transición SÍ está permitida por la tabla; el rechazo viene de la
    // regla antifalsificación: sin registro oficial no hay aprobación.
    const refused = await http()
      .patch(`/ecf/platform/dgii/applications/${companyA.companyId}`)
      .set("Authorization", `Bearer ${staff.token}`)
      .send({ state: "APPROVED", observations: "intento de aprobación directa" })
      .expect(409);
    expect(JSON.stringify(refused.body)).toContain(
      "ECF_DGII_APPROVAL_REQUIRES_OFFICIAL_RECORD",
    );

    const detail = await http()
      .get(`/ecf/platform/dgii/applications/${companyA.companyId}`)
      .set("Authorization", `Bearer ${staff.token}`)
      .expect(200);
    expect(detail.body.state).toBe("IN_CERTIFICATION");
    expect(detail.body.hasOfficialAuthorization).toBe(false);
    expect(detail.body.authorizedAt).toBeNull();
  });

  it("doble solicitud: repetir la misma decisión es idempotente y no corrompe estado", async () => {
    const companyA = await registerTenant("doble");
    const staff = await registerTenant("fulltech-doble");
    await submitApplication(companyA.token);
    setStaff(staff.userId);

    const body = { state: "IN_PROGRESS", observations: "primera pasada" };
    await http()
      .patch(`/ecf/platform/dgii/applications/${companyA.companyId}`)
      .set("Authorization", `Bearer ${staff.token}`)
      .send(body)
      .expect(200);
    await http()
      .patch(`/ecf/platform/dgii/applications/${companyA.companyId}`)
      .set("Authorization", `Bearer ${staff.token}`)
      .send(body)
      .expect(200);

    const detail = await http()
      .get(`/ecf/platform/dgii/applications/${companyA.companyId}`)
      .set("Authorization", `Bearer ${staff.token}`)
      .expect(200);
    expect(detail.body.state).toBe("IN_PROGRESS");

    // Dos peticiones EN PARALELO: la protección optimista puede rechazar una
    // con 409, pero nunca puede haber un 500 ni un estado inventado.
    const target = companyA.companyId;
    const [first, second] = await Promise.all([
      http()
        .patch(`/ecf/platform/dgii/applications/${target}`)
        .set("Authorization", `Bearer ${staff.token}`)
        .send({ state: "TESTS_PENDING", observations: "concurrente 1" }),
      http()
        .patch(`/ecf/platform/dgii/applications/${target}`)
        .set("Authorization", `Bearer ${staff.token}`)
        .send({ state: "IN_CERTIFICATION", observations: "concurrente 2" }),
    ]);
    for (const res of [first, second]) {
      expect([200, 409]).toContain(res.status);
    }
    expect([first.status, second.status]).toContain(200);

    const afterRace = await http()
      .get(`/ecf/platform/dgii/applications/${target}`)
      .set("Authorization", `Bearer ${staff.token}`)
      .expect(200);
    expect(["TESTS_PENDING", "IN_CERTIFICATION"]).toContain(afterRace.body.state);
  });

  it("decidir sobre una empresa NO altera el expediente de la otra", async () => {
    const companyA = await registerTenant("aislamiento-a");
    const companyB = await registerTenant("aislamiento-b");
    const staff = await registerTenant("fulltech-aislamiento");
    await submitApplication(companyA.token);
    await submitApplication(companyB.token);
    setStaff(staff.userId);

    await http()
      .patch(`/ecf/platform/dgii/applications/${companyA.companyId}`)
      .set("Authorization", `Bearer ${staff.token}`)
      .send({ state: "IN_PROGRESS", observations: "solo empresa A" })
      .expect(200);

    const detailB = await http()
      .get(`/ecf/platform/dgii/applications/${companyB.companyId}`)
      .set("Authorization", `Bearer ${staff.token}`)
      .expect(200);
    expect(detailB.body.state).toBe("APPLICATION_PENDING");
    expect(detailB.body.observations).toBe("Expediente sintético de UAT");

    const auditB = await prisma.ecfAuditLog.count({
      where: {
        companyId: companyB.companyId,
        action: EcfAuditAction.DGII_HABILITATION_UPDATED,
      },
    });
    // La empresa B solo tiene la auditoría de su propio envío.
    expect(auditB).toBe(1);
  });

  it("quitar al usuario de la lista revoca el acceso en la siguiente petición", async () => {
    const companyA = await registerTenant("revocacion");
    const staff = await registerTenant("fulltech-revocacion");
    await submitApplication(companyA.token);

    setStaff(staff.userId);
    await http()
      .get("/ecf/platform/dgii/applications")
      .set("Authorization", `Bearer ${staff.token}`)
      .expect(200);

    setStaff();
    await http()
      .get("/ecf/platform/dgii/applications")
      .set("Authorization", `Bearer ${staff.token}`)
      .expect(403);
  });

  it("una empresa concreta inexistente responde 403, no 404 ni una lista vacía", async () => {
    const staff = await registerTenant("fulltech-404");
    setStaff(staff.userId);
    // El guard de concesión se evalúa antes que la existencia de la empresa:
    // sin concesión no hay acceso, y un 403 no revela si el identificador
    // corresponde a una empresa real. Es más estricto que el 404 anterior.
    await http()
      .get(`/ecf/platform/dgii/applications/${randomUUID()}`)
      .set("Authorization", `Bearer ${staff.token}`)
      .expect(403);
  });

  it("el panel lista los requisitos del catálogo y registra la revisión de uno", async () => {
    const companyA = await registerTenant("requisitos");
    const staff = await registerTenant("fulltech-requisitos");
    await submitApplication(companyA.token);
    setStaff(staff.userId);

    const list = await http()
      .get(`/ecf/platform/dgii/applications/${companyA.companyId}/requirements`)
      .set("Authorization", `Bearer ${staff.token}`)
      .expect(200);
    expect(list.body.items.length).toBeGreaterThan(10);
    const digital = list.body.items.find(
      (row: { key: string }) => row.key === "DIGITAL_CERTIFICATE",
    );
    expect(digital).toBeDefined();
    expect(digital.mandatory).toBe(true);
    // Sin seguimiento registrado no se inventa un estado.
    expect(digital.tracking).toBeNull();

    const reviewed = await http()
      .patch(
        `/ecf/platform/dgii/applications/${companyA.companyId}/requirements/DIGITAL_CERTIFICATE`,
      )
      .set("Authorization", `Bearer ${staff.token}`)
      .send({
        status: "IN_PROGRESS",
        note: "Certificado recibido, pendiente de validación",
      })
      .expect(200);
    expect(reviewed.body.key).toBe("DIGITAL_CERTIFICATE");
    expect(reviewed.body.tracking.status).toBe("IN_PROGRESS");
    expect(reviewed.body.tracking.updatedByUserId).toBe(staff.userId);

    // El catálogo es cerrado: una clave inventada no entra.
    await http()
      .patch(
        `/ecf/platform/dgii/applications/${companyA.companyId}/requirements/REQUISITO_INVENTADO`,
      )
      .set("Authorization", `Bearer ${staff.token}`)
      .send({ status: "IN_PROGRESS" })
      .expect(404);

    // Y queda auditado con el actor real.
    const audit = await prisma.ecfAuditLog.findFirst({
      where: {
        companyId: companyA.companyId,
        action: EcfAuditAction.DGII_HABILITATION_UPDATED,
        actorUserId: staff.userId,
      },
      orderBy: { createdAt: "desc" },
      select: { after: true },
    });
    expect(JSON.stringify(audit?.after)).toContain("DIGITAL_CERTIFICATE");
  });

  it("el panel revisa evidencias con la misma política (rechazo con motivo)", async () => {
    const companyA = await registerTenant("evidencia-panel");
    const staff = await registerTenant("fulltech-evidencia");
    await submitApplication(companyA.token);

    const evidence = await http()
      .post("/ecf/dgii/evidence")
      .set("Authorization", `Bearer ${companyA.token}`)
      .send({
        source: "MANUAL_DECLARATION",
        kind: "certificado",
        storageRef: `uat://synthetic/cert-${randomUUID()}`,
        fileName: "certificado.pdf",
      })
      .expect(201);
    setStaff(staff.userId);

    // Rechazar sin motivo no es auditable: misma regla que en la empresa.
    const refused = await http()
      .patch(
        `/ecf/platform/dgii/applications/${companyA.companyId}/evidence/${evidence.body.id}`,
      )
      .set("Authorization", `Bearer ${staff.token}`)
      .send({ decision: "REJECTED" })
      .expect(400);
    expect(JSON.stringify(refused.body)).toContain(
      "ECF_DGII_EVIDENCE_REJECTION_REASON_REQUIRED",
    );

    const reviewed = await http()
      .patch(
        `/ecf/platform/dgii/applications/${companyA.companyId}/evidence/${evidence.body.id}`,
      )
      .set("Authorization", `Bearer ${staff.token}`)
      .send({ decision: "REVIEWED", note: "Documento legible" })
      .expect(200);
    expect(reviewed.body.reviewStatus).toBe("REVIEWED");
    // Revisar NO autoriza: la evidencia sigue sin sustentar registro oficial.
    expect(reviewed.body.grantsOfficialAuthorization).toBe(false);

    const audit = await prisma.ecfAuditLog.findFirst({
      where: {
        companyId: companyA.companyId,
        action: EcfAuditAction.DGII_EVIDENCE_REVIEWED,
        actorUserId: staff.userId,
      },
      select: { id: true },
    });
    expect(audit).not.toBeNull();
  });

  it("una evidencia de OTRA empresa no se puede revisar desde el expediente ajeno", async () => {
    const companyA = await registerTenant("cruce-a");
    const companyB = await registerTenant("cruce-b");
    const staff = await registerTenant("fulltech-cruce");
    await submitApplication(companyA.token);
    await submitApplication(companyB.token);

    const evidenceB = await http()
      .post("/ecf/dgii/evidence")
      .set("Authorization", `Bearer ${companyB.token}`)
      .send({
        source: "MANUAL_DECLARATION",
        kind: "nota-b",
        storageRef: `uat://synthetic/nota-b-${randomUUID()}`,
      })
      .expect(201);
    setStaff(staff.userId);

    // Se usa la ruta de la empresa A con el identificador de la empresa B.
    await http()
      .patch(
        `/ecf/platform/dgii/applications/${companyA.companyId}/evidence/${evidenceB.body.id}`,
      )
      .set("Authorization", `Bearer ${staff.token}`)
      .send({ decision: "REVIEWED", note: "intento cruzado" })
      .expect(404);
  });

  it("el personal descarga un documento autorizado y no el de otra empresa", async () => {
    const companyA = await registerTenant("descarga-a");
    const companyB = await registerTenant("descarga-b");
    const staff = await registerTenant("fulltech-descarga");
    await submitApplication(companyA.token);

    const uploaded = await http()
      .post("/ecf/dgii/documents")
      .set("Authorization", `Bearer ${companyA.token}`)
      .field("kind", "AUTHORIZATION")
      .attach("file", syntheticPng(), "autorizacion.png")
      .expect(201);
    expect(uploaded.body.id).toBeTruthy();
    expect(uploaded.body.sha256).toHaveLength(64);
    setStaff(staff.userId);

    const downloaded = await http()
      .get(
        `/ecf/platform/dgii/applications/${companyA.companyId}/documents/${uploaded.body.id}/file`,
      )
      .set("Authorization", `Bearer ${staff.token}`)
      .expect(200);
    expect(downloaded.headers["x-content-sha256"]).toBe(uploaded.body.sha256);
    expect(downloaded.headers["cache-control"]).toBe("no-store");
    expect(downloaded.body.length).toBeGreaterThan(0);

    // El mismo identificador por la ruta de otra empresa no existe.
    await http()
      .get(
        `/ecf/platform/dgii/applications/${companyB.companyId}/documents/${uploaded.body.id}/file`,
      )
      .set("Authorization", `Bearer ${staff.token}`)
      .expect(404);
  });

  /**
   * Expediente: borrador persistente, snapshot inmutable y consentimiento.
   *
   * Todo por HTTP real contra PostgreSQL desechable. La versión del
   * consentimiento nunca se escribe a mano aquí: se lee del servidor, para que
   * el test no quede desfasado si el texto cambia de versión.
   */
  describe("expediente: borrador, snapshot y consentimiento", () => {
    const validPayload = () => ({
      company: {
        rnc: "131000001",
        legalName: "Empresa Sintética SRL",
        address: "Calle Sintética 1, Santo Domingo",
      },
      representative: {
        fullName: "Ana Pérez",
        identification: "001-0000000-1",
        email: "ana.representante@example.test",
      },
    });

    const draftOf = (token: string) =>
      http()
        .get("/ecf/dgii/application/draft")
        .set("Authorization", `Bearer ${token}`);

    const saveDraft = (
      token: string,
      payload: unknown,
      expectedRevision?: number,
    ) =>
      http()
        .put("/ecf/dgii/application/draft")
        .set("Authorization", `Bearer ${token}`)
        .send({
          payload,
          ...(expectedRevision === undefined ? {} : { expectedRevision }),
        });

    const submit = (token: string, body: Record<string, unknown>) =>
      http()
        .post("/ecf/dgii/application/submit")
        .set("Authorization", `Bearer ${token}`)
        .send(body);

    it("guarda el borrador y lo recupera íntegro en una sesión nueva", async () => {
      const tenant = await registerTenant("draft");
      const payload = validPayload();

      const saved = await saveDraft(tenant.token, payload).expect(200);
      expect(saved.body.draft).toEqual(payload);
      expect(saved.body.missingFields).toEqual([]);

      // Sesión nueva de verdad: se vuelve a autenticar y se lee lo guardado.
      const login = await http()
        .post("/auth/login")
        .send({ email: tenant.email, password: PASSWORD });
      expect(login.body.accessToken).toBeTruthy();

      const reopened = await draftOf(login.body.accessToken as string).expect(
        200,
      );
      expect(reopened.body.draft).toEqual(payload);

      // Modificar el borrador tampoco toca nada fiscal.
      const changed = { ...payload, company: { ...payload.company, address: "Otra dirección 22" } };
      await saveDraft(
        login.body.accessToken as string,
        changed,
        reopened.body.draftRevision as number,
      ).expect(200);
      const after = await draftOf(login.body.accessToken as string).expect(200);
      expect(after.body.draft.company.address).toBe("Otra dirección 22");
    });

    it("señala los campos que faltan sin rellenarlos", async () => {
      const tenant = await registerTenant("incomplete");
      const saved = await saveDraft(tenant.token, {
        company: { rnc: "131000002" },
      }).expect(200);

      expect(saved.body.missingFields).toEqual(
        expect.arrayContaining([
          "company.legalName",
          "company.address",
          "representative.fullName",
          "representative.identification",
          "representative.email",
        ]),
      );
      expect(saved.body.draft.company.legalName).toBeUndefined();
    });

    it("el borrador de una empresa no lo ve otra", async () => {
      const a = await registerTenant("draft-a");
      const b = await registerTenant("draft-b");
      await saveDraft(a.token, validPayload()).expect(200);

      const other = await draftOf(b.token).expect(200);
      expect(other.body.draft).toBeNull();
      expect(other.body.missingFields.length).toBeGreaterThan(0);
    });

    it("sin consentimiento el envío se rechaza y no crea snapshot", async () => {
      const tenant = await registerTenant("noconsent");
      await saveDraft(tenant.token, validPayload()).expect(200);

      const rejected = await submit(tenant.token, {}).expect(400);
      expect(JSON.stringify(rejected.body)).toContain(
        "ECF_DGII_CONSENT_REQUIRED",
      );

      const habilitation = await http()
        .get("/ecf/dgii/habilitation")
        .set("Authorization", `Bearer ${tenant.token}`)
        .expect(200);
      expect(habilitation.body.state).toBe("NOT_STARTED");

      const snapshots = await http()
        .get("/ecf/dgii/application/snapshots")
        .set("Authorization", `Bearer ${tenant.token}`)
        .expect(200);
      expect(snapshots.body).toEqual([]);
    });

    it("una versión de consentimiento desconocida se rechaza", async () => {
      const tenant = await registerTenant("badversion");
      await saveDraft(tenant.token, validPayload()).expect(200);

      const rejected = await submit(tenant.token, {
        consentVersion: "1999-01-01.v0",
      }).expect(400);
      expect(JSON.stringify(rejected.body)).toContain(
        "ECF_DGII_CONSENT_VERSION_UNKNOWN",
      );
    });

    it("un expediente incompleto no se puede enviar", async () => {
      const tenant = await registerTenant("incomplete-submit");
      await saveDraft(tenant.token, { company: { rnc: "131000003" } }).expect(
        200,
      );
      const { body } = await draftOf(tenant.token).expect(200);

      const rejected = await submit(tenant.token, {
        consentVersion: body.requiredConsentVersion,
      }).expect(400);
      expect(JSON.stringify(rejected.body)).toContain(
        "ECF_DGII_DRAFT_INCOMPLETE",
      );
    });

    it("el envío crea un snapshot v1, guarda el consentimiento y audita", async () => {
      const tenant = await registerTenant("submit");
      await saveDraft(tenant.token, validPayload()).expect(200);
      const { body: draft } = await draftOf(tenant.token).expect(200);

      const submitted = await submit(tenant.token, {
        consentVersion: draft.requiredConsentVersion,
      }).expect(201);
      expect(submitted.body.version).toBe(1);
      expect(submitted.body.idempotent).toBe(false);
      expect(submitted.body.state).toBe("APPLICATION_PENDING");
      expect(submitted.body.payloadHash).toMatch(/^[a-f0-9]{64}$/);

      const habilitation = await http()
        .get("/ecf/dgii/habilitation")
        .set("Authorization", `Bearer ${tenant.token}`)
        .expect(200);
      expect(habilitation.body.state).toBe("APPLICATION_PENDING");

      const stored = await prisma.ecfDgiiHabilitation.findUnique({
        where: { companyId: tenant.companyId },
      });
      expect(stored?.consentVersion).toBe(draft.requiredConsentVersion);
      expect(stored?.consentAcceptedByUserId).toBe(tenant.userId);
      expect(stored?.consentAcceptedAt).not.toBeNull();
      expect(stored?.currentSnapshotVersion).toBe(1);
      expect(stored?.draftPayload).toBeNull();

      const audit = await prisma.ecfAuditLog.findMany({
        where: {
          companyId: tenant.companyId,
          action: {
            in: [
              EcfAuditAction.DGII_APPLICATION_SUBMITTED,
              EcfAuditAction.DGII_CONSENT_ACCEPTED,
            ],
          },
        },
      });
      expect(audit).toHaveLength(2);
      expect(audit.every((row) => row.actorUserId === tenant.userId)).toBe(true);
    });

    it("reenviar lo mismo es idempotente y no duplica la versión", async () => {
      const tenant = await registerTenant("idempotent");
      await saveDraft(tenant.token, validPayload()).expect(200);
      const { body: draft } = await draftOf(tenant.token).expect(200);

      const first = await submit(tenant.token, {
        consentVersion: draft.requiredConsentVersion,
        payload: validPayload(),
      }).expect(201);
      const second = await submit(tenant.token, {
        consentVersion: draft.requiredConsentVersion,
        payload: validPayload(),
      }).expect(201);

      expect(second.body.idempotent).toBe(true);
      expect(second.body.version).toBe(first.body.version);
      expect(second.body.snapshotId).toBe(first.body.snapshotId);

      const count = await prisma.ecfDgiiApplicationSnapshot.count({
        where: { companyId: tenant.companyId },
      });
      expect(count).toBe(1);
    });

    it("el snapshot es inmutable incluso por SQL directo", async () => {
      const tenant = await registerTenant("immutable");
      await saveDraft(tenant.token, validPayload()).expect(200);
      const { body: draft } = await draftOf(tenant.token).expect(200);
      const submitted = await submit(tenant.token, {
        consentVersion: draft.requiredConsentVersion,
      }).expect(201);

      await expect(
        prisma.$executeRawUnsafe(
          `UPDATE "ecf_dgii_application_snapshots" SET "version" = 99 WHERE "id" = $1::uuid`,
          submitted.body.snapshotId,
        ),
      ).rejects.toThrow(/inmutable/i);

      await expect(
        prisma.$executeRawUnsafe(
          `DELETE FROM "ecf_dgii_application_snapshots" WHERE "id" = $1::uuid`,
          submitted.body.snapshotId,
        ),
      ).rejects.toThrow(/inmutable/i);

      const still = await prisma.ecfDgiiApplicationSnapshot.findUnique({
        where: { id: submitted.body.snapshotId },
      });
      expect(still?.version).toBe(1);
    });

    it("una corrección y reenvío crea la v2 sin tocar la v1", async () => {
      const tenant = await registerTenant("correction");
      const firstSave = await saveDraft(tenant.token, validPayload()).expect(200);
      const { body: draft } = await draftOf(tenant.token).expect(200);
      const v1 = await submit(tenant.token, {
        consentVersion: draft.requiredConsentVersion,
      }).expect(201);

      // Fulltech pide corrección (con motivo) y el cliente reenvía.
      setStaff(tenant.userId);
      await http()
        .patch(`/ecf/platform/dgii/applications/${tenant.companyId}`)
        .set("Authorization", `Bearer ${tenant.token}`)
        .send({
          state: "REQUIRES_CORRECTION",
          observations: "El RNC no coincide con el documento aportado.",
        })
        .expect(200);

      const corrected = validPayload();
      corrected.company.rnc = "131000009";
      await saveDraft(
        tenant.token,
        corrected,
        firstSave.body.draftRevision as number,
      ).expect(200);

      const v2 = await submit(tenant.token, {
        consentVersion: draft.requiredConsentVersion,
      }).expect(201);
      expect(v2.body.version).toBe(2);
      expect(v2.body.idempotent).toBe(false);

      const versions = await prisma.ecfDgiiApplicationSnapshot.findMany({
        where: { companyId: tenant.companyId },
        orderBy: { version: "asc" },
        select: { version: true, payloadHash: true },
      });
      expect(versions.map((row) => row.version)).toEqual([1, 2]);
      expect(versions[0].payloadHash).toBe(v1.body.payloadHash);
      expect(versions[1].payloadHash).not.toBe(v1.body.payloadHash);
    });

    it("dos guardados concurrentes no pueden sobrescribir el más reciente", async () => {
      const tenant = await registerTenant("concurrent");
      const first = await saveDraft(tenant.token, validPayload()).expect(200);
      const revision = first.body.draftRevision as number;
      expect(revision).toBe(1);

      const other = {
        ...validPayload(),
        company: { ...validPayload().company, address: "Dirección B" },
      };

      // Ambas peticiones parten de la MISMA revisión: solo una puede escribir.
      const [a, b] = await Promise.all([
        saveDraft(tenant.token, validPayload(), revision),
        saveDraft(tenant.token, other, revision),
      ]);
      const statuses = [a.status, b.status].sort();
      expect(statuses).toEqual([200, 409]);

      const winner = a.status === 200 ? a : b;
      const loser = a.status === 200 ? b : a;
      expect(JSON.stringify(loser.body)).toContain("ECF_DGII_DRAFT_CONFLICT");
      // El conflicto devuelve la versión vigente para que el cliente se recupere.
      expect(loser.body.currentRevision).toBe(winner.body.draftRevision);

      // Una petición que llega TARDE con la revisión vieja tampoco pisa nada.
      const stale = await saveDraft(
        tenant.token,
        { company: { rnc: "999" } },
        revision,
      );
      expect(stale.status).toBe(409);

      const stored = await draftOf(tenant.token).expect(200);
      expect(stored.body.draftRevision).toBe(winner.body.draftRevision);
      expect(stored.body.draft).toEqual(winner.body.draft);
      expect(stored.body.draft).not.toEqual({ company: { rnc: "999" } });
    });

    it("guardar sin revisión cuando ya existe borrador se rechaza", async () => {
      const tenant = await registerTenant("norevision");
      await saveDraft(tenant.token, validPayload()).expect(200);
      const rejected = await saveDraft(tenant.token, validPayload());
      expect(rejected.status).toBe(400);
      expect(JSON.stringify(rejected.body)).toContain(
        "ECF_DGII_DRAFT_REVISION_REQUIRED",
      );
    });

    it("los snapshots de una empresa no son visibles para otra", async () => {
      const a = await registerTenant("snap-a");
      const b = await registerTenant("snap-b");
      await saveDraft(a.token, validPayload()).expect(200);
      const { body: draft } = await draftOf(a.token).expect(200);
      await submit(a.token, {
        consentVersion: draft.requiredConsentVersion,
      }).expect(201);

      const forB = await http()
        .get("/ecf/dgii/application/snapshots")
        .set("Authorization", `Bearer ${b.token}`)
        .expect(200);
      expect(forB.body).toEqual([]);
    });

    it("añadir un documento después del envío no altera la versión presentada", async () => {
      const tenant = await registerTenant("snapshot-docs");
      const payload = validPayload();
      await saveDraft(tenant.token, payload).expect(200);
      const { body: draft } = await draftOf(tenant.token).expect(200);
      const v1 = await submit(tenant.token, {
        consentVersion: draft.requiredConsentVersion,
        payload,
      }).expect(201);

      const before = await prisma.ecfDgiiApplicationSnapshot.findUnique({
        where: { id: v1.body.snapshotId },
      });
      expect(before).not.toBeNull();

      // Documento NUEVO, añadido después de presentar la versión 1.
      await prisma.ecfEvidence.create({
        data: {
          companyId: tenant.companyId,
          source: "OFFICIAL_DOCUMENT",
          kind: "COMPANY_DOCUMENT",
          storageRef: `storage://e2e/${randomUUID()}.pdf`,
          fileName: "documento-posterior.pdf",
          mimeType: "application/pdf",
          sha256: "a".repeat(64),
        },
      });

      // La versión 1 sigue exactamente igual: datos, documentos y hashes.
      const after = await prisma.ecfDgiiApplicationSnapshot.findUnique({
        where: { id: v1.body.snapshotId },
      });
      expect(after?.payload).toEqual(before?.payload);
      expect(after?.payloadHash).toBe(before?.payloadHash);
      expect(after?.documents).toEqual(before?.documents);
      expect(after?.documentsHash).toBe(before?.documentsHash);
      expect(after?.consentVersion).toBe(before?.consentVersion);
      expect(after?.submittedByUserId).toBe(tenant.userId);

      // Un envío nuevo sí refleja el documento añadido, en una versión distinta.
      setStaff(tenant.userId);
      await http()
        .patch(`/ecf/platform/dgii/applications/${tenant.companyId}`)
        .set("Authorization", `Bearer ${tenant.token}`)
        .send({
          state: "REQUIRES_CORRECTION",
          observations: "Falta adjuntar el documento nuevo.",
        })
        .expect(200);

      const v2 = await submit(tenant.token, {
        consentVersion: draft.requiredConsentVersion,
        payload,
      }).expect(201);
      expect(v2.body.version).toBe(2);
      expect(v2.body.documentsHash).not.toBe(v1.body.documentsHash);
    });
  });
});
