import { randomUUID } from "node:crypto";
import { Role } from "@prisma/client";
import { PrismaService } from "../../prisma/prisma.service";
import { EcfService } from "../ecf.service";
import { EcfSecretReferenceService } from "../ecf-secret-reference.service";
import { isEcfEphemeralTestTarget } from "../ecf-local-target";
import { EcfDocumentQueryService } from "./ecf-document-query.service";
import { TaxService } from "../../tax/tax.service";
import { TaxCalculationService } from "../../tax/tax-calculation.service";

const local = process.env.ECF_POSTGRES_UAT === "true" ? describe : describe.skip;

local("company activation and POS readiness on isolated PostgreSQL", () => {
  let prisma: PrismaService;
  const companyId = randomUUID();
  const otherId = randomUUID();
  const user = { id: randomUUID(), companyId, role: Role.ADMIN };
  const previousEmissionFlag = process.env.DOSA_EMISSION_ENABLED;

  beforeAll(async () => {
    if (!isEcfEphemeralTestTarget() || process.env.ALANUBE_ENABLE_REAL_CALLS !== "false" ||
        process.env.ECF_EMISSION_ENABLED !== "false") throw Error("EPHEMERAL_TEST_REQUIRED");
    prisma = new PrismaService();
    await prisma.$connect();
    await prisma.company.createMany({ data: [companyId, otherId].map((id) => ({
      id, name: "Synthetic activation test", slug: `ecf-activation-${id}`,
    })) });
    process.env.DOSA_EMISSION_ENABLED = "true";
    await prisma.appConfig.create({ data: { id: randomUUID(), companyId, companyName: "Synthetic issuer", rnc: "101000001" } });
    await prisma.ecfDosaCompanyCredential.create({ data: { companyId, rnc: "101000001", environment: "test", status: "ACTIVE", source: "WEBHOOK", keyVersion: 1,
      ciphertext: "synthetic-never-opened", iv: "synthetic", authTag: "synthetic", fingerprint: "a".repeat(64), present: { apiKeyTest: true } } });
  });

  afterAll(async () => {
    if (!prisma) return;
    try {
      await prisma.company.deleteMany({ where: { id: { in: [companyId, otherId] }, slug: { startsWith: "ecf-activation-" } } });
    } finally {
      if (previousEmissionFlag === undefined) delete process.env.DOSA_EMISSION_ENABLED;
      else process.env.DOSA_EMISSION_ENABLED = previousEmissionFlag;
      await prisma.$disconnect();
    }
  });

  it("activates taxes, waits for readiness, and never borrows another tenant's range", async () => {
    const service = new EcfService(prisma, new EcfSecretReferenceService(), new TaxService(prisma, new TaxCalculationService()));
    const query = new EcfDocumentQueryService(prisma);
    await service.getConfig(user);
    await expect(service.updateConfig({ ...user, id: "invalid-uuid" }, { enabled: true })).rejects.toThrow();
    expect((await prisma.company.findUniqueOrThrow({ where: { id: companyId } })).taxEnabled).toBe(false);
    expect(await prisma.tax.count({ where: { companyId } })).toBe(0);
    await service.updateConfig(user, { enabled: true });
    const company = await prisma.company.findUniqueOrThrow({ where: { id: companyId } });
    expect(company.taxEnabled).toBe(true);
    expect(Number(company.defaultTaxRate)).toBe(0.18);
    expect(company.defaultTaxId).not.toBeNull();
    expect(await prisma.tax.findFirst({ where: { id: company.defaultTaxId!, companyId, isActive: true } })).not.toBeNull();
    expect((await query.capabilities(user)).posReady).toBe(false);
    await prisma.ecfCompanyConfiguration.update({
      where: { companyId }, data: { provider: "DOSA", certificationStatus: "AUTHORIZED_SANDBOX" },
    });
    await prisma.ecfSequence.create({ data: {
      environment: "SANDBOX",
      companyId: otherId, documentType: "E32", prefix: "E32",
      startNumber: 1, nextNumber: 1, endNumber: 10,
    } });
    expect((await query.capabilities(user)).posReady).toBe(false);
    const sequence = await prisma.ecfSequence.create({ data: {
      environment: "SANDBOX",
      companyId, documentType: "E32", prefix: "E32",
      startNumber: 1, nextNumber: 1, endNumber: 10,
    } });
    expect(await query.capabilities(user)).toMatchObject({ posReady: true, posAvailableTypes: ["E32"] });
    await prisma.ecfSequence.update({ where: { id: sequence.id }, data: { nextNumber: 11 } });
    expect((await query.capabilities(user)).posReady).toBe(false);
    await prisma.ecfSequence.create({ data: {
      environment: "SANDBOX",
      companyId, documentType: "E31", prefix: "E31",
      startNumber: 1, nextNumber: 1, endNumber: 10, validUntil: new Date("2000-01-01"),
    } });
    expect((await query.capabilities(user)).posReady).toBe(false);
    const configuredTax = await prisma.tax.create({ data: {
      companyId: otherId, name: "Synthetic configured tax", rate: 0.10, isActive: true, isDefault: true,
    } });
    await prisma.company.update({ where: { id: otherId }, data: { defaultTaxRate: 0.10, defaultTaxId: configuredTax.id } });
    await service.updateConfig({ ...user, companyId: otherId }, { enabled: true });
    expect(Number((await prisma.company.findUniqueOrThrow({ where: { id: otherId } })).defaultTaxRate)).toBe(0.10);
    await service.updateConfig(user, { enabled: false });
    expect((await prisma.company.findUniqueOrThrow({ where: { id: companyId } })).taxEnabled).toBe(true);
  });
});
