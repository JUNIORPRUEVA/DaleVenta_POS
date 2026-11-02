import { PrismaClient } from "@prisma/client";
import { randomBytes } from "node:crypto";
import {
  DosaCredentialService,
  PrismaDosaCredentialStore,
} from "./dosa-credential.service";
import { DosaCredentialVault } from "./dosa-credential-vault.service";
import { PrismaDosaAuthorizationReader } from "./dosa-activation-authority.service";
import { DosaActivationService } from "./dosa-activation.service";

/**
 * Fase F contra PostgreSQL REAL y desechable.
 *
 * Cubre dos cosas que ningún doble puede demostrar:
 *
 * 1. Que `DOSA` ya es un valor válido de `ecf_provider`, que **ALANUBE sigue
 *    siendo el valor por defecto** y que ninguna fila existente cambia.
 * 2. Que la activación fiscal se decide leyendo evidencia **persistida**, no un
 *    booleano del llamador: sin sesión, sin evento autenticado, sin habilitación
 *    DGII oficial y sin autorización auditada, no se activa.
 */
const real = process.env.ECF_POSTGRES_UAT === "true" ? describe : describe.skip;

const MASTER = randomBytes(32).toString("base64");
const COMPANY = "ffffffff-0000-4000-8000-00000000000f";
const COMPANY_OTHER = "f0f0f0f0-0000-4000-8000-0000000000f0";
const RNC = "133306001";
const ACTOR = "a0a0a0a0-0000-4000-8000-0000000000a0";

real("Fase F — DOSA en PostgreSQL real", () => {
  let prisma: PrismaClient;
  let credentials: DosaCredentialService;
  let activation: DosaActivationService;

  beforeAll(async () => {
    prisma = new PrismaClient();
    credentials = new DosaCredentialService(
      new PrismaDosaCredentialStore(prisma),
      new DosaCredentialVault(MASTER),
    );
    activation = new DosaActivationService(
      new PrismaDosaAuthorizationReader(prisma),
      credentials,
    );
    for (const [id, slug] of [
      [COMPANY, "fasef-ecf"],
      [COMPANY_OTHER, "fasef-tradicional"],
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
      DELETE FROM "companies" WHERE "id" IN (${COMPANY}::uuid, ${COMPANY_OTHER}::uuid)
    `;
    await prisma.$disconnect();
  });

  async function cleanup() {
    for (const table of [
      "ecf_dosa_company_credentials",
      "ecf_dosa_webhook_events",
      "ecf_dosa_certification_sessions",
      "ecf_dgii_habilitations",
      "ecf_audit_logs",
      "ecf_company_configurations",
    ]) {
      await prisma.$executeRawUnsafe(
        `DELETE FROM "${table}" WHERE "company_id" = ANY($1::uuid[])`,
        [COMPANY, COMPANY_OTHER],
      );
    }
  }

  async function providerOf(companyId: string): Promise<string | null> {
    const rows = await prisma.$queryRaw<Array<{ provider: string }>>`
      SELECT "provider"::text AS "provider"
        FROM "ecf_company_configurations" WHERE "company_id" = ${companyId}::uuid
    `;
    return rows[0]?.provider ?? null;
  }

  describe("enum ecf_provider", () => {
    it("el valor por defecto sigue siendo ALANUBE", async () => {
      await prisma.$executeRaw`
        INSERT INTO "ecf_company_configurations" ("id","company_id")
        VALUES (gen_random_uuid(), ${COMPANY_OTHER}::uuid)
      `;
      expect(await providerOf(COMPANY_OTHER)).toBe("ALANUBE");
    });

    it("una empresa puede seleccionar DOSA y volver a abrirla sin errores", async () => {
      await prisma.$executeRaw`
        INSERT INTO "ecf_company_configurations" ("id","company_id","provider")
        VALUES (gen_random_uuid(), ${COMPANY}::uuid, 'DOSA')
      `;
      expect(await providerOf(COMPANY)).toBe("DOSA");

      // Segunda lectura: el valor persiste y se puede volver a escribir.
      await prisma.$executeRaw`
        UPDATE "ecf_company_configurations" SET "provider" = 'DOSA'
         WHERE "company_id" = ${COMPANY}::uuid
      `;
      expect(await providerOf(COMPANY)).toBe("DOSA");
    });

    it("una empresa tradicional conserva ALANUBE aunque exista DOSA", async () => {
      await prisma.$executeRaw`
        INSERT INTO "ecf_company_configurations" ("id","company_id","provider")
        VALUES (gen_random_uuid(), ${COMPANY_OTHER}::uuid, 'ALANUBE')
      `;
      await prisma.$executeRaw`
        INSERT INTO "ecf_company_configurations" ("id","company_id","provider")
        VALUES (gen_random_uuid(), ${COMPANY}::uuid, 'DOSA')
      `;
      expect(await providerOf(COMPANY_OTHER)).toBe("ALANUBE");
      expect(await providerOf(COMPANY)).toBe("DOSA");
    });

    it("seleccionar DOSA no activa e-CF por sí solo", async () => {
      await prisma.$executeRaw`
        INSERT INTO "ecf_company_configurations" ("id","company_id","provider")
        VALUES (gen_random_uuid(), ${COMPANY}::uuid, 'DOSA')
      `;
      const rows = await prisma.$queryRaw<Array<{ enabled: boolean }>>`
        SELECT "enabled" FROM "ecf_company_configurations"
         WHERE "company_id" = ${COMPANY}::uuid
      `;
      expect(rows[0].enabled).toBe(false);
    });
  });

  describe("autoridad de activación (evidencia persistida)", () => {
    async function seedSession() {
      await prisma.$executeRaw`
        INSERT INTO "ecf_dosa_certification_sessions"
          ("id","company_id","rnc","attempt_no","active_key","status","created_at","updated_at")
        VALUES (gen_random_uuid(), ${COMPANY}::uuid, ${RNC}, 1,
                ${`${COMPANY}:${RNC}`}, 'RUNNING', NOW(), NOW())
      `;
    }

    async function seedAuthenticatedEvent() {
      await prisma.$executeRaw`
        INSERT INTO "ecf_dosa_webhook_events"
          ("id","company_id","dedupe_key","event_type","postulacion_id",
           "estado_certificacion","raw_body_sha256","payload_summary",
           "signature_status")
        VALUES (gen_random_uuid(), ${COMPANY}::uuid, 'k-fasef', 'empresa.conectada',
                'post-fasef', 'finalizado', repeat('a', 64), '{}'::jsonb,
                'UNVERIFIED_PLAINTEXT_SECRET')
      `;
    }

    async function seedDgii(
      state: string,
      source: string,
    ) {
      await prisma.$executeRawUnsafe(
        `INSERT INTO "ecf_dgii_habilitations"
           ("id","company_id","state","authorization_source","created_at","updated_at")
         VALUES (gen_random_uuid(), $1::uuid, $2::text::ecf_dgii_habilitation_state,
                 $3::text::ecf_dgii_verification_source, NOW(), NOW())`,
        COMPANY,
        state,
        source,
      );
    }

    async function seedAudit(action: string, withActor = true) {
      await prisma.$executeRawUnsafe(
        `INSERT INTO "ecf_audit_logs" ("id","company_id","actor_user_id","action")
         VALUES (gen_random_uuid(), $1::uuid, $2::uuid, $3::text::ecf_audit_action)`,
        COMPANY,
        withActor ? ACTOR : null,
        action,
      );
    }

    it("sin nada persistido no hay evidencia", async () => {
      const evidence = await new PrismaDosaAuthorizationReader(prisma).read({
        companyId: COMPANY,
        rnc: RNC,
      });
      expect(evidence.identityLinked).toBe(false);
      expect(evidence.providerConfirmed).toBe(false);
      expect(evidence.dgiiApproved).toBe(false);
      expect(evidence.administrativeAuthorized).toBe(false);
    });

    it("una declaración manual del operador NO equivale a aprobación DGII", async () => {
      await seedSession();
      await seedDgii("APPROVED", "MANUAL_OPERATOR_DECLARATION");
      const evidence = await new PrismaDosaAuthorizationReader(prisma).read({
        companyId: COMPANY,
        rnc: RNC,
      });
      expect(evidence.dgiiApproved).toBe(false);
    });

    it("el registro oficial de la DGII sí cuenta", async () => {
      await seedSession();
      await seedDgii("APPROVED", "DGII_OFFICIAL_RECORD");
      const evidence = await new PrismaDosaAuthorizationReader(prisma).read({
        companyId: COMPANY,
        rnc: RNC,
      });
      expect(evidence.dgiiApproved).toBe(true);
    });

    it("una autorización revocada invalida las anteriores", async () => {
      await seedAudit("DGII_AUTHORIZATION_RECORDED");
      await seedAudit("DGII_AUTHORIZATION_REVOKED");
      const evidence = await new PrismaDosaAuthorizationReader(prisma).read({
        companyId: COMPANY,
        rnc: RNC,
      });
      expect(evidence.administrativeAuthorized).toBe(false);
    });

    it("una autorización sin actor real no cuenta", async () => {
      await seedAudit("DGII_AUTHORIZATION_RECORDED", false);
      const evidence = await new PrismaDosaAuthorizationReader(prisma).read({
        companyId: COMPANY,
        rnc: RNC,
      });
      expect(evidence.administrativeAuthorized).toBe(false);
    });

    it("con toda la evidencia persistida se activa y la credencial pasa a ACTIVE", async () => {
      await prisma.$executeRaw`
        INSERT INTO "ecf_company_configurations" ("id","company_id","enabled","provider")
        VALUES (gen_random_uuid(), ${COMPANY}::uuid, true, 'DOSA')
      `;
      await seedSession();
      await seedAuthenticatedEvent();
      await seedDgii("APPROVED", "DGII_OFFICIAL_RECORD");
      await seedAudit("DGII_AUTHORIZATION_RECORDED");

      await credentials.ingestFromProvider({
        companyId: COMPANY,
        rnc: RNC,
        environment: "test",
        bundle: { apiKeyTest: "CLAVE-FASE-F" },
        signatureAuthenticated: true,
      });

      const result = await activation.activate({
        companyId: COMPANY,
        rnc: RNC,
        environment: "test",
      });
      expect(result.ok).toBe(true);

      const inspection = await credentials.inspect({
        companyId: COMPANY,
        rnc: RNC,
        environment: "test",
      });
      expect(inspection?.status).toBe("ACTIVE");
    });

    it("sin autorización administrativa no se activa aunque lo demás esté", async () => {
      await prisma.$executeRaw`
        INSERT INTO "ecf_company_configurations" ("id","company_id","enabled","provider")
        VALUES (gen_random_uuid(), ${COMPANY}::uuid, true, 'DOSA')
      `;
      await seedSession();
      await seedAuthenticatedEvent();
      await seedDgii("APPROVED", "DGII_OFFICIAL_RECORD");

      await credentials.ingestFromProvider({
        companyId: COMPANY,
        rnc: RNC,
        environment: "test",
        bundle: { apiKeyTest: "CLAVE-FASE-F" },
        signatureAuthenticated: true,
      });

      const result = await activation.activate({
        companyId: COMPANY,
        rnc: RNC,
        environment: "test",
      });
      expect(result.ok).toBe(false);
      if (!result.ok) {
        expect(result.blockingReasons).toContain(
          "ECF_DOSA_ACTIVATION_ADMIN_NOT_AUTHORIZED",
        );
      }

      const inspection = await credentials.inspect({
        companyId: COMPANY,
        rnc: RNC,
        environment: "test",
      });
      expect(inspection?.status).toBe("PENDING_CONFIRMATION");
    });

    it("un evento con firma BLOCKED no confirma al proveedor", async () => {
      await seedSession();
      await prisma.$executeRaw`
        INSERT INTO "ecf_dosa_webhook_events"
          ("id","company_id","dedupe_key","event_type","estado_certificacion",
           "raw_body_sha256","payload_summary","signature_status")
        VALUES (gen_random_uuid(), ${COMPANY}::uuid, 'k-blocked', 'empresa.conectada',
                'finalizado', repeat('b', 64), '{}'::jsonb, 'BLOCKED')
      `;
      const evidence = await new PrismaDosaAuthorizationReader(prisma).read({
        companyId: COMPANY,
        rnc: RNC,
      });
      expect(evidence.providerConfirmed).toBe(false);
    });
  });
});
