import { PrismaClient } from "@prisma/client";
import { EcfDosaSessionService } from "./ecf-dosa-session.service";

/**
 * Pruebas REALES contra PostgreSQL de la sesión de certificación DOSA.
 *
 * Se ejecutan solo con una base desechable declarada explícitamente:
 *
 *   $env:ECF_POSTGRES_UAT = "true"
 *   $env:DATABASE_URL = "postgresql://.../base_desechable"
 *
 * Nunca contra UAT ni producción. Cada prueba limpia lo suyo.
 */
const uat = process.env.ECF_POSTGRES_UAT === "true" ? describe : describe.skip;

const COMPANY_A = "11111111-1111-4111-8111-111111111111";
const COMPANY_B = "22222222-2222-4222-8222-222222222222";
const RNC_A = "101000001";
const RNC_B = "101000002";

uat("EcfDosaCertificationSession — PostgreSQL real", () => {
  let prisma: PrismaClient;
  let service: EcfDosaSessionService;

  beforeAll(async () => {
    prisma = new PrismaClient();
    service = new EcfDosaSessionService(prisma);
    for (const [id, slug] of [
      [COMPANY_A, "dosa-test-a"],
      [COMPANY_B, "dosa-test-b"],
    ]) {
      await prisma.$executeRaw`
        INSERT INTO "companies" ("id","name","slug","updated_at")
        VALUES (${id}::uuid, ${slug}, ${slug}, NOW())
        ON CONFLICT ("id") DO NOTHING
      `;
    }
  });

  beforeEach(async () => {
    await cleanup();
  });

  afterAll(async () => {
    await cleanup();
    await prisma.$executeRaw`
      DELETE FROM "companies" WHERE "id" IN (${COMPANY_A}::uuid, ${COMPANY_B}::uuid)
    `;
    await prisma.$disconnect();
  });

  async function cleanup() {
    await prisma.$executeRaw`
      DELETE FROM "ecf_dosa_certification_sessions"
       WHERE "company_id" IN (${COMPANY_A}::uuid, ${COMPANY_B}::uuid)
    `;
  }

  async function rows(): Promise<
    Array<{
      id: string;
      attempt_no: number;
      active_key: string | null;
      status: string;
      last_event_type: string | null;
      provider_confirmed_at: Date | null;
      session_url: string | null;
    }>
  > {
    return prisma.$queryRaw`
      SELECT "id","attempt_no","active_key","status","last_event_type",
             "provider_confirmed_at","session_url"
        FROM "ecf_dosa_certification_sessions"
       WHERE "company_id" IN (${COMPANY_A}::uuid, ${COMPANY_B}::uuid)
       ORDER BY "attempt_no"
    `;
  }

  it("crea el primer intento con attempt_no = 1 y clave activa", async () => {
    const claim = await service.claim({ companyId: COMPANY_A, rnc: RNC_A });

    expect(claim).toMatchObject({ ok: true, created: true, attemptNo: 1 });
    const [row] = await rows();
    expect(row.active_key).toBe(`${COMPANY_A}:${RNC_A}`);
    expect(row.status).toBe("NOT_STARTED");
  });

  it("dos solicitudes simultaneas devuelven la MISMA sesion (sin duplicar)", async () => {
    const [first, second] = await Promise.all([
      service.claim({ companyId: COMPANY_A, rnc: RNC_A }),
      service.claim({ companyId: COMPANY_A, rnc: RNC_A }),
    ]);

    expect(first.ok && second.ok).toBe(true);
    if (!first.ok || !second.ok) return;
    expect(first.id).toBe(second.id);
    expect(await rows()).toHaveLength(1);
  });

  it("dos solicitudes simultaneas tras un intento cerrado no duplican", async () => {
    await service.claim({ companyId: COMPANY_A, rnc: RNC_A });
    await service.close({
      companyId: COMPANY_A,
      rnc: RNC_A,
      status: "EXPIRED",
    });

    const [first, second] = await Promise.all([
      service.claim({ companyId: COMPANY_A, rnc: RNC_A }),
      service.claim({ companyId: COMPANY_A, rnc: RNC_A }),
    ]);

    expect(first.ok && second.ok).toBe(true);
    if (!first.ok || !second.ok) return;
    expect(first.id).toBe(second.id);
    // Dos filas: el intento vencido (historial) y el nuevo.
    expect(await rows()).toHaveLength(2);
  });

  it("aísla por empresa y por RNC", async () => {
    const a = await service.claim({ companyId: COMPANY_A, rnc: RNC_A });
    const b = await service.claim({ companyId: COMPANY_B, rnc: RNC_A });
    const c = await service.claim({ companyId: COMPANY_A, rnc: RNC_B });

    expect(a.ok && b.ok && c.ok).toBe(true);
    if (!a.ok || !b.ok || !c.ok) return;
    expect(new Set([a.id, b.id, c.id]).size).toBe(3);
    expect(await rows()).toHaveLength(3);
  });

  it("recupera la sesion existente en lugar de crear otra", async () => {
    const first = await service.claim({ companyId: COMPANY_A, rnc: RNC_A });
    const second = await service.claim({ companyId: COMPANY_A, rnc: RNC_A });

    expect(first.ok && second.ok).toBe(true);
    if (!first.ok || !second.ok) return;
    expect(second.created).toBe(false);
    expect(second.id).toBe(first.id);
    expect(second.attemptNo).toBe(1);
  });

  it("permite repetir la postulacion tras un intento vencido, conservando historial", async () => {
    await service.claim({ companyId: COMPANY_A, rnc: RNC_A });
    const closed = await service.close({
      companyId: COMPANY_A,
      rnc: RNC_A,
      status: "EXPIRED",
    });

    const renewed = await service.claim({ companyId: COMPANY_A, rnc: RNC_A });

    expect(closed).toEqual({ closed: true });
    expect(renewed).toMatchObject({ ok: true, created: true, attemptNo: 2 });
    const all = await rows();
    expect(all.map((row) => row.attempt_no)).toEqual([1, 2]);
    expect(all[0].active_key).toBeNull();
    expect(all[0].status).toBe("EXPIRED");
    expect(all[1].active_key).toBe(`${COMPANY_A}:${RNC_A}`);
  });

  it("permite repetir tras FAILED, CANCELLED y COMPLETED", async () => {
    for (const status of ["FAILED", "CANCELLED", "COMPLETED"] as const) {
      await service.claim({ companyId: COMPANY_A, rnc: RNC_A });
      await service.close({ companyId: COMPANY_A, rnc: RNC_A, status });
    }
    const renewed = await service.claim({ companyId: COMPANY_A, rnc: RNC_A });

    expect(renewed).toMatchObject({ ok: true, created: true, attemptNo: 4 });
    expect(await rows()).toHaveLength(4);
  });

  it("no permite cerrar con un estado en curso", async () => {
    await service.claim({ companyId: COMPANY_A, rnc: RNC_A });

    await expect(
      service.close({
        companyId: COMPANY_A,
        rnc: RNC_A,
        status: "RUNNING" as never,
      }),
    ).rejects.toThrow(/ECF_DOSA_SESSION_INVALID_CLOSE_STATUS/);

    const [row] = await rows();
    expect(row.active_key).toBe(`${COMPANY_A}:${RNC_A}`);
    expect(row.status).toBe("NOT_STARTED");
  });

  it("un evento del navegador NO cambia estado ni confirma nada", async () => {
    await service.claim({ companyId: COMPANY_A, rnc: RNC_A });

    const hint = await service.recordEventHint({
      companyId: COMPANY_A,
      rnc: RNC_A,
      eventType: "cert:complete",
    });

    const [row] = await rows();
    expect(hint).toEqual({ updated: true });
    expect(row.last_event_type).toBe("cert:complete");
    // Lo esencial: `cert:complete` NO activa nada.
    expect(row.status).toBe("NOT_STARTED");
    expect(row.provider_confirmed_at).toBeNull();
  });

  it("un evento sin sesion no crea filas", async () => {
    const hint = await service.recordEventHint({
      companyId: COMPANY_B,
      rnc: RNC_B,
      eventType: "cert:postulacion",
    });

    expect(hint).toEqual({ updated: false });
    expect(await rows()).toHaveLength(0);
  });

  it("solo la confirmacion del backend marca provider_confirmed_at", async () => {
    await service.claim({ companyId: COMPANY_A, rnc: RNC_A });

    await service.applyProviderConfirmation({
      companyId: COMPANY_A,
      rnc: RNC_A,
      providerPostulationId: "POST-1",
    });

    const [row] = await rows();
    expect(row.provider_confirmed_at).not.toBeNull();
    // Aun confirmado el proveedor, el estado del asistente no cambia solo.
    expect(row.status).toBe("NOT_STARTED");
  });

  it("rechaza una empresa inexistente por integridad referencial", async () => {
    await expect(
      service.claim({
        companyId: "33333333-3333-4333-8333-333333333333",
        rnc: RNC_A,
      }),
    ).rejects.toBeTruthy();

    expect(await rows()).toHaveLength(0);
  });

  it("un claim invalido no deja filas a medias", async () => {
    const invalid = await service.claim({ companyId: COMPANY_A, rnc: "   " });

    expect(invalid).toEqual({ ok: false, reason: "MISSING_RNC" });
    expect(await rows()).toHaveLength(0);
  });

  it("la base impide dos intentos con el mismo numero", async () => {
    await service.claim({ companyId: COMPANY_A, rnc: RNC_A });

    await expect(
      prisma.$executeRaw`
        INSERT INTO "ecf_dosa_certification_sessions"
          ("id","company_id","rnc","attempt_no","active_key","created_at","updated_at")
        VALUES (gen_random_uuid(), ${COMPANY_A}::uuid, ${RNC_A}, 1, NULL, NOW(), NOW())
      `,
    ).rejects.toBeTruthy();
  });

  it("la base impide dos sesiones activas para la misma empresa y RNC", async () => {
    await service.claim({ companyId: COMPANY_A, rnc: RNC_A });

    await expect(
      prisma.$executeRaw`
        INSERT INTO "ecf_dosa_certification_sessions"
          ("id","company_id","rnc","attempt_no","active_key","created_at","updated_at")
        VALUES (gen_random_uuid(), ${COMPANY_A}::uuid, ${RNC_A}, 99,
                ${`${COMPANY_A}:${RNC_A}`}, NOW(), NOW())
      `,
    ).rejects.toBeTruthy();
  });

  it("permite varias sesiones cerradas (NULL en clave activa)", async () => {
    // PostgreSQL admite muchos NULL en un indice unico: el historial convive.
    await prisma.$executeRaw`
      INSERT INTO "ecf_dosa_certification_sessions"
        ("id","company_id","rnc","attempt_no","active_key","status","created_at","updated_at")
      VALUES (gen_random_uuid(), ${COMPANY_A}::uuid, ${RNC_A}, 1, NULL, 'EXPIRED', NOW(), NOW()),
             (gen_random_uuid(), ${COMPANY_A}::uuid, ${RNC_A}, 2, NULL, 'FAILED', NOW(), NOW())
    `;

    expect(await rows()).toHaveLength(2);
  });
});
