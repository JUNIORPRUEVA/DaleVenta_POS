import { PrismaClient } from "@prisma/client";
import { randomBytes } from "node:crypto";
import { DosaCertificationIntentController } from "./dosa-certification-intent.controller";
import {
  DosaCertificationIntentService,
  PrismaDosaRncOwnersReader,
} from "./dosa-certification-intent.service";
import { EcfDosaSessionService } from "./ecf-dosa-session.service";
import { EcfCanonicalIdentityService } from "../../dgii/certificate/ecf-canonical-identity.service";
import { PrismaDosaCompanyFiscalConfigReader } from "./dosa-company-fiscal-config";
import {
  DosaCredentialService,
  PrismaDosaCredentialStore,
} from "./dosa-credential.service";
import { DosaCredentialVault } from "./dosa-credential-vault.service";
import type { PrismaService } from "../../../prisma/prisma.service";
import type { TenantUser } from "../../../auth/tenant-context";
import type { Request } from "express";

/**
 * Preasociación por HTTP contra PostgreSQL REAL.
 *
 * Recorre el controlador completo (auditoría incluida) sobre datos reales:
 * `app_config` para la identidad fiscal y `ecf_dosa_certification_sessions` para
 * el intento. `ecf_company_configurations` solo se **lee** para informar del
 * estado de emisión: no es una compuerta de preparación.
 *
 * Demuestra lo que un doble no puede: que **antes** de abrir el asistente existe
 * una fila real que vincula la empresa con su RNC, que la preparación funciona
 * con la emisión desactivada —o sin configuración fiscal— y que no activa nada.
 */
const real = process.env.ECF_POSTGRES_UAT === "true" ? describe : describe.skip;

const MASTER = randomBytes(32).toString("base64");
// La base UAT puede contener una empresa sintética con el RNC de pruebas por
// defecto. Se permite elegir un RNC libre para que la prueba no dependa de que
// el entorno esté vacío, sin tocar datos existentes.
const RNC_SHARED = process.env.ECF_POSTGRES_TEST_RNC?.trim() || "133306001";
const RNC_OTHER = process.env.ECF_POSTGRES_TEST_RNC_OTHER?.trim() || "130000002";

const COMPANY_A = "31313131-0000-4000-8000-000000000031";
const COMPANY_B = "32323232-0000-4000-8000-000000000032";
const COMPANY_NO_RNC = "33333333-0000-4000-8000-000000000033";
const COMPANY_OTHER = "34343434-0000-4000-8000-000000000034";
const ACTOR = "35353535-0000-4000-8000-000000000035";

const ALL = [COMPANY_A, COMPANY_B, COMPANY_NO_RNC, COMPANY_OTHER];

real("Preasociación empresa-RNC — PostgreSQL real", () => {
  let prisma: PrismaClient;
  let controller: DosaCertificationIntentController;

  beforeAll(async () => {
    prisma = new PrismaClient();

    for (const [id, slug] of [
      [COMPANY_A, "intent-a"],
      [COMPANY_B, "intent-b"],
      [COMPANY_NO_RNC, "intent-c"],
      [COMPANY_OTHER, "intent-d"],
    ]) {
      await prisma.$executeRaw`
        INSERT INTO "companies" ("id","name","slug","updated_at")
        VALUES (${id}::uuid, ${slug}, ${slug}, NOW())
        ON CONFLICT ("id") DO NOTHING
      `;
      // Opt-in de e-CF (el administrador ya lo pidió).
      await prisma.$executeRaw`
        INSERT INTO "ecf_company_configurations" ("id","company_id","enabled","provider")
        VALUES (gen_random_uuid(), ${id}::uuid, true, 'DOSA')
        ON CONFLICT ("company_id") DO UPDATE SET "enabled" = true, "provider" = 'DOSA'
      `;
    }

    controller = new DosaCertificationIntentController(
      prisma as unknown as PrismaService,
      new DosaCertificationIntentService(
        new EcfCanonicalIdentityService(prisma as unknown as PrismaService),
        new EcfDosaSessionService(prisma),
        new PrismaDosaRncOwnersReader(prisma),
      ),
      new DosaCredentialService(
        new PrismaDosaCredentialStore(prisma),
        new DosaCredentialVault(MASTER),
      ),
      new PrismaDosaCompanyFiscalConfigReader(prisma),
    );
  });

  beforeEach(async () => {
    await cleanup();
    // Identidad fiscal real: RNC en app_config. La empresa C no tiene, y la B
    // solo lo recibe en la prueba de ambiguedad.
    await seedAppConfig(COMPANY_A, RNC_SHARED);
    await seedAppConfig(COMPANY_OTHER, RNC_OTHER);
  });

  afterAll(async () => {
    await cleanup();
    await prisma.$executeRaw`
      DELETE FROM "companies" WHERE "id" = ANY(${ALL}::uuid[])
    `;
    await prisma.$disconnect();
  });

  async function seedAppConfig(companyId: string, rnc: string) {
    await prisma.$executeRawUnsafe(
      `INSERT INTO "app_config" ("id","company_id","companyName","rnc","updatedAt")
       VALUES ($1, $2::uuid, 'EMPRESA PRUEBA', $3, NOW())`,
      `ac-${companyId}`,
      companyId,
      rnc,
    );
  }

  async function cleanup() {
    for (const table of [
      "ecf_dosa_company_credentials",
      "ecf_dosa_webhook_events",
      "ecf_dosa_certification_sessions",
      "ecf_audit_logs",
      "app_config",
    ]) {
      await prisma.$executeRawUnsafe(
        `DELETE FROM "${table}" WHERE "company_id" = ANY($1::uuid[])`,
        ALL,
      );
    }
  }

  function req(companyId: string): Request {
    return {
      user: { id: ACTOR, companyId } as TenantUser,
    } as unknown as Request;
  }

  async function sessionRows(companyId: string) {
    return prisma.$queryRaw<Array<{ id: string; rnc: string; status: string }>>`
      SELECT "id","rnc","status" FROM "ecf_dosa_certification_sessions"
       WHERE "company_id" = ${companyId}::uuid
    `;
  }

  it("registra el intento y la sesión existe en PostgreSQL antes del asistente", async () => {
    const response = await controller.register(req(COMPANY_A), {});

    expect(response).toMatchObject({
      ok: true,
      companyId: COMPANY_A,
      rnc: RNC_SHARED,
      created: true,
      fiscalAuthorizationGranted: false,
    });

    const rows = await sessionRows(COMPANY_A);
    expect(rows).toHaveLength(1);
    expect(rows[0].rnc).toBe(RNC_SHARED);
    expect(rows[0].id).toBe(response.sessionId);
  });

  it("es idempotente: repetir no crea un segundo intento", async () => {
    const first = await controller.register(req(COMPANY_A), {});
    const second = await controller.register(req(COMPANY_A), {});

    expect(first.created).toBe(true);
    expect(second.created).toBe(false);
    expect(second.sessionId).toBe(first.sessionId);
    expect(await sessionRows(COMPANY_A)).toHaveLength(1);
  });

  it("el endpoint de estado devuelve la sesión interna", async () => {
    await controller.register(req(COMPANY_A), {});
    const state = await controller.state(req(COMPANY_A));

    expect(state.canonicalRnc).toBe(RNC_SHARED);
    expect(state.canonicalSource).toBe("FISCAL_CONFIG");
    expect(state.session?.id).not.toBeNull();
    expect(state.canRegister).toBe(true);
    expect(state.fiscalAuthorizationGranted).toBe(false);
  });

  it("dos empresas con el mismo RNC: ninguna de las dos se asocia", async () => {
    // La empresa B declara el MISMO RNC que A. La ambiguedad se detecta por
    // configuración, no por orden de llegada: **ninguna** puede registrarse.
    await seedAppConfig(COMPANY_B, RNC_SHARED);

    await expect(controller.register(req(COMPANY_A), {})).rejects.toMatchObject({
      response: { message: "AMBIGUOUS_RNC" },
    });
    await expect(controller.register(req(COMPANY_B), {})).rejects.toMatchObject({
      response: { message: "AMBIGUOUS_RNC" },
    });

    expect(await sessionRows(COMPANY_A)).toHaveLength(0);
    expect(await sessionRows(COMPANY_B)).toHaveLength(0);
  });

  it("una empresa sin RNC fiscal verificado no registra nada", async () => {
    await expect(
      controller.register(req(COMPANY_NO_RNC), {}),
    ).rejects.toMatchObject({ response: { message: "COMPANY_RNC_NOT_VERIFIED" } });
    expect(await sessionRows(COMPANY_NO_RNC)).toHaveLength(0);
  });

  it("un RNC del cliente distinto del expediente se rechaza", async () => {
    await expect(
      controller.register(req(COMPANY_OTHER), { rnc: RNC_SHARED }),
    ).rejects.toMatchObject({
      response: { message: "RNC_DOES_NOT_MATCH_COMPANY_IDENTITY" },
    });
    expect(await sessionRows(COMPANY_OTHER)).toHaveLength(0);
  });

  it("empresas con RNC distintos conviven sin contaminarse", async () => {
    await controller.register(req(COMPANY_A), {});
    await controller.register(req(COMPANY_OTHER), {});

    expect((await sessionRows(COMPANY_A))[0].rnc).toBe(RNC_SHARED);
    expect((await sessionRows(COMPANY_OTHER))[0].rnc).toBe(RNC_OTHER);
  });

  it("deja auditoría con actor real y sin credenciales", async () => {
    await controller.register(req(COMPANY_A), {});

    const rows = await prisma.$queryRaw<
      Array<{ action: string; actor_user_id: string | null; target_type: string; metadata: unknown }>
    >`
      SELECT "action"::text AS "action", "actor_user_id", "target_type", "metadata"
        FROM "ecf_audit_logs"
       WHERE "company_id" = ${COMPANY_A}::uuid
    `;
    expect(rows).toHaveLength(1);
    expect(rows[0].action).toBe("ONBOARDING_STARTED");
    expect(rows[0].actor_user_id).toBe(ACTOR);
    expect(rows[0].target_type).toBe("DOSA_CERTIFICATION_INTENT");
    expect(JSON.stringify(rows[0].metadata)).not.toMatch(/[A-Za-z0-9+/_-]{40,}/);
  });

  it("la preparación NO activa nada: la configuración fiscal queda igual", async () => {
    // Se parte del caso realista: empresa preparando con el módulo de emisión
    // APAGADO. Antes esto bloqueaba; ahora debe preparar y no tocar nada.
    await prisma.$executeRaw`
      UPDATE "ecf_company_configurations"
         SET "enabled" = false, "production_enabled" = false,
             "certification_status" = 'NOT_STARTED', "environment" = 'SANDBOX'
       WHERE "company_id" = ${COMPANY_A}::uuid
    `;

    const response = await controller.register(req(COMPANY_A), {});
    expect(response.ok).toBe(true);
    expect(response.ecfEnabled).toBe(false);
    expect(response.fiscalAuthorizationGranted).toBe(false);

    const rows = await prisma.$queryRaw<
      Array<{ enabled: boolean; production_enabled: boolean; certification_status: string; environment: string }>
    >`
      SELECT "enabled","production_enabled","certification_status"::text AS "certification_status",
             "environment"::text AS "environment"
        FROM "ecf_company_configurations"
       WHERE "company_id" = ${COMPANY_A}::uuid
    `;
    // Nada cambió: preparar no es activar.
    expect(rows[0]).toEqual({
      enabled: false,
      production_enabled: false,
      certification_status: "NOT_STARTED",
      environment: "SANDBOX",
    });
    // Y no se creó ninguna credencial.
    const credentials = await prisma.$queryRaw<Array<{ n: number }>>`
      SELECT count(*)::int AS "n" FROM "ecf_dosa_company_credentials"
       WHERE "company_id" = ${COMPANY_A}::uuid
    `;
    expect(credentials[0].n).toBe(0);
    // La sesión de preparación SÍ existe: el estado distinto quedó registrado.
    expect(await sessionRows(COMPANY_A)).toHaveLength(1);
  });

  it("prepara una empresa que aún no tiene configuración fiscal, sin crearla", async () => {
    await prisma.$executeRaw`
      DELETE FROM "ecf_company_configurations" WHERE "company_id" = ${COMPANY_OTHER}::uuid
    `;
    try {
      const response = await controller.register(req(COMPANY_OTHER), {});
      expect(response.ok).toBe(true);
      // El proveedor del intento es DOSA; no se afirma nada de la configuración.
      expect(response.provider).toBe("DOSA");
      expect(response.ecfEnabled).toBe(false);

      const configs = await prisma.$queryRaw<Array<{ n: number }>>`
        SELECT count(*)::int AS "n" FROM "ecf_company_configurations"
         WHERE "company_id" = ${COMPANY_OTHER}::uuid
      `;
      // No se creó una configuración fiscal "por la cara".
      expect(configs[0].n).toBe(0);
      expect(await sessionRows(COMPANY_OTHER)).toHaveLength(1);

      const state = await controller.state(req(COMPANY_OTHER));
      expect(state.canRegister).toBe(true);
      expect(state.blockingReasons).toEqual([]);
      expect(state.ecfEnabled).toBe(false);
    } finally {
      await prisma.$executeRaw`
        INSERT INTO "ecf_company_configurations" ("id","company_id","enabled","provider")
        VALUES (gen_random_uuid(), ${COMPANY_OTHER}::uuid, true, 'DOSA')
        ON CONFLICT ("company_id") DO UPDATE SET "enabled" = true
      `;
    }
  });
});
