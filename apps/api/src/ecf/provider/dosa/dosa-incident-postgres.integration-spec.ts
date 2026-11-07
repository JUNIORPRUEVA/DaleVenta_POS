import { PrismaClient } from "@prisma/client";
import {
  DOSA_INCIDENT_STATUS,
} from "./dosa-incident.policy";
import {
  DosaIncidentService,
  type DosaIncidentRetryRunner,
} from "./dosa-incident.service";
import { DosaIncidentRetryAdapter } from "./dosa-incident-retry.adapter";
import { EcfDosaSessionService } from "./ecf-dosa-session.service";

/**
 * Vigilancia de incidencias DOSA sobre PostgreSQL REAL.
 *
 * Las pruebas unitarias usan un doble de Prisma; aquí se ejecuta el SQL de
 * detección tal cual, que es lo único que un doble no puede demostrar: que las
 * condiciones se localizan por empresa, que no se duplican alertas y que el
 * reintento seguro deja la base en el estado correcto.
 *
 * Solo contra una base DESECHABLE declarada explícitamente:
 *
 *   $env:ECF_POSTGRES_UAT = "true"
 *   $env:DATABASE_URL = "postgresql://.../base_desechable"
 */
const real = process.env.ECF_POSTGRES_UAT === "true" ? describe : describe.skip;

const COMPANY_A = "f1f1f1f1-0000-4000-8000-0000000000f1";
const COMPANY_B = "f2f2f2f2-0000-4000-8000-0000000000f2";
const RNC_A = "133080299";
const RNC_B = "130000902";
const COMPANIES = [COMPANY_A, COMPANY_B];

real("Incidencias DOSA — detección y recuperación en PostgreSQL real", () => {
  let prisma: PrismaClient;
  let service: DosaIncidentService;
  let sessions: EcfDosaSessionService;

  beforeAll(async () => {
    prisma = new PrismaClient();
    sessions = new EcfDosaSessionService(prisma as never);
    await cleanupAll();
    for (const [id, slug] of [
      [COMPANY_A, "incidentes-a"],
      [COMPANY_B, "incidentes-b"],
    ]) {
      await prisma.$executeRaw`
        INSERT INTO "companies" ("id","name","slug","updated_at")
        VALUES (${id}::uuid, ${slug}, ${slug}, NOW())
        ON CONFLICT ("id") DO NOTHING
      `;
    }
    const retry = new DosaIncidentRetryAdapter(sessions) as DosaIncidentRetryRunner;
    service = new DosaIncidentService(prisma as never, retry);
  }, 60000);

  beforeEach(async () => {
    await cleanupAll();
  });

  afterAll(async () => {
    await cleanupAll();
    await prisma.$executeRaw`DELETE FROM "companies" WHERE "id" = ANY(${COMPANIES}::uuid[])`;
    await prisma.$disconnect();
  });

  async function cleanupAll() {
    await prisma.$executeRaw`DELETE FROM "ecf_dosa_incidents" WHERE "company_id" = ANY(${COMPANIES}::uuid[])`;
    await prisma.$executeRaw`DELETE FROM "ecf_dosa_webhook_events" WHERE "company_id" = ANY(${COMPANIES}::uuid[])`;
    await prisma.$executeRaw`DELETE FROM "ecf_dosa_company_credentials" WHERE "company_id" = ANY(${COMPANIES}::uuid[])`;
    await prisma.$executeRaw`DELETE FROM "ecf_dosa_certification_sessions" WHERE "company_id" = ANY(${COMPANIES}::uuid[])`;
  }

  async function activeSession(companyId: string, rnc: string) {
    await prisma.$executeRaw`
      INSERT INTO "ecf_dosa_certification_sessions"
        ("id","company_id","rnc","attempt_no","active_key","status","updated_at")
      VALUES
        (gen_random_uuid(), ${companyId}::uuid, ${rnc}, 1,
         ${`${companyId}:${rnc}`}, 'RUNNING', NOW())
    `;
  }

  async function event(input: {
    companyId: string;
    rnc: string;
    postulacionId: string;
    processingState: string;
    eventType?: string;
    minutesAgo?: number;
  }) {
    const summary = JSON.stringify({ rnc: input.rnc, event: "PENDING_CLASSIFICATION" });
    await prisma.$executeRaw`
      INSERT INTO "ecf_dosa_webhook_events"
        ("id","company_id","dedupe_key","event_type","postulacion_id",
         "estado_certificacion","raw_body_sha256","payload_summary",
         "signature_status","processing_state","received_at")
      VALUES
        (gen_random_uuid(), ${input.companyId}::uuid, ${`key-${Math.random()}`},
         ${input.eventType ?? "PENDING_CLASSIFICATION"}, ${input.postulacionId},
         'finalizado', ${"a".repeat(64)}, ${summary}::jsonb,
         'HMAC_SHA256_TIMESTAMPED', ${input.processingState},
         NOW() - (${input.minutesAgo ?? 60} || ' minutes')::interval)
    `;
  }

  async function pendingCredential(input: {
    companyId: string;
    rnc: string;
    environment: string;
    minutesAgo?: number;
  }) {
    await prisma.$executeRaw`
      INSERT INTO "ecf_dosa_company_credentials"
        ("id","company_id","rnc","environment","status","source","key_version",
         "ciphertext","iv","auth_tag","fingerprint","present","created_at","updated_at")
      VALUES
        (gen_random_uuid(), ${input.companyId}::uuid, ${input.rnc},
         ${input.environment}, 'PENDING_CONFIRMATION', 'WEBHOOK', 1,
         'cipher', 'iv', 'tag', ${"b".repeat(64)}, '{"apiKeyTest":true}'::jsonb,
         NOW() - (${input.minutesAgo ?? 60} || ' minutes')::interval, NOW())
    `;
  }

  async function incidentsOf(companyId: string) {
    return prisma.$queryRaw<
      Array<{
        kind: string;
        severity: string;
        status: string;
        incident_key: string;
        attempts: number;
        subject_ref: string | null;
      }>
    >`
      SELECT "kind","severity","status","incident_key","attempts","subject_ref"
        FROM "ecf_dosa_incidents"
       WHERE "company_id" = ${companyId}::uuid
       ORDER BY "kind"
    `;
  }

  it("detecta las cinco condiciones de una empresa", async () => {
    await activeSession(COMPANY_A, RNC_A);
    await event({
      companyId: COMPANY_A,
      rnc: RNC_A,
      postulacionId: "post-sin-guardar",
      processingState: "PENDING_CREDENTIALS",
    });
    await event({
      companyId: COMPANY_A,
      rnc: RNC_A,
      postulacionId: "post-conflicto",
      processingState: "CONFLICT_PENDING_REVIEW",
      eventType: "PENDING_CLASSIFICATION",
    });
    await event({
      companyId: COMPANY_A,
      rnc: RNC_A,
      postulacionId: "post-completa",
      processingState: "COMPLETE",
      eventType: "EMPRESA_CONECTADA",
    });
    await pendingCredential({
      companyId: COMPANY_A,
      rnc: RNC_A,
      environment: "test",
    });

    const summary = await service.scan({ staleMinutes: 0 });
    expect(summary.errors).toBe(0);

    const kinds = (await incidentsOf(COMPANY_A)).map((row) => row.kind).sort();
    expect(kinds).toEqual([
      "CREDENTIAL_AWAITING_CONFIRMATION",
      "CREDENTIAL_CONFLICT_REVIEW",
      "EVENT_CREDENTIALS_NOT_STORED",
      "EVENT_TYPE_UNKNOWN",
      "POSTULATION_NOT_BOUND",
    ]);
  }, 60000);

  it("no repite la alerta en barridos sucesivos", async () => {
    await event({
      companyId: COMPANY_A,
      rnc: RNC_A,
      postulacionId: "post-1",
      processingState: "PENDING_CREDENTIALS",
      eventType: "EMPRESA_CONECTADA",
    });

    await service.scan({ staleMinutes: 0 });
    await service.scan({ staleMinutes: 0 });
    await service.scan({ staleMinutes: 0 });

    const rows = await incidentsOf(COMPANY_A);
    expect(rows).toHaveLength(1);
    expect(rows[0].kind).toBe("EVENT_CREDENTIALS_NOT_STORED");
  }, 60000);

  it("aísla las incidencias de cada empresa", async () => {
    await event({
      companyId: COMPANY_A,
      rnc: RNC_A,
      postulacionId: "post-a",
      processingState: "PENDING_CREDENTIALS",
      eventType: "EMPRESA_CONECTADA",
    });
    await event({
      companyId: COMPANY_B,
      rnc: RNC_B,
      postulacionId: "post-b",
      processingState: "CONFLICT_PENDING_REVIEW",
      eventType: "EMPRESA_CONECTADA",
    });

    await service.scan({ staleMinutes: 0 });

    const a = await incidentsOf(COMPANY_A);
    const b = await incidentsOf(COMPANY_B);
    expect(a.map((row) => row.kind)).toEqual(["EVENT_CREDENTIALS_NOT_STORED"]);
    expect(b.map((row) => row.kind)).toEqual(["CREDENTIAL_CONFLICT_REVIEW"]);
    expect(a[0].subject_ref).toBe("post-a");
    expect(b[0].subject_ref).toBe("post-b");
  }, 60000);

  it("el reintento seguro vincula la postulación y cierra la incidencia", async () => {
    await activeSession(COMPANY_A, RNC_A);
    await event({
      companyId: COMPANY_A,
      rnc: RNC_A,
      postulacionId: "post-reintento",
      processingState: "COMPLETE",
      eventType: "EMPRESA_CONECTADA",
    });

    const first = await service.scan({ staleMinutes: 0 });
    expect(first.retried).toBe(1);
    expect(first.retrySucceeded).toBe(1);

    const bound = await prisma.$queryRaw<Array<{ provider_postulation_id: string | null }>>`
      SELECT "provider_postulation_id"
        FROM "ecf_dosa_certification_sessions"
       WHERE "company_id" = ${COMPANY_A}::uuid AND "rnc" = ${RNC_A}
    `;
    expect(bound[0].provider_postulation_id).toBe("post-reintento");

    const rows = await incidentsOf(COMPANY_A);
    const unbound = rows.find((row) => row.kind === "POSTULATION_NOT_BOUND");
    expect(unbound?.status).toBe(DOSA_INCIDENT_STATUS.RESOLVED);
    expect(unbound?.attempts).toBe(1);
  }, 60000);

  // Con varias réplicas del backend, dos barridos pueden coincidir. El reclamo
  // atómico (`UPDATE ... RETURNING`) debe dejar que solo uno ejecute y cuente el
  // intento: si no, el backoff se agota antes de tiempo.
  it("dos barridos simultáneos cuentan el intento UNA sola vez", async () => {
    await activeSession(COMPANY_B, RNC_B);
    await event({
      companyId: COMPANY_B,
      rnc: RNC_B,
      postulacionId: "post-carrera",
      processingState: "COMPLETE",
      eventType: "EMPRESA_CONECTADA",
    });

    const [first, second] = await Promise.all([
      service.scan({ staleMinutes: 0 }),
      service.scan({ staleMinutes: 0 }),
    ]);

    // La vinculación es idempotente, así que el estado final es el correcto…
    const bound = await prisma.$queryRaw<Array<{ provider_postulation_id: string | null }>>`
      SELECT "provider_postulation_id"
        FROM "ecf_dosa_certification_sessions"
       WHERE "company_id" = ${COMPANY_B}::uuid AND "rnc" = ${RNC_B}
    `;
    expect(bound[0].provider_postulation_id).toBe("post-carrera");

    // …y el intento se contó una sola vez entre los dos barridos.
    const rows = await prisma.$queryRaw<Array<{ attempts: number; status: string }>>`
      SELECT "attempts","status"
        FROM "ecf_dosa_incidents"
       WHERE "company_id" = ${COMPANY_B}::uuid AND "kind" = 'POSTULATION_NOT_BOUND'
    `;
    expect(rows).toHaveLength(1);
    expect(rows[0].attempts).toBe(1);
    expect(rows[0].status).toBe(DOSA_INCIDENT_STATUS.RESOLVED);
    expect(first.retrySucceeded + second.retrySucceeded).toBeLessThanOrEqual(1);
  }, 60000);

  it("no reintenta una condición que dejaría de ser segura", async () => {    // Sin sesión activa no hay nada que vincular: la condición ni siquiera se
    // detecta, así que no se genera un reintento inútil.
    await event({
      companyId: COMPANY_B,
      rnc: RNC_B,
      postulacionId: "post-huerfana",
      processingState: "COMPLETE",
      eventType: "EMPRESA_CONECTADA",
    });

    const summary = await service.scan({ staleMinutes: 0 });

    const rows = await incidentsOf(COMPANY_B);
    expect(rows.some((row) => row.kind === "POSTULATION_NOT_BOUND")).toBe(false);
    expect(summary.retried).toBe(0);
  }, 60000);

  it("resuelve sola la incidencia cuando la condición desaparece", async () => {
    await event({
      companyId: COMPANY_A,
      rnc: RNC_A,
      postulacionId: "post-resuelta",
      processingState: "PENDING_CREDENTIALS",
      eventType: "EMPRESA_CONECTADA",
    });
    await service.scan({ staleMinutes: 0 });
    expect((await incidentsOf(COMPANY_A))[0].status).toBe(DOSA_INCIDENT_STATUS.OPEN);

    // El proveedor reenvía el evento y ahora sí se guarda: la condición cesa.
    await prisma.$executeRaw`
      UPDATE "ecf_dosa_webhook_events"
         SET "processing_state" = 'COMPLETE'
       WHERE "company_id" = ${COMPANY_A}::uuid
    `;
    await service.scan({ staleMinutes: 0 });

    const rows = await incidentsOf(COMPANY_A);
    expect(rows[0].status).toBe(DOSA_INCIDENT_STATUS.RESOLVED);
    expect(rows[0].incident_key).toBe("EVENT_CREDENTIALS_NOT_STORED:post-resuelta");
  }, 60000);

  it("cierra con motivo del catálogo y no vuelve a abrirse", async () => {
    await event({
      companyId: COMPANY_A,
      rnc: RNC_A,
      postulacionId: "post-cierre",
      processingState: "CONFLICT_PENDING_REVIEW",
      eventType: "EMPRESA_CONECTADA",
    });
    await service.scan({ staleMinutes: 0 });
    const [incident] = await prisma.$queryRaw<Array<{ id: string }>>`
      SELECT "id" FROM "ecf_dosa_incidents"
       WHERE "company_id" = ${COMPANY_A}::uuid
    `;

    const closed = await service.close({
      incidentId: incident.id,
      companyId: COMPANY_A,
      resolution: "ROTATION_AUTHORIZED",
      actorUserId: "00000000-0000-4000-8000-000000000001",
    });
    expect(closed.ok).toBe(true);

    // La condición sigue viva en la base, pero la incidencia ya está cerrada: el
    // barrido no la reabre, porque un cierre humano es terminal.
    await service.scan({ staleMinutes: 0 });
    const rows = await incidentsOf(COMPANY_A);
    expect(rows[0].status).toBe(DOSA_INCIDENT_STATUS.CLOSED);
  }, 60000);
});
