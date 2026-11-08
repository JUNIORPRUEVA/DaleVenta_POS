import { PrismaClient } from "@prisma/client";
import { randomUUID } from "node:crypto";

import { EcfPortalEnrollmentService } from "./ecf-portal-enrollment.service";
import { EcfCertificationPortalService } from "./ecf-certification-portal.service";

/**
 * Autorización del asistente e-CF POR EMPRESA sobre PostgreSQL REAL.
 *
 * Lo que un doble de Prisma no puede demostrar y aquí sí:
 *  - el índice único parcial impide dos autorizaciones vigentes a la vez;
 *  - la elegibilidad se calcula con el reloj de la base y deja de valer sola
 *    cuando la autorización caduca;
 *  - revocar conserva la fila y devuelve el acceso a `NO_AUTHORIZATION`;
 *  - dos empresas son independientes: autorizar una no habilita a la otra.
 *
 * Solo contra una base DESECHABLE declarada explícitamente:
 *
 *   $env:ECF_POSTGRES_UAT = "true"
 *   $env:DATABASE_URL = "postgresql://.../base_desechable"
 */
const real = process.env.ECF_POSTGRES_UAT === "true" ? describe : describe.skip;

const COMPANY_A = "a1a1a1a1-0000-4000-8000-0000000000a1";
const COMPANY_B = "b2b2b2b2-0000-4000-8000-0000000000b2";
const COMPANIES = [COMPANY_A, COMPANY_B];

real("Autorización del portal e-CF — PostgreSQL real", () => {
  let prisma: PrismaClient;
  let service: EcfPortalEnrollmentService;

  beforeAll(async () => {
    prisma = new PrismaClient();
    service = new EcfPortalEnrollmentService(prisma as never);
    await cleanupAll();
    for (const [id, slug] of [
      [COMPANY_A, "portal-a"],
      [COMPANY_B, "portal-b"],
    ]) {
      await prisma.$executeRaw`
        INSERT INTO "companies" ("id","name","slug","updated_at")
        VALUES (${id}::uuid, ${slug}, ${slug}, NOW())
        ON CONFLICT ("id") DO NOTHING
      `;
    }
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
    await prisma.$executeRaw`DELETE FROM "ecf_portal_enrollments" WHERE "company_id" = ANY(${COMPANIES}::uuid[])`;
  }

  it("sin autorización, una empresa nueva NO es elegible (cerrado por defecto)", async () => {
    const result = await service.eligibility(COMPANY_A, { env: {} });
    expect(result.eligible).toBe(false);
    expect(result.reason).toBe("NO_AUTHORIZATION");
  });

  it("una empresa nueva entra con una autorización registrada, sin tocar el entorno", async () => {
    const granted = await service.grant({
      companyId: COMPANY_A,
      source: "ADMIN_AUTHORIZATION",
      reason: "Alta comercial autorizada",
      actorUserId: null,
    });
    expect(granted).toMatchObject({ ok: true, created: true });

    const result = await service.eligibility(COMPANY_A, { env: {} });
    expect(result.eligible).toBe(true);
    expect(result.reason).toBe("ENROLLED");
    expect(result.source).toBe("ADMIN_AUTHORIZATION");
  });

  it("autorizar A no habilita a B", async () => {
    await service.grant({
      companyId: COMPANY_A,
      source: "ADMIN_AUTHORIZATION",
      reason: "Alta comercial autorizada",
      actorUserId: null,
    });

    expect((await service.eligibility(COMPANY_A, { env: {} })).eligible).toBe(true);
    expect((await service.eligibility(COMPANY_B, { env: {} })).eligible).toBe(false);
  });

  it("el índice único parcial impide dos autorizaciones vigentes", async () => {
    await service.grant({
      companyId: COMPANY_A,
      source: "ADMIN_AUTHORIZATION",
      reason: "Primera autorización",
      actorUserId: null,
    });

    // Inserción directa, sin pasar por el servicio: la base debe rechazarla.
    await expect(
      prisma.$executeRaw`
        INSERT INTO "ecf_portal_enrollments"
          ("id","company_id","source","status","reason","created_at","updated_at")
        VALUES
          (gen_random_uuid(), ${COMPANY_A}::uuid, 'ADMIN_AUTHORIZATION', 'ACTIVE',
           'duplicada a propósito', NOW(), NOW())
      `,
    ).rejects.toThrow();
  });

  it("el servicio es idempotente: no crea una segunda vigente", async () => {
    const first = await service.grant({
      companyId: COMPANY_A,
      source: "ADMIN_AUTHORIZATION",
      reason: "Primera autorización",
      actorUserId: null,
    });
    const second = await service.grant({
      companyId: COMPANY_A,
      source: "CONTRACT_REFERENCE",
      reason: "Segunda autorización",
      actorUserId: null,
    });

    expect(first).toMatchObject({ created: true });
    expect(second).toMatchObject({ created: false });
    const rows = await prisma.ecfPortalEnrollment.count({
      where: { companyId: COMPANY_A },
    });
    expect(rows).toBe(1);
  });

  it("una autorización caducada deja de servir SIN que nadie intervenga", async () => {
    await prisma.$executeRaw`
      INSERT INTO "ecf_portal_enrollments"
        ("id","company_id","source","status","reason","expires_at","created_at","updated_at")
      VALUES
        (gen_random_uuid(), ${COMPANY_A}::uuid, 'CONTRACT_REFERENCE', 'ACTIVE',
         'contrato vencido', NOW() - INTERVAL '1 minute', NOW(), NOW())
    `;

    const result = await service.eligibility(COMPANY_A, { env: {} });
    expect(result.eligible).toBe(false);
    expect(result.reason).toBe("AUTHORIZATION_EXPIRED");
  });

  it("revocar conserva el historial y corta el acceso", async () => {
    await service.grant({
      companyId: COMPANY_A,
      source: "ADMIN_AUTHORIZATION",
      reason: "Alta comercial autorizada",
      actorUserId: null,
    });

    const revoked = await service.revoke({
      companyId: COMPANY_A,
      actorUserId: null,
      reason: "Baja solicitada por el cliente",
    });
    expect(revoked).toEqual({ ok: true, revoked: 1 });

    // La fila sigue existiendo: nada se borró.
    const rows = await service.history(COMPANY_A);
    expect(rows).toHaveLength(1);
    expect(rows[0]).toMatchObject({
      status: "REVOKED",
      revocationReason: "Baja solicitada por el cliente",
    });

    const result = await service.eligibility(COMPANY_A, { env: {} });
    expect(result.eligible).toBe(false);
    expect(result.reason).toBe("AUTHORIZATION_REVOKED");
  });

  it("tras revocar se puede autorizar de nuevo, y la nueva vigente manda", async () => {
    await service.grant({
      companyId: COMPANY_A,
      source: "ADMIN_AUTHORIZATION",
      reason: "Alta comercial autorizada",
      actorUserId: null,
    });
    await service.revoke({
      companyId: COMPANY_A,
      actorUserId: null,
      reason: "Baja solicitada por el cliente",
    });
    const again = await service.grant({
      companyId: COMPANY_A,
      source: "CONTRACT_REFERENCE",
      reason: "Reactivación con contrato nuevo",
      actorUserId: null,
    });
    expect(again).toMatchObject({ ok: true, created: true });

    const result = await service.eligibility(COMPANY_A, { env: {} });
    expect(result.eligible).toBe(true);
    expect(result.reason).toBe("ENROLLED");

    const rows = await service.history(COMPANY_A);
    expect(rows).toHaveLength(2);
    expect(rows.filter((row) => row.status === "ACTIVE")).toHaveLength(1);
  });

  it("el portal usa la autorización de la base: emite boleto sin variable de entorno", async () => {
    const previous = process.env.ECF_PORTAL_PILOT_COMPANY_IDS;
    process.env.ECF_PORTAL_PILOT_COMPANY_IDS = "";
    try {
      await service.grant({
        companyId: COMPANY_A,
        source: "ADMIN_AUTHORIZATION",
        reason: "Alta comercial autorizada",
        actorUserId: null,
      });

      const portal = new EcfCertificationPortalService(prisma as never, service);
      const eligibility = await portal.eligibility(COMPANY_A);
      expect(eligibility.eligible).toBe(true);
      await expect(portal.isPilotCompany(COMPANY_A)).resolves.toBe(true);
      await expect(portal.isPilotCompany(COMPANY_B)).resolves.toBe(false);
    } finally {
      if (previous === undefined) delete process.env.ECF_PORTAL_PILOT_COMPANY_IDS;
      else process.env.ECF_PORTAL_PILOT_COMPANY_IDS = previous;
    }
  });

  it("dos autorizaciones simultáneas no rompen la regla de una sola vigente", async () => {
    const results = await Promise.all([
      service.grant({
        companyId: COMPANY_B,
        source: "ADMIN_AUTHORIZATION",
        reason: "Concesión concurrente uno",
        actorUserId: null,
      }),
      service.grant({
        companyId: COMPANY_B,
        source: "ADMIN_AUTHORIZATION",
        reason: "Concesión concurrente dos",
        actorUserId: null,
      }),
    ]);

    expect(results.every((result) => result.ok)).toBe(true);
    const active = await prisma.ecfPortalEnrollment.count({
      where: { companyId: COMPANY_B, status: "ACTIVE" },
    });
    expect(active).toBe(1);
  });

  it("el webhook resuelve la empresa por RNC y declara su elegibilidad", async () => {
    const rnc = `9${randomUUID().replace(/\D/g, "").slice(0, 10)}`;
    await prisma.$executeRaw`
      INSERT INTO "ecf_dosa_certification_sessions"
        ("id","company_id","rnc","attempt_no","active_key","status","updated_at")
      VALUES
        (gen_random_uuid(), ${COMPANY_A}::uuid, ${rnc}, 1,
         ${`${COMPANY_A}:${rnc}`}, 'NOT_STARTED', NOW())
    `;
    try {
      await service.grant({
        companyId: COMPANY_A,
        source: "ADMIN_AUTHORIZATION",
        reason: "Alta comercial autorizada",
        actorUserId: null,
      });

      const rows = await prisma.$queryRaw<
        { company_id: string; portal_eligible: boolean }[]
      >`
        SELECT s."company_id" AS company_id,
               EXISTS (
                 SELECT 1 FROM "ecf_portal_enrollments" e
                  WHERE e."company_id" = s."company_id"
                    AND e."status" = 'ACTIVE'
                    AND e."revoked_at" IS NULL
                    AND (e."expires_at" IS NULL OR e."expires_at" > NOW())
               ) AS portal_eligible
          FROM "ecf_dosa_certification_sessions" s
         WHERE s."rnc" = ${rnc}
      `;

      expect(rows).toHaveLength(1);
      expect(rows[0].portal_eligible).toBe(true);
    } finally {
      await prisma.$executeRaw`DELETE FROM "ecf_dosa_certification_sessions" WHERE "company_id" = ${COMPANY_A}::uuid`;
    }
  });
});
