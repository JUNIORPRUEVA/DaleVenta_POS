import { PrismaClient } from "@prisma/client";
import { PrismaService } from "../../../prisma/prisma.service";
import { DosaWebhookService } from "./dosa-webhook.service";
import { PrismaDosaCompanyResolver } from "./dosa-company-resolver.service";

/**
 * Pruebas REALES del webhook DOSA contra PostgreSQL.
 *
 * Se ejecutan solo contra una base DESECHABLE declarada explícitamente:
 *
 *   $env:ECF_POSTGRES_UAT = "true"
 *   $env:DATABASE_URL = "postgresql://.../base_desechable"
 *
 * Comprueban lo que los dobles no pueden: que el `ON CONFLICT` real deduplica,
 * que el resolver filtra por empresa y que nada de credenciales queda en la
 * fila persistida.
 */
const real = process.env.ECF_POSTGRES_UAT === "true" ? describe : describe.skip;

const COMPANY_A = "77777777-7777-4777-8777-777777777777";
const COMPANY_B = "88888888-8888-4888-8888-888888888888";
const COMPANY_C = "99999999-9999-4999-8999-999999999999";
const RNC_A = "133306001";
const RNC_B = "130000002";
const RNC_DISABLED = "130000003";
const SECRET = "d".repeat(64);

const SIGNATURE = {
  strategy: "UNVERIFIED_PLAINTEXT_SECRET" as const,
  secret: SECRET,
};

function payload(overrides: Record<string, unknown> = {}) {
  const body = {
    postulacion_id: "post-int-0001",
    rnc: RNC_A,
    razon_social: "EMPRESA INTEGRACION SRL",
    correo: "fiscal@example.com",
    ambiente: "Test",
    estado_certificacion: "finalizado",
    credenciales: {
      api_key_produccion: "PROD-KEY-INTEGRACION",
      api_key_test: "TEST-KEY-INTEGRACION",
      api_secret: "SECRET-INTEGRACION",
    },
    credenciales_pendientes: false,
    disponibles_desde: "2026-11-01T22:50:12Z",
    ...overrides,
  };
  const rawBody = Buffer.from(JSON.stringify(body), "utf8");
  return {
    headers: { "x-dosa-signature": SECRET },
    rawBody,
    body,
  };
}

real("DosaWebhook — PostgreSQL real", () => {
  let prisma: PrismaClient;
  let service: DosaWebhookService;

  beforeAll(async () => {
    prisma = new PrismaClient();
    service = new DosaWebhookService(
      prisma,
      new PrismaDosaCompanyResolver(prisma as unknown as PrismaService),
      SIGNATURE,
    );

    for (const [id, slug] of [
      [COMPANY_A, "dosa-webhook-a"],
      [COMPANY_B, "dosa-webhook-b"],
      [COMPANY_C, "dosa-webhook-c"],
    ]) {
      await prisma.$executeRaw`
        INSERT INTO "companies" ("id","name","slug","updated_at")
        VALUES (${id}::uuid, ${slug}, ${slug}, NOW())
        ON CONFLICT ("id") DO NOTHING
      `;
    }
    for (const [companyId, rnc, enabled] of [
      [COMPANY_A, RNC_A, true],
      [COMPANY_B, RNC_B, true],
      [COMPANY_C, RNC_DISABLED, false],
    ] as const) {
      await prisma.$executeRaw`
        INSERT INTO "ecf_company_configurations" ("id","company_id","enabled")
        VALUES (gen_random_uuid(), ${companyId}::uuid, ${enabled})
        ON CONFLICT ("company_id") DO UPDATE SET "enabled" = ${enabled}
      `;
    }
  });

  beforeEach(async () => {
    await cleanup();
  });

  afterAll(async () => {
    await cleanup();
    await prisma.$executeRaw`
      DELETE FROM "ecf_company_configurations"
       WHERE "company_id" IN (${COMPANY_A}::uuid, ${COMPANY_B}::uuid, ${COMPANY_C}::uuid)
    `;
    await prisma.$executeRaw`
      DELETE FROM "companies"
       WHERE "id" IN (${COMPANY_A}::uuid, ${COMPANY_B}::uuid, ${COMPANY_C}::uuid)
    `;
    await prisma.$disconnect();
  });

  async function cleanup() {
    await prisma.$executeRaw`
      DELETE FROM "ecf_dosa_webhook_events"
       WHERE "company_id" IN (${COMPANY_A}::uuid, ${COMPANY_B}::uuid, ${COMPANY_C}::uuid)
    `;
    await prisma.$executeRaw`
      DELETE FROM "ecf_dosa_certification_sessions"
       WHERE "company_id" IN (${COMPANY_A}::uuid, ${COMPANY_B}::uuid, ${COMPANY_C}::uuid)
    `;
  }

  async function linkSession(companyId: string, rnc: string) {
    await prisma.$executeRaw`
      INSERT INTO "ecf_dosa_certification_sessions"
        ("id","company_id","rnc","attempt_no","active_key","status",
         "created_at","updated_at")
      VALUES
        (gen_random_uuid(), ${companyId}::uuid, ${rnc}, 1,
         ${`${companyId}:${rnc}`}, 'RUNNING', NOW(), NOW())
      ON CONFLICT ("company_id","rnc","attempt_no") DO NOTHING
    `;
  }

  async function eventRows(companyId: string) {
    return prisma.$queryRaw<Array<{ id: string; payload_summary: unknown }>>`
      SELECT "id","payload_summary"
        FROM "ecf_dosa_webhook_events"
       WHERE "company_id" = ${companyId}::uuid
       ORDER BY "received_at" ASC
    `;
  }

  it("sin vinculación previa el evento no entra (RNC desconocido)", async () => {
    const outcome = await service.handle(payload());
    expect(outcome).toMatchObject({ accepted: false, status: 404 });
    expect(await eventRows(COMPANY_A)).toHaveLength(0);
  });

  it("con vinculación, el evento se guarda en la empresa correcta", async () => {
    await linkSession(COMPANY_A, RNC_A);

    const outcome = await service.handle(payload());

    expect(outcome).toMatchObject({ accepted: true, duplicate: false });
    const rows = await eventRows(COMPANY_A);
    expect(rows).toHaveLength(1);
  });

  it("la doble entrega no duplica: una sola fila y segunda respuesta duplicate", async () => {
    await linkSession(COMPANY_A, RNC_A);

    const first = await service.handle(payload());
    const second = await service.handle(payload());

    expect(first).toMatchObject({ accepted: true, duplicate: false });
    expect(second).toMatchObject({ accepted: true, duplicate: true });
    expect(await eventRows(COMPANY_A)).toHaveLength(1);
  });

  it("empresa sin e-CF habilitado queda fuera (409) y no persiste", async () => {
    await linkSession(COMPANY_C, RNC_DISABLED);

    const outcome = await service.handle(payload({ rnc: RNC_DISABLED }));

    expect(outcome).toMatchObject({ accepted: false, status: 409 });
    expect(await eventRows(COMPANY_C)).toHaveLength(0);
  });

  it("dos empresas con RNC propios no se contaminan", async () => {
    await linkSession(COMPANY_A, RNC_A);
    await linkSession(COMPANY_B, RNC_B);

    await service.handle(payload());
    await service.handle(
      payload({ rnc: RNC_B, postulacion_id: "post-int-0002" }),
    );

    expect(await eventRows(COMPANY_A)).toHaveLength(1);
    expect(await eventRows(COMPANY_B)).toHaveLength(1);
  });

  it("ninguna credencial llega a la fila persistida", async () => {
    await linkSession(COMPANY_A, RNC_A);
    await service.handle(payload());

    const rows = await eventRows(COMPANY_A);
    const serialized = JSON.stringify(rows);
    expect(serialized).not.toContain("PROD-KEY-INTEGRACION");
    expect(serialized).not.toContain("TEST-KEY-INTEGRACION");
    expect(serialized).not.toContain("SECRET-INTEGRACION");
    expect(serialized).toContain("[REDACTED]");
  });

  it("el evento NO cambia el estado de la sesión de certificación", async () => {
    await linkSession(COMPANY_A, RNC_A);

    await service.handle(payload());

    const sessions = await prisma.$queryRaw<Array<{ status: string }>>`
      SELECT "status"::text AS "status"
        FROM "ecf_dosa_certification_sessions"
       WHERE "company_id" = ${COMPANY_A}::uuid
    `;
    expect(sessions).toHaveLength(1);
    expect(sessions[0].status).toBe("RUNNING");
  });

  it("un cambio real de estado sí es un evento nuevo", async () => {
    await linkSession(COMPANY_A, RNC_A);

    await service.handle(payload());
    await service.handle(payload({ estado_certificacion: "en_proceso" }));

    expect(await eventRows(COMPANY_A)).toHaveLength(2);
  });
});
