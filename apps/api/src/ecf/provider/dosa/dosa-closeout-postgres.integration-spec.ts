import { PrismaClient } from "@prisma/client";
import { randomBytes } from "node:crypto";
import { EcfDosaSessionService } from "./ecf-dosa-session.service";
import {
  DosaCertificationIntentService,
  PrismaDosaRncOwnersReader,
} from "./dosa-certification-intent.service";
import type { EcfCanonicalIdentityService } from "../../dgii/certificate/ecf-canonical-identity.service";
import {
  COMPLETE_STATE,
  DosaWebhookService,
  PENDING_STATE,
  type DosaCompanyResolver,
} from "./dosa-webhook.service";
import type { DosaSignatureConfig } from "./dosa-webhook-signature.policy";
import {
  DosaCredentialService,
  PrismaDosaCredentialStore,
} from "./dosa-credential.service";
import { DosaCredentialVault } from "./dosa-credential-vault.service";

/**
 * Cierre de hallazgos contra PostgreSQL REAL.
 *
 * 1. Preasociación empresa↔RNC sobre la tabla de sesiones existente, con bloqueo
 *    cuando dos empresas comparten el RNC.
 * 2. Webhook recuperable: el evento nace en PENDING_CREDENTIALS, un fallo real de
 *    la bóveda responde 5xx y el reenvío lo reanuda sin duplicar la fila.
 */
const real = process.env.ECF_POSTGRES_UAT === "true" ? describe : describe.skip;

const MASTER = randomBytes(32).toString("base64");
const SECRET = "9".repeat(64);
const COMPANY_A = "17171717-0000-4000-8000-000000000017";
const COMPANY_B = "18181818-0000-4000-8000-000000000018";
const RNC_SHARED = "133306001";

const SIGNATURE: DosaSignatureConfig = {
  strategy: "UNVERIFIED_PLAINTEXT_SECRET",
  secret: SECRET,
};

real("Cierre de hallazgos — PostgreSQL real", () => {
  let prisma: PrismaClient;

  beforeAll(async () => {
    prisma = new PrismaClient();
    for (const [id, slug] of [
      [COMPANY_A, "cierre-a"],
      [COMPANY_B, "cierre-b"],
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
    for (const table of [
      "ecf_dosa_company_credentials",
      "ecf_dosa_webhook_events",
      "ecf_dosa_certification_sessions",
      "ecf_company_configurations",
    ]) {
      await prisma.$executeRawUnsafe(
        `DELETE FROM "${table}" WHERE "company_id" = ANY($1::uuid[])`,
        [COMPANY_A, COMPANY_B],
      );
    }
  }

  function identityOf(taxId: string | null): EcfCanonicalIdentityService {
    return {
      async resolve() {
        return {
          taxId,
          legalName: null,
          representativeName: null,
          representativeId: null,
          source: taxId ? "FISCAL_CONFIG" : "NONE",
        };
      },
    } as unknown as EcfCanonicalIdentityService;
  }

  function intentFor(taxId: string | null) {
    return new DosaCertificationIntentService(
      identityOf(taxId),
      new EcfDosaSessionService(prisma),
      new PrismaDosaRncOwnersReader(prisma),
    );
  }

  describe("preasociación empresa–RNC", () => {
    it("registra la sesión con el RNC del servidor y el webhook la encuentra", async () => {
      const intent = intentFor(RNC_SHARED);
      const registered = await intent.register({ companyId: COMPANY_A });
      expect(registered.ok).toBe(true);

      // La sesión existe de verdad en la tabla existente.
      const sessions = await prisma.$queryRaw<Array<{ rnc: string }>>`
        SELECT "rnc" FROM "ecf_dosa_certification_sessions"
         WHERE "company_id" = ${COMPANY_A}::uuid
      `;
      expect(sessions).toHaveLength(1);
      expect(sessions[0].rnc).toBe(RNC_SHARED);

      await prisma.$executeRaw`
        INSERT INTO "ecf_company_configurations" ("id","company_id","enabled","provider")
        VALUES (gen_random_uuid(), ${COMPANY_A}::uuid, true, 'DOSA')
      `;

      const { PrismaDosaCompanyResolver } = await import(
        "./dosa-company-resolver.service"
      );
      const resolved = await new PrismaDosaCompanyResolver(prisma).resolveByRnc(
        RNC_SHARED,
      );
      // `portalEligible` es ahora parte del contrato: sin autorización registrada
      // en `ecf_portal_enrollments` (ni lista heredada) es `false`.
      expect(resolved).toEqual({
        companyId: COMPANY_A,
        ecfEnabled: true,
        portalEligible: false,
      });
    });

    it("si dos empresas comparten el RNC, la segunda queda bloqueada", async () => {
      const first = await intentFor(RNC_SHARED).register({ companyId: COMPANY_A });
      expect(first.ok).toBe(true);

      const second = await intentFor(RNC_SHARED).register({ companyId: COMPANY_B });
      expect(second).toMatchObject({ ok: false, reason: "AMBIGUOUS_RNC" });

      const rows = await prisma.$queryRaw<Array<{ n: number }>>`
        SELECT count(*)::int AS "n" FROM "ecf_dosa_certification_sessions"
         WHERE "company_id" = ${COMPANY_B}::uuid
      `;
      expect(rows[0].n).toBe(0);
    });

    it("sin RNC verificado no se crea sesión", async () => {
      const result = await intentFor(null).register({ companyId: COMPANY_A });
      expect(result).toMatchObject({ ok: false, reason: "COMPANY_RNC_NOT_VERIFIED" });
      const rows = await prisma.$queryRaw<Array<{ n: number }>>`
        SELECT count(*)::int AS "n" FROM "ecf_dosa_certification_sessions"
         WHERE "company_id" = ${COMPANY_A}::uuid
      `;
      expect(rows[0].n).toBe(0);
    });
  });

  describe("webhook recuperable", () => {
    function payload() {
      const body = {
        postulacion_id: "post-cierre-01",
        rnc: RNC_SHARED,
        razon_social: "EMPRESA CIERRE SRL",
        correo: "fiscal@example.com",
        ambiente: "Test",
        estado_certificacion: "finalizado",
        credenciales: { api_key_test: "CLAVE-TEST-CIERRE" },
        credenciales_pendientes: false,
        disponibles_desde: "2026-11-03T10:00:00Z",
      };
      return {
        headers: { "x-dosa-signature": SECRET },
        rawBody: Buffer.from(JSON.stringify(body), "utf8"),
        body,
      };
    }

    function resolver(): DosaCompanyResolver {
      return {
        async resolveByRnc() {
          return { companyId: COMPANY_A, ecfEnabled: true };
        },
      };
    }

    async function seedCompany() {
      await prisma.$executeRaw`
        INSERT INTO "ecf_company_configurations" ("id","company_id","enabled","provider")
        VALUES (gen_random_uuid(), ${COMPANY_A}::uuid, true, 'DOSA')
      `;
    }

    async function eventRow() {
      const rows = await prisma.$queryRaw<
        Array<{ processing_state: string; credentials_stored_at: Date | null }>
      >`
        SELECT "processing_state", "credentials_stored_at"
          FROM "ecf_dosa_webhook_events"
         WHERE "company_id" = ${COMPANY_A}::uuid
      `;
      return rows;
    }

    it("un fallo de la bóveda deja el evento reanudable y el reenvío lo completa", async () => {
      await seedCompany();

      // Bóveda sin clave maestra: no puede sellar nada.
      const brokenVault = new DosaCredentialService(
        new PrismaDosaCredentialStore(prisma),
        new DosaCredentialVault(null),
      );
      const failing = new DosaWebhookService(
        prisma,
        resolver(),
        SIGNATURE,
        brokenVault,
      );

      const first = await failing.handle(payload());
      expect(first).toMatchObject({
        accepted: false,
        status: 500,
        code: "ECF_DOSA_WEBHOOK_CREDENTIALS_FAILED",
      });

      const pending = await eventRow();
      expect(pending).toHaveLength(1);
      expect(pending[0].processing_state).toBe(PENDING_STATE);
      expect(pending[0].credentials_stored_at).toBeNull();

      // Segunda entrega con bóveda sana: reanuda, no duplica.
      const healthyVault = new DosaCredentialService(
        new PrismaDosaCredentialStore(prisma),
        new DosaCredentialVault(MASTER),
      );
      const healthy = new DosaWebhookService(
        prisma,
        resolver(),
        SIGNATURE,
        healthyVault,
      );

      const second = await healthy.handle(payload());
      expect(second).toMatchObject({
        accepted: true,
        status: 200,
        duplicate: false,
        code: "ECF_DOSA_WEBHOOK_RESUMED",
      });

      const complete = await eventRow();
      expect(complete).toHaveLength(1);
      expect(complete[0].processing_state).toBe(COMPLETE_STATE);
      expect(complete[0].credentials_stored_at).not.toBeNull();

      // La credencial quedó cifrada y pendiente de confirmación.
      const credential = await healthyVault.inspect({
        companyId: COMPANY_A,
        rnc: RNC_SHARED,
        environment: "test",
      });
      expect(credential?.status).toBe("PENDING_CONFIRMATION");
    });

    it("una tercera entrega ya es duplicado", async () => {
      await seedCompany();
      const healthy = new DosaWebhookService(
        prisma,
        resolver(),
        SIGNATURE,
        new DosaCredentialService(
          new PrismaDosaCredentialStore(prisma),
          new DosaCredentialVault(MASTER),
        ),
      );

      await healthy.handle(payload());
      const again = await healthy.handle(payload());

      expect(again).toMatchObject({
        duplicate: true,
        code: "ECF_DOSA_WEBHOOK_DUPLICATE",
      });
      expect(await eventRow()).toHaveLength(1);
    });

    it("el evento no activa facturación electrónica", async () => {
      await seedCompany();
      const healthy = new DosaWebhookService(
        prisma,
        resolver(),
        SIGNATURE,
        new DosaCredentialService(
          new PrismaDosaCredentialStore(prisma),
          new DosaCredentialVault(MASTER),
        ),
      );
      await healthy.handle(payload());

      const rows = await prisma.$queryRaw<
        Array<{ enabled: boolean; production_enabled: boolean }>
      >`
        SELECT "enabled", "production_enabled"
          FROM "ecf_company_configurations"
         WHERE "company_id" = ${COMPANY_A}::uuid
      `;
      expect(rows[0]).toEqual({ enabled: true, production_enabled: false });
    });
  });
});
