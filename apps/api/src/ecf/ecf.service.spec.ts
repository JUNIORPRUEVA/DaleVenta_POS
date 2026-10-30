import {
  BadRequestException,
  ConflictException,
  ForbiddenException,
  NotFoundException,
} from "@nestjs/common";
import {
  EcfAuditAction,
  EcfCertificationStatus,
  EcfEnvironment,
  EcfOnboardingStepKey,
  EcfOnboardingStepMode,
  EcfOnboardingStepStatus,
  EcfProvider,
  Role,
} from "@prisma/client";
import { EcfSecretReferenceService } from "./ecf-secret-reference.service";
import { EcfService } from "./ecf.service";

const companyId = "00000000-0000-4000-8000-000000000001";
const otherCompanyId = "00000000-0000-4000-8000-000000000002";
const user = { id: "00000000-0000-4000-8000-000000000101", role: Role.ADMIN, companyId };

function config(overrides: Record<string, unknown> = {}) {
  return {
    id: "00000000-0000-4000-8000-000000000201",
    companyId,
    enabled: false,
    provider: EcfProvider.ALANUBE,
    environment: EcfEnvironment.SANDBOX,
    certificationStatus: EcfCertificationStatus.NOT_STARTED,
    productionEnabled: false,
    alanubeCompanyId: null,
    credentialsSecretRef: null,
    certificateSecretRef: null,
    webhookSecretRef: null,
    allowedTypes: ["E31", "E32", "E34"],
    notes: null,
    createdAt: new Date("2026-10-14T00:00:00.000Z"),
    updatedAt: new Date("2026-10-14T00:00:00.000Z"),
    ...overrides,
  };
}

function step(overrides: Record<string, unknown> = {}) {
  return {
    id: "00000000-0000-4000-8000-000000000301",
    companyId,
    stepKey: EcfOnboardingStepKey.REQUIREMENTS,
    status: EcfOnboardingStepStatus.PENDING,
    mode: EcfOnboardingStepMode.MANUAL,
    evidenceId: null,
    resultSummary: null,
    lastErrorCode: null,
    lastError: null,
    blockedReason: null,
    startedAt: null,
    completedAt: null,
    confirmedAt: null,
    createdAt: new Date("2026-10-14T00:00:00.000Z"),
    updatedAt: new Date("2026-10-14T00:00:00.000Z"),
    evidence: null,
    ...overrides,
  };
}

function createPrismaMock() {
  const prisma = {
    company: {
      findUnique: jest.fn().mockResolvedValue({ id: companyId }),
    },
    ecfCompanyConfiguration: {
      findUnique: jest.fn().mockResolvedValue(config()),
      create: jest.fn().mockResolvedValue(config()),
      update: jest.fn().mockResolvedValue(config({ enabled: true })),
    },
    ecfOnboardingStep: {
      createMany: jest.fn().mockResolvedValue({ count: 14 }),
      findMany: jest.fn().mockResolvedValue([]),
      findUnique: jest.fn().mockResolvedValue(step()),
      updateMany: jest.fn().mockResolvedValue({ count: 1 }),
    },
    ecfEvidence: {
      findFirst: jest.fn().mockResolvedValue(null),
      create: jest.fn().mockResolvedValue({
        id: "00000000-0000-4000-8000-000000000401",
        companyId,
        kind: "DGII",
        storageRef: "evidence://dgii/postulation-1",
        fileName: null,
        mimeType: null,
        sha256: null,
      }),
    },
    ecfAuditLog: {
      create: jest.fn().mockResolvedValue({}),
      findMany: jest.fn().mockResolvedValue([]),
    },
    $transaction: jest.fn(async (fn: (tx: unknown) => unknown) => fn(prisma)),
  };
  return prisma;
}

describe("EcfService", () => {
  it("creates an e-CF config disabled by default without touching fiscal settings", async () => {
    const prisma = createPrismaMock();
    prisma.ecfCompanyConfiguration.findUnique.mockResolvedValueOnce(null);
    const service = new EcfService(prisma as any, new EcfSecretReferenceService());

    const result = await service.getConfig(user);

    expect(result.enabled).toBe(false);
    expect(result.environment).toBe(EcfEnvironment.SANDBOX);
    expect(result.productionEnabled).toBe(false);
    expect(result.issuance).toEqual(
      expect.objectContaining({
        configurationEnabled: false,
        productionEmissionEnabled: false,
        canEmit: false,
      }),
    );
    expect(prisma.ecfCompanyConfiguration.create).toHaveBeenCalledWith(
      expect.objectContaining({
        data: expect.objectContaining({
          companyId,
          enabled: false,
          productionEnabled: false,
        }),
      }),
    );
    expect((prisma.company as any).update).toBeUndefined();
  });

  it("uses the authenticated tenant company when updating config", async () => {
    const prisma = createPrismaMock();
    const service = new EcfService(prisma as any, new EcfSecretReferenceService());

    await service.updateConfig({ ...user, companyId: otherCompanyId }, { enabled: true });

    expect(prisma.company.findUnique).toHaveBeenCalledWith({
      where: { id: otherCompanyId },
      select: { id: true },
    });
    expect(prisma.ecfCompanyConfiguration.update).toHaveBeenCalledWith(
      expect.objectContaining({
        where: { companyId: otherCompanyId },
      }),
    );
  });

  it("does not treat enabled config as authorization to emit", async () => {
    const prisma = createPrismaMock();
    prisma.ecfCompanyConfiguration.update.mockResolvedValueOnce(
      config({
        enabled: true,
        credentialsSecretRef: "uat://alanube/credentials",
        certificateSecretRef: "uat://alanube/cert-ref",
      }),
    );
    const service = new EcfService(prisma as any, new EcfSecretReferenceService());

    const result = await service.updateConfig(user, { enabled: true });

    expect(result.enabled).toBe(true);
    expect(result.issuance).toEqual(
      expect.objectContaining({
        configurationEnabled: true,
        providerIntegrationReady: true,
        productionAuthorized: false,
        productionEmissionEnabled: false,
        canEmit: false,
      }),
    );
  });

  it("rejects production activation in this phase", async () => {
    const prisma = createPrismaMock();
    const service = new EcfService(prisma as any, new EcfSecretReferenceService());

    await expect(
      service.updateConfig(user, { environment: EcfEnvironment.PRODUCTION }),
    ).rejects.toBeInstanceOf(ForbiddenException);
  });

  it("rejects raw-looking secrets and accepts only secret references", async () => {
    const prisma = createPrismaMock();
    const service = new EcfService(prisma as any, new EcfSecretReferenceService());

    await expect(
      service.updateConfig(user, {
        certificateSecretRef: "-----BEGIN CERTIFICATE-----abc",
      }),
    ).rejects.toBeInstanceOf(BadRequestException);

    await service.updateConfig(user, {
      certificateSecretRef: "uat://alanube/cert-ref",
    });
    expect(prisma.ecfCompanyConfiguration.update).toHaveBeenCalledWith(
      expect.objectContaining({
        data: expect.objectContaining({
          certificateSecretRef: "uat://alanube/cert-ref",
        }),
      }),
    );
  });

  it("does not confirm a step without protected evidence", async () => {
    const prisma = createPrismaMock();
    const service = new EcfService(prisma as any, new EcfSecretReferenceService());

    await expect(
      service.updateStep(user, "requirements", {
        status: EcfOnboardingStepStatus.CONFIRMED,
      }),
    ).rejects.toBeInstanceOf(BadRequestException);
  });

  it("does not expose storage references in onboarding responses", async () => {
    const prisma = createPrismaMock();
    prisma.ecfOnboardingStep.findMany.mockResolvedValueOnce([
      step({
        evidenceId: "00000000-0000-4000-8000-000000000401",
        evidence: {
          id: "00000000-0000-4000-8000-000000000401",
          kind: "DGII",
          storageRef: "s3://private-bucket/company-a/postulation.pdf",
        },
      }),
    ]);
    prisma.ecfAuditLog.findMany.mockResolvedValueOnce([
      {
        id: "00000000-0000-4000-8000-000000000901",
        companyId,
        actorUserId: user.id,
        action: EcfAuditAction.EVIDENCE_LINKED,
        targetType: "EcfEvidence",
        targetId: "00000000-0000-4000-8000-000000000401",
        before: null,
        after: {
          id: "00000000-0000-4000-8000-000000000401",
          storageRef: "s3://private-bucket/company-a/postulation.pdf",
        },
        metadata: null,
        createdAt: new Date("2026-10-14T00:00:00.000Z"),
      },
    ]);
    const service = new EcfService(prisma as any, new EcfSecretReferenceService());

    const result = await service.getOnboarding(user);

    expect(JSON.stringify(result)).not.toContain("storageRef");
    expect(JSON.stringify(result)).not.toContain("private-bucket");
    expect(result.steps[0].evidence).toEqual({
      id: "00000000-0000-4000-8000-000000000401",
      kind: "DGII",
    });
  });

  it("does not expose storage references in onboarding history", async () => {
    const prisma = createPrismaMock();
    prisma.ecfAuditLog.findMany.mockResolvedValueOnce([
      {
        id: "00000000-0000-4000-8000-000000000901",
        companyId,
        actorUserId: user.id,
        action: EcfAuditAction.EVIDENCE_LINKED,
        targetType: "EcfEvidence",
        targetId: "00000000-0000-4000-8000-000000000401",
        before: null,
        after: {
          kind: "DGII",
          storageRef: "r2://tenant-private/evidence.pdf",
          nested: { webhookSecretRef: "uat://secret/webhook" },
        },
        metadata: { token: "never-return-this" },
        createdAt: new Date("2026-10-14T00:00:00.000Z"),
      },
    ]);
    const service = new EcfService(prisma as any, new EcfSecretReferenceService());

    const result = await service.listAudit(user);

    expect(JSON.stringify(result)).not.toContain("storageRef");
    expect(JSON.stringify(result)).not.toContain("tenant-private");
    expect(JSON.stringify(result)).not.toContain("webhookSecretRef");
    expect(JSON.stringify(result)).not.toContain("never-return-this");
  });

  it("blocks production enablement confirmation in this phase", async () => {
    const prisma = createPrismaMock();
    prisma.ecfOnboardingStep.findUnique.mockResolvedValueOnce(
      step({
        stepKey: EcfOnboardingStepKey.PRODUCTION_ENABLEMENT,
        evidenceId: "00000000-0000-4000-8000-000000000401",
      }),
    );
    const service = new EcfService(prisma as any, new EcfSecretReferenceService());

    await expect(
      service.updateStep(user, "production_enablement", {
        status: EcfOnboardingStepStatus.CONFIRMED,
      }),
    ).rejects.toBeInstanceOf(ForbiddenException);
  });

  it("rejects evidence ids from another company", async () => {
    const prisma = createPrismaMock();
    prisma.ecfEvidence.findFirst.mockResolvedValueOnce(null);
    const service = new EcfService(prisma as any, new EcfSecretReferenceService());

    await expect(
      service.updateStep(user, "requirements", {
        status: EcfOnboardingStepStatus.COMPLETED,
        evidenceId: "00000000-0000-4000-8000-000000000499",
      }),
    ).rejects.toBeInstanceOf(BadRequestException);
    expect(prisma.ecfEvidence.findFirst).toHaveBeenCalledWith({
      where: {
        id: "00000000-0000-4000-8000-000000000499",
        companyId,
      },
    });
  });

  it("fails explicitly when a concurrent request updates the same step first", async () => {
    const prisma = createPrismaMock();
    prisma.ecfOnboardingStep.updateMany.mockResolvedValueOnce({ count: 0 });
    const service = new EcfService(prisma as any, new EcfSecretReferenceService());

    await expect(
      service.updateStep(user, "requirements", {
        status: EcfOnboardingStepStatus.IN_PROGRESS,
      }),
    ).rejects.toBeInstanceOf(ConflictException);
  });

  it("returns not found when the tenant company does not exist", async () => {
    const prisma = createPrismaMock();
    prisma.company.findUnique.mockResolvedValueOnce(null);
    const service = new EcfService(prisma as any, new EcfSecretReferenceService());

    await expect(service.getConfig(user)).rejects.toBeInstanceOf(
      NotFoundException,
    );
  });

  it("writes audit logs without exposing secret reference values", async () => {
    const prisma = createPrismaMock();
    prisma.ecfCompanyConfiguration.findUnique.mockResolvedValueOnce(
      config({ certificateSecretRef: "uat://old/cert" }),
    );
    prisma.ecfCompanyConfiguration.update.mockResolvedValueOnce(
      config({ certificateSecretRef: "uat://new/cert" }),
    );
    const service = new EcfService(prisma as any, new EcfSecretReferenceService());

    await service.updateConfig(user, {
      certificateSecretRef: "uat://new/cert",
    });

    expect(prisma.ecfAuditLog.create).toHaveBeenCalledWith(
      expect.objectContaining({
        data: expect.objectContaining({
          action: EcfAuditAction.CONFIG_UPDATED,
          before: expect.objectContaining({
            secrets: expect.objectContaining({ certificateConfigured: true }),
          }),
          after: expect.objectContaining({
            secrets: expect.objectContaining({ certificateConfigured: true }),
          }),
        }),
      }),
    );
    const auditCall = prisma.ecfAuditLog.create.mock.calls.at(-1)?.[0];
    expect(JSON.stringify(auditCall)).not.toContain("uat://new/cert");
  });

  it("writes evidence audit snapshots without storage references", async () => {
    const prisma = createPrismaMock();
    const service = new EcfService(prisma as any, new EcfSecretReferenceService());

    await service.updateStep(user, "requirements", {
      status: EcfOnboardingStepStatus.COMPLETED,
      evidence: {
        kind: "DGII",
        storageRef: "evidence://dgii/postulation-1",
      },
    });

    const evidenceAuditCall = prisma.ecfAuditLog.create.mock.calls.find(
      ([call]) => call.data.action === EcfAuditAction.EVIDENCE_LINKED,
    )?.[0];
    expect(evidenceAuditCall).toBeDefined();
    expect(JSON.stringify(evidenceAuditCall)).not.toContain("storageRef");
    expect(JSON.stringify(evidenceAuditCall)).not.toContain(
      "evidence://dgii/postulation-1",
    );
  });
});

