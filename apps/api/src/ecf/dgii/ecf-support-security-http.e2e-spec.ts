import { INestApplication, ValidationPipe } from "@nestjs/common";
import { Test } from "@nestjs/testing";
import { execFileSync } from "node:child_process";
import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { Client } from "pg";
import request from "supertest";
import { EcfAuditAction } from "@prisma/client";
import { AppModule } from "../../app.module";
import { PrismaService } from "../../prisma/prisma.service";
import { PLATFORM_STAFF_ENV } from "../platform/platform-staff.guard";

/**
 * MATRIZ DE SEGURIDAD — aislamiento por empresa y auditoría append-only.
 *
 * Complementa `ecf-support-grant-http.e2e-spec.ts` con los casos que faltaban:
 *  1. identificadores de evidencia de OTRA empresa (descarga y revisión),
 *  2. visibilidad de la bandeja multiempresa (no debe filtrar nombres),
 *  3. escalada de privilegios (concesión ≠ permiso de plataforma),
 *  4. integridad de la auditoría: cada acto deja fila, las filas se acumulan y
 *     no existe ruta HTTP que las modifique ni las borre,
 *  5. aislamiento de la auditoría por empresa.
 */
jest.setTimeout(300000);

const PASSWORD = "EcfSupportSecurityE2E123!";
const SAFE_DB = /^fullpos_support_security_e2e_/;

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

uat("asistencia autorizada — aislamiento y auditoría", () => {
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
    dbName = `fullpos_support_security_e2e_${Date.now()}`;
    adminUrl = replaceDbName(baseUrl, "postgres");
    const appUrl = replaceDbName(baseUrl, dbName);
    if (!SAFE_DB.test(dbName)) throw new Error("Unsafe E2E DB name");

    const admin = new Client({ connectionString: adminUrl });
    await admin.connect();
    await admin.query(`CREATE DATABASE ${dbName}`);
    await admin.end();

    process.env.DATABASE_URL = appUrl;
    process.env.JWT_SECRET = process.env.JWT_SECRET || "ecf-security-e2e-secret";
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

  async function registerTenant(suffix: string, name?: string) {
    const email = `sec-e2e-${Date.now()}-${suffix}@example.test`;
    const commercialName = name ?? `Seguridad ${suffix}`;
    const res = await http()
      .post("/auth/register-business")
      .send({
        firstName: "Sec",
        lastName: suffix,
        email,
        phone: "8095550000",
        password: PASSWORD,
        confirmPassword: PASSWORD,
        commercialName,
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
      name: commercialName,
    };
  }

  function expiresIn(days: number) {
    return new Date(Date.now() + days * 24 * 60 * 60 * 1000).toISOString();
  }

  async function grant(token: string, scopes: string[], days = 7) {
    const res = await http()
      .post("/ecf/dgii/support-grants")
      .set(auth(token))
      .send({ scopes, expiresAt: expiresIn(days) })
      .expect(201);
    return res.body.id as string;
  }

  async function staffFor(suffix: string) {
    const staff = await registerTenant(`staff-${suffix}`);
    process.env[PLATFORM_STAFF_ENV] = staff.userId;
    return staff;
  }

  /** Evidencia mínima real en BD: el contenido no hace falta para el aislamiento. */
  async function makeEvidence(companyId: string, label: string) {
    return prisma.ecfEvidence.create({
      data: {
        companyId,
        kind: "CERTIFICADO_DGII",
        storageRef: `e2e/${label}.pdf`,
        fileName: `${label}.pdf`,
        mimeType: "application/pdf",
        sha256: "0".repeat(64),
        description: `evidencia ${label}`,
      },
      select: { id: true },
    });
  }

  const detailUrl = (companyId: string) =>
    `/ecf/platform/dgii/applications/${companyId}`;
  const documentUrl = (companyId: string, evidenceId: string) =>
    `/ecf/platform/dgii/applications/${companyId}/documents/${evidenceId}/file`;
  const evidenceUrl = (companyId: string, evidenceId: string) =>
    `/ecf/platform/dgii/applications/${companyId}/evidence/${evidenceId}`;

  describe("identificadores de otra empresa", () => {
    it("descargar con el companyId correcto y la evidencia de OTRA empresa da 404", async () => {
      const a = await registerTenant("doc-a");
      const b = await registerTenant("doc-b");
      await http().get("/ecf/dgii/habilitation").set(auth(a.token)).expect(200);
      await http().get("/ecf/dgii/habilitation").set(auth(b.token)).expect(200);
      const evidenceB = await makeEvidence(b.companyId, "ajena");
      await grant(a.token, ["VIEW_DOSSIER", "REVIEW_EVIDENCE"]);
      const staff = await staffFor("doc");

      // La concesión de A sí cubre la descarga, pero la evidencia es de B:
      // debe comportarse como inexistente, sin filtrar nada del archivo ajeno.
      const res = await http()
        .get(documentUrl(a.companyId, evidenceB.id))
        .set(auth(staff.token))
        .expect(404);
      expect(JSON.stringify(res.body)).toContain("ECF_DGII_DOCUMENT_NOT_FOUND");
      expect(JSON.stringify(res.body)).not.toContain("ajena.pdf");
    });

    it("la concesión de A no descarga la evidencia de B ni con el companyId de B", async () => {
      const a = await registerTenant("doc2-a");
      const b = await registerTenant("doc2-b");
      await http().get("/ecf/dgii/habilitation").set(auth(b.token)).expect(200);
      const evidenceB = await makeEvidence(b.companyId, "ajena2");
      await grant(a.token, ["VIEW_DOSSIER", "REVIEW_EVIDENCE"]);
      const staff = await staffFor("doc2");

      const res = await http()
        .get(documentUrl(b.companyId, evidenceB.id))
        .set(auth(staff.token))
        .expect(403);
      expect(JSON.stringify(res.body)).toContain("ECF_SUPPORT_GRANT_MISSING");
    });

    it("revisar la evidencia de OTRA empresa no cambia su estado", async () => {
      const a = await registerTenant("rev-a");
      const b = await registerTenant("rev-b");
      await http().get("/ecf/dgii/habilitation").set(auth(a.token)).expect(200);
      await http().get("/ecf/dgii/habilitation").set(auth(b.token)).expect(200);
      const evidenceB = await makeEvidence(b.companyId, "ajena3");
      await grant(a.token, ["VIEW_DOSSIER", "REVIEW_EVIDENCE"]);
      const staff = await staffFor("rev");

      const res = await http()
        .patch(evidenceUrl(a.companyId, evidenceB.id))
        .set(auth(staff.token))
        .send({ reviewStatus: "REJECTED", reviewNote: "no autorizado" });
      expect(res.status).not.toBe(200);

      const row = await prisma.ecfEvidence.findUnique({
        where: { id: evidenceB.id },
        select: { reviewStatus: true, reviewNote: true },
      });
      expect(row?.reviewStatus).toBe("PENDING");
      expect(row?.reviewNote).toBeNull();
    });
  });

  describe("bandeja multiempresa", () => {
    it("una empresa sin concesión no aparece ni filtra su nombre", async () => {
      const secret = await registerTenant(
        "oculta",
        "Empresa Confidencial Bandeja",
      );
      await http()
        .get("/ecf/dgii/habilitation")
        .set(auth(secret.token))
        .expect(200);
      const staff = await staffFor("vacia");

      // La concesión es de la EMPRESA hacia Fulltech, no de un empleado
      // concreto: por eso la bandeja puede contener otras empresas que ya
      // autorizaron asistencia. Lo que nunca puede ocurrir es que aparezca una
      // empresa SIN concesión, ni siquiera su nombre.
      const res = await http()
        .get("/ecf/platform/dgii/applications?take=200")
        .set(auth(staff.token))
        .expect(200);
      const ids = (res.body.items as { companyId: string }[]).map(
        (item) => item.companyId,
      );
      expect(ids).not.toContain(secret.companyId);
      expect(JSON.stringify(res.body)).not.toContain("Confidencial");
    });

    it("solo aparece la empresa que concedió asistencia", async () => {
      const visible = await registerTenant("visible", "Empresa Visible Bandeja");
      const hidden = await registerTenant("hidden", "Empresa Oculta Bandeja");
      await http()
        .get("/ecf/dgii/habilitation")
        .set(auth(visible.token))
        .expect(200);
      await http()
        .get("/ecf/dgii/habilitation")
        .set(auth(hidden.token))
        .expect(200);
      await grant(visible.token, ["VIEW_DOSSIER"]);
      const staff = await staffFor("filtrada");

      const res = await http()
        .get("/ecf/platform/dgii/applications?take=200")
        .set(auth(staff.token))
        .expect(200);

      const ids = (res.body.items as { companyId: string }[]).map(
        (item) => item.companyId,
      );
      expect(ids).toContain(visible.companyId);
      expect(ids).not.toContain(hidden.companyId);
      expect(JSON.stringify(res.body)).not.toContain("Empresa Oculta Bandeja");
      // `total` debe contar con el mismo filtro, no la tabla completa.
      expect(res.body.total).toBe(ids.length);
    });
  });

  describe("alcance visible para el personal", () => {
    it("el staff ve los alcances concedidos y su caducidad", async () => {
      const company = await registerTenant("acceso-visible");
      await http()
        .get("/ecf/dgii/habilitation")
        .set(auth(company.token))
        .expect(200);
      await grant(company.token, ["VIEW_DOSSIER", "REVIEW_EVIDENCE"], 3);
      const staff = await staffFor("acceso-visible");

      const res = await http()
        .get(`/ecf/platform/dgii/applications/${company.companyId}/access`)
        .set(auth(staff.token))
        .expect(200);

      expect(res.body.companyId).toBe(company.companyId);
      expect(res.body.grant.scopes).toEqual(
        expect.arrayContaining(["VIEW_DOSSIER", "REVIEW_EVIDENCE"]),
      );
      expect(res.body.grant.expiresAt).toBeTruthy();
      // Nunca se expone el almacenamiento ni datos del cliente.
      expect(JSON.stringify(res.body)).not.toContain("storageRef");
    });

    it("sin concesión la ruta de alcance también se deniega", async () => {
      const company = await registerTenant("acceso-denegado");
      const staff = await staffFor("acceso-denegado");
      const res = await http()
        .get(`/ecf/platform/dgii/applications/${company.companyId}/access`)
        .set(auth(staff.token))
        .expect(403);
      expect(JSON.stringify(res.body)).toContain("ECF_SUPPORT_GRANT_MISSING");
    });
  });

  describe("escalada de privilegios", () => {    it("tener una concesión NO convierte al usuario en staff de plataforma", async () => {
      const a = await registerTenant("escalada");
      await http().get("/ecf/dgii/habilitation").set(auth(a.token)).expect(200);
      await grant(a.token, [
        "VIEW_DOSSIER",
        "REVIEW_EVIDENCE",
        "REQUEST_CORRECTION",
      ]);

      // El propio usuario que concedió la asistencia sigue sin ser staff.
      const me = await http()
        .get("/ecf/platform/me")
        .set(auth(a.token))
        .expect(403);
      expect(JSON.stringify(me.body)).toContain("PLATFORM_STAFF_REQUIRED");

      const inbox = await http()
        .get("/ecf/platform/dgii/applications")
        .set(auth(a.token))
        .expect(403);
      expect(JSON.stringify(inbox.body)).toContain("PLATFORM_STAFF_REQUIRED");
    });

    it("una concesión solo la puede crear la empresa dueña, nunca el staff por otra", async () => {
      const target = await registerTenant("ajena-grant");
      const staff = await staffFor("intruso");

      // El staff crea una concesión para SÍ mismo (su propio companyId del token).
      await http()
        .post("/ecf/dgii/support-grants")
        .set(auth(staff.token))
        .send({ scopes: ["VIEW_DOSSIER"], expiresAt: expiresIn(7) })
        .expect(201);

      // Eso no le abre el expediente ajeno.
      await http()
        .get(detailUrl(target.companyId))
        .set(auth(staff.token))
        .expect(403);
    });
  });

  describe("auditoría append-only", () => {
    it("alta, acceso concedido, acceso denegado y revocación quedan registrados", async () => {
      const company = await registerTenant("auditoria");
      await http()
        .get("/ecf/dgii/habilitation")
        .set(auth(company.token))
        .expect(200);
      const staff = await staffFor("auditoria");

      // 1) Alta
      const grantId = await grant(company.token, ["VIEW_DOSSIER"]);
      // 2) Acceso concedido
      await http()
        .get(detailUrl(company.companyId))
        .set(auth(staff.token))
        .expect(200);
      // 3) Acceso denegado por alcance insuficiente
      const denied = await http()
        .patch(
          `/ecf/platform/dgii/applications/${company.companyId}/requirements/FISCAL_DATA`,
        )
        .set(auth(staff.token))
        .send({ status: "IN_PROGRESS" })
        .expect(403);
      expect(JSON.stringify(denied.body)).toContain(
        "ECF_SUPPORT_SCOPE_NOT_GRANTED",
      );
      // 4) Revocación
      await http()
        .post(`/ecf/dgii/support-grants/${grantId}/revoke`)
        .set(auth(company.token))
        .send({})
        .expect(201);

      const rows = await prisma.ecfAuditLog.findMany({
        where: {
          companyId: company.companyId,
          action: {
            in: [
              EcfAuditAction.SUPPORT_GRANT_CREATED,
              EcfAuditAction.SUPPORT_ACCESS_GRANTED,
              EcfAuditAction.SUPPORT_ACCESS_DENIED,
              EcfAuditAction.SUPPORT_GRANT_REVOKED,
            ],
          },
        },
        orderBy: { createdAt: "asc" },
      });
      const actions = rows.map((row) => row.action);

      expect(actions).toContain("SUPPORT_GRANT_CREATED");
      expect(actions).toContain("SUPPORT_ACCESS_GRANTED");
      expect(actions).toContain("SUPPORT_ACCESS_DENIED");
      expect(actions).toContain("SUPPORT_GRANT_REVOKED");

      // El actor real se registra: el staff en las denegaciones, la empresa en
      // el alta y la revocación.
      const deniedRow = rows.find(
        (row) => row.action === "SUPPORT_ACCESS_DENIED",
      );
      expect(deniedRow?.actorUserId).toBe(staff.userId);
      expect(JSON.stringify(deniedRow?.after)).toContain(
        "ECF_SUPPORT_SCOPE_NOT_GRANTED",
      );

      const createdRow = rows.find(
        (row) => row.action === "SUPPORT_GRANT_CREATED",
      );
      expect(createdRow?.actorUserId).toBe(company.userId);
      expect(createdRow?.targetId).toBe(grantId);
    });

    it("renovar tras caducidad registra SUPPORT_GRANT_EXPIRED sin borrar la anterior", async () => {
      const company = await registerTenant("caducidad-audit");
      const stale = await prisma.ecfSupportGrant.create({
        data: {
          companyId: company.companyId,
          grantedByUserId: company.userId,
          scopes: ["VIEW_DOSSIER"],
          expiresAt: new Date(Date.now() - 60_000),
        },
        select: { id: true },
      });

      const newId = await grant(company.token, ["VIEW_DOSSIER"]);
      expect(newId).not.toBe(stale.id);

      const expiredRows = await prisma.ecfAuditLog.findMany({
        where: {
          companyId: company.companyId,
          action: EcfAuditAction.SUPPORT_GRANT_EXPIRED,
        },
      });
      expect(expiredRows).toHaveLength(1);
      expect(expiredRows[0].targetId).toBe(stale.id);
      // El registro de la concesión caducada sigue existiendo: se cierra, no se borra.
      const stillThere = await prisma.ecfSupportGrant.findUnique({
        where: { id: stale.id },
        select: { revokedAt: true },
      });
      expect(stillThere).not.toBeNull();
      expect(stillThere?.revokedAt).not.toBeNull();
    });

    it("la auditoría se acumula: los eventos nuevos no pisan los anteriores", async () => {
      const company = await registerTenant("acumulativa");
      await http()
        .get("/ecf/dgii/habilitation")
        .set(auth(company.token))
        .expect(200);
      const staff = await staffFor("acumulativa");
      const grantId = await grant(company.token, ["VIEW_DOSSIER"]);

      await http()
        .get(detailUrl(company.companyId))
        .set(auth(staff.token))
        .expect(200);
      const firstBatch = await prisma.ecfAuditLog.findMany({
        where: { companyId: company.companyId },
        orderBy: { createdAt: "asc" },
        select: { id: true, action: true },
      });
      expect(firstBatch.length).toBeGreaterThanOrEqual(2);

      await http()
        .get(detailUrl(company.companyId))
        .set(auth(staff.token))
        .expect(200);
      await http()
        .post(`/ecf/dgii/support-grants/${grantId}/revoke`)
        .set(auth(company.token))
        .send({})
        .expect(201);

      const secondBatch = await prisma.ecfAuditLog.findMany({
        where: { companyId: company.companyId },
        orderBy: { createdAt: "asc" },
        select: { id: true, action: true },
      });
      expect(secondBatch.length).toBeGreaterThan(firstBatch.length);
      // Ningún identificador previo desapareció ni cambió de acción.
      for (const previous of firstBatch) {
        const current = secondBatch.find((row) => row.id === previous.id);
        expect(current).toBeDefined();
        expect(current?.action).toBe(previous.action);
      }
    });

    it("no existe ninguna ruta HTTP que borre o edite la auditoría", async () => {
      const company = await registerTenant("sin-ruta-audit");
      const grantId = await grant(company.token, ["VIEW_DOSSIER"]);
      const before = await prisma.ecfAuditLog.count({
        where: { companyId: company.companyId },
      });
      expect(before).toBeGreaterThan(0);

      const candidates = [
        ["delete", "/ecf/dgii/audit"],
        ["delete", `/ecf/dgii/audit/${grantId}`],
        ["patch", "/ecf/dgii/audit"],
        ["delete", "/ecf/platform/dgii/audit"],
        ["delete", `/ecf/platform/dgii/applications/${company.companyId}/audit`],
      ] as const;

      for (const [method, url] of candidates) {
        const res = await http()[method](url).set(auth(company.token)).send({});
        expect([403, 404, 405]).toContain(res.status);
      }

      const after = await prisma.ecfAuditLog.count({
        where: { companyId: company.companyId },
      });
      expect(after).toBe(before);
    });

    it("la auditoría de una empresa no se mezcla con la de otra", async () => {
      const a = await registerTenant("audit-a");
      const b = await registerTenant("audit-b");
      await grant(a.token, ["VIEW_DOSSIER"]);
      await grant(b.token, ["VIEW_DOSSIER"]);

      const rowsA = await prisma.ecfAuditLog.findMany({
        where: { companyId: a.companyId },
      });
      const rowsB = await prisma.ecfAuditLog.findMany({
        where: { companyId: b.companyId },
      });
      expect(rowsA.length).toBeGreaterThan(0);
      expect(rowsB.length).toBeGreaterThan(0);
      const idsA = new Set(rowsA.map((row) => row.id));
      expect(rowsB.some((row) => idsA.has(row.id))).toBe(false);
      expect(new Set(rowsA.map((row) => row.companyId))).toEqual(
        new Set([a.companyId]),
      );
    });
  });
});
