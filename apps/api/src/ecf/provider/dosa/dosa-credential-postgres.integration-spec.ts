import { PrismaClient } from "@prisma/client";
import { randomBytes } from "node:crypto";
import {
  DosaCredentialService,
  PrismaDosaCredentialStore,
} from "./dosa-credential.service";
import { DosaCredentialVault } from "./dosa-credential-vault.service";

/**
 * Credenciales fiscales contra PostgreSQL REAL.
 *
 * Solo con una base desechable declarada explícitamente:
 *
 *   $env:ECF_POSTGRES_UAT = "true"
 *   $env:DATABASE_URL = "postgresql://.../base_desechable"
 *
 * Comprueba lo que un doble no puede: que el criptograma se guarda tal cual, que
 * la clave única impide que un RNC herede credenciales de otra empresa y que
 * nada en claro llega a la fila.
 */
const real = process.env.ECF_POSTGRES_UAT === "true" ? describe : describe.skip;

const COMPANY_A = "cccccccc-0000-4000-8000-00000000000c";
const COMPANY_B = "dddddddd-0000-4000-8000-00000000000d";
const RNC_A = "133306001";
const RNC_B = "130000002";
const MASTER = randomBytes(32).toString("base64");

real("Credenciales DOSA — PostgreSQL real", () => {
  let prisma: PrismaClient;
  let service: DosaCredentialService;

  beforeAll(async () => {
    prisma = new PrismaClient();
    service = new DosaCredentialService(
      new PrismaDosaCredentialStore(prisma),
      new DosaCredentialVault(MASTER),
    );
    for (const [id, slug] of [
      [COMPANY_A, "dosa-cred-a"],
      [COMPANY_B, "dosa-cred-b"],
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
      DELETE FROM "ecf_dosa_company_credentials"
       WHERE "company_id" IN (${COMPANY_A}::uuid, ${COMPANY_B}::uuid)
    `;
  }

  async function rawRows(companyId: string) {
    return prisma.$queryRaw<Array<{ ciphertext: string; present: unknown }>>`
      SELECT "ciphertext","present"
        FROM "ecf_dosa_company_credentials"
       WHERE "company_id" = ${companyId}::uuid
    `;
  }

  it("guarda la credencial cifrada y la recupera con el contexto correcto", async () => {
    await service.ingestFromProvider({
      companyId: COMPANY_A,
      rnc: RNC_A,
      environment: "test",
      bundle: { apiKeyTest: "TEST-SECRETA-PG" },
      signatureAuthenticated: true,
    });

    const opened = await service.openForEmission({
      companyId: COMPANY_A,
      rnc: RNC_A,
      environment: "test",
      authorized: true,
    });
    expect(opened.apiKeyTest).toBe("TEST-SECRETA-PG");
  });

  it("la fila no contiene el valor en claro", async () => {
    await service.ingestFromProvider({
      companyId: COMPANY_A,
      rnc: RNC_A,
      environment: "test",
      bundle: { apiKeyTest: "TEST-SECRETA-PG" },
      signatureAuthenticated: true,
    });

    const rows = await rawRows(COMPANY_A);
    expect(rows).toHaveLength(1);
    expect(JSON.stringify(rows)).not.toContain("TEST-SECRETA-PG");
    expect(JSON.stringify(rows)).toContain("ciphertext");
  });

  it("el RNC queda normalizado y la clave única evita duplicados", async () => {
    for (let i = 0; i < 3; i += 1) {
      await service.ingestFromProvider({
        companyId: COMPANY_A,
        rnc: "133-306-001",
        environment: "test",
        bundle: { apiKeyTest: `CLAVE-${i}` },
        signatureAuthenticated: true,
      });
    }
    const rows = await rawRows(COMPANY_A);
    expect(rows).toHaveLength(1);
  });

  it("dos empresas con el mismo RNC no se pisan", async () => {
    await service.ingestFromProvider({
      companyId: COMPANY_A,
      rnc: RNC_A,
      environment: "test",
      bundle: { apiKeyTest: "DE-A" },
      signatureAuthenticated: true,
    });
    await service.ingestFromProvider({
      companyId: COMPANY_B,
      rnc: RNC_A,
      environment: "test",
      bundle: { apiKeyTest: "DE-B" },
      signatureAuthenticated: true,
    });

    const a = await service.openForEmission({
      companyId: COMPANY_A,
      rnc: RNC_A,
      environment: "test",
      authorized: true,
    });
    const b = await service.openForEmission({
      companyId: COMPANY_B,
      rnc: RNC_A,
      environment: "test",
      authorized: true,
    });
    expect(a.apiKeyTest).toBe("DE-A");
    expect(b.apiKeyTest).toBe("DE-B");
  });

  it("un criptograma de otra empresa no se puede abrir", async () => {
    await service.ingestFromProvider({
      companyId: COMPANY_B,
      rnc: RNC_B,
      environment: "test",
      bundle: { apiKeyTest: "SOLO-B" },
      signatureAuthenticated: true,
    });

    await expect(
      service.openForEmission({
        companyId: COMPANY_A,
        rnc: RNC_B,
        environment: "test",
        authorized: true,
      }),
    ).rejects.toThrow();
  });

  it("el estado avanza solo con la evidencia persistida completa", async () => {
    await service.ingestFromProvider({
      companyId: COMPANY_A,
      rnc: RNC_A,
      environment: "test",
      bundle: { apiKeyTest: "X" },
      signatureAuthenticated: true,
    });

    const blocked = await service.promote({
      companyId: COMPANY_A,
      rnc: RNC_A,
      environment: "test",
      to: "ACTIVE",
      evidence: {
        identityLinked: true,
        providerConfirmed: true,
        dgiiApproved: false,
        administrativeAuthorized: true,
        details: {
          linkedSessions: 1,
          authenticatedProviderEvents: 1,
          dgiiState: "IN_CERTIFICATION",
          dgiiSource: "MANUAL_OPERATOR_DECLARATION",
          authorizationsRecorded: 1,
          authorizationsRevoked: 0,
        },
      },
    });
    expect(blocked.ok).toBe(false);

    const activated = await service.promote({
      companyId: COMPANY_A,
      rnc: RNC_A,
      environment: "test",
      to: "ACTIVE",
      evidence: {
        identityLinked: true,
        providerConfirmed: true,
        dgiiApproved: true,
        administrativeAuthorized: true,
        details: {
          linkedSessions: 1,
          authenticatedProviderEvents: 1,
          dgiiState: "APPROVED",
          dgiiSource: "DGII_OFFICIAL_RECORD",
          authorizationsRecorded: 1,
          authorizationsRevoked: 0,
        },
      },
    });
    expect(activated).toEqual({ ok: true, status: "ACTIVE" });

    const inspection = await service.inspect({
      companyId: COMPANY_A,
      rnc: RNC_A,
      environment: "test",
    });
    expect(inspection?.status).toBe("ACTIVE");
  });
});
