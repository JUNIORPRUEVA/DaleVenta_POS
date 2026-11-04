import type { ConfigService } from "@nestjs/config";
import type { PrismaService } from "../../../prisma/prisma.service";
import { EcfDgiiHabilitationService } from "../ecf-dgii-habilitation.service";

const companyId = "company-a";
const fiscalUpdatedAt = new Date("2026-11-03T12:00:00.000Z");

function setup() {
  const prisma = {
    appConfig: {
      findFirst: jest.fn().mockResolvedValue({ updatedAt: fiscalUpdatedAt }),
    },
    ecfDgiiApplicationSnapshot: {
      findFirst: jest.fn().mockResolvedValue({ version: 2 }),
    },
  };
  const service = new EcfDgiiHabilitationService(
    prisma as unknown as PrismaService,
    {} as ConfigService,
  );
  const status = (requirements: object) =>
    (service as any).certificateValidation(companyId, requirements);
  return { prisma, status };
}

const validation = {
  notAfter: "2027-04-16T00:00:00.000Z",
  fiscalUpdatedAt: fiscalUpdatedAt.toISOString(),
  snapshotVersion: 2,
  validatedAt: "2026-11-03T12:00:00.000Z",
};

describe("persisted certificate resume", () => {
  test("restores only a current validation for the authenticated company", async () => {
    const { prisma, status } = setup();
    await expect(status({ __certificateValidation: validation })).resolves.toEqual({
      ready: true,
      notAfter: validation.notAfter,
      reason: null,
    });
    expect(prisma.appConfig.findFirst).toHaveBeenCalledWith({
      where: { companyId },
      select: { updatedAt: true },
    });
    expect(prisma.ecfDgiiApplicationSnapshot.findFirst).toHaveBeenCalledWith({
      where: { companyId },
      orderBy: { version: "desc" },
      select: { version: true },
    });
  });

  test("missing validation fails closed without a data request", async () => {
    const { prisma, status } = setup();
    await expect(status({})).resolves.toBeNull();
    expect(prisma.appConfig.findFirst).not.toHaveBeenCalled();
  });

  test("expired validation requires a new certificate", async () => {
    const { status } = setup();
    const result = await status({
      __certificateValidation: {
        ...validation,
        notAfter: "2020-01-01T00:00:00.000Z",
      },
    });
    expect(result.ready).toBe(false);
    expect(result.reason).toContain("venció");
  });

  test("changed fiscal identity source invalidates the old validation", async () => {
    const { prisma, status } = setup();
    prisma.appConfig.findFirst.mockResolvedValue({
      updatedAt: new Date("2026-11-04T12:00:00.000Z"),
    });
    const result = await status({ __certificateValidation: validation });
    expect(result.ready).toBe(false);
    expect(result.reason).toContain("datos fiscales cambiaron");
  });

  test("a successful validation stores metadata and audit for one company", async () => {
    const tx = {
      ecfDgiiHabilitation: {
        updateMany: jest.fn().mockResolvedValue({ count: 1 }),
      },
      ecfAuditLog: { create: jest.fn().mockResolvedValue({}) },
    };
    const prisma = {
      appConfig: {
        findFirst: jest.fn().mockResolvedValue({ updatedAt: fiscalUpdatedAt }),
      },
      ecfDgiiApplicationSnapshot: {
        findFirst: jest.fn().mockResolvedValue({ version: 2 }),
      },
      ecfDgiiHabilitation: {
        findUnique: jest.fn().mockResolvedValue({
          id: "record-a",
          companyId,
          updatedAt: fiscalUpdatedAt,
          requirements: { REQUIREMENTS: { status: "PENDING" } },
        }),
      },
      $transaction: jest.fn(async (action: (client: typeof tx) => Promise<void>) =>
        action(tx)),
    };
    const service = new EcfDgiiHabilitationService(
      prisma as unknown as PrismaService,
      {} as ConfigService,
    );
    await service.rememberCertificateValidation(
      { id: "admin-a", role: "ADMIN", companyId },
      {
        canProceed: true,
        certificate: { notAfter: validation.notAfter },
      } as any,
      {
        fiscalUpdatedAt: fiscalUpdatedAt.toISOString(),
        snapshotVersion: 2,
      },
    );
    expect(tx.ecfDgiiHabilitation.updateMany).toHaveBeenCalledWith(
      expect.objectContaining({
        where: { id: "record-a", companyId, updatedAt: fiscalUpdatedAt },
      }),
    );
    const written = tx.ecfDgiiHabilitation.updateMany.mock.calls[0][0].data;
    expect(written.requirements.REQUIREMENTS).toEqual({ status: "PENDING" });
    expect(written.requirements.__certificateValidation.notAfter).toBe(
      validation.notAfter,
    );
    expect(JSON.stringify(written)).not.toMatch(/password|privateKey|buffer/i);
    expect(tx.ecfAuditLog.create).toHaveBeenCalledTimes(1);
  });

  test("a rejected certificate never creates a persisted success", async () => {
    const { prisma } = setup();
    const service = new EcfDgiiHabilitationService(
      prisma as unknown as PrismaService,
      {} as ConfigService,
    );
    await service.rememberCertificateValidation(
      { id: "admin-a", role: "ADMIN", companyId },
      { canProceed: false, certificate: null } as any,
      { fiscalUpdatedAt: null, snapshotVersion: null },
    );
    expect(prisma.appConfig.findFirst).not.toHaveBeenCalled();
  });

  test("does not save a result if fiscal data changed during validation", async () => {
    const { prisma } = setup();
    const service = new EcfDgiiHabilitationService(
      prisma as unknown as PrismaService,
      {} as ConfigService,
    );
    await expect(
      service.rememberCertificateValidation(
        { id: "admin-a", role: "ADMIN", companyId },
        { canProceed: true, certificate: { notAfter: validation.notAfter } } as any,
        { fiscalUpdatedAt: "older revision", snapshotVersion: 2 },
      ),
    ).rejects.toThrow("cambiaron durante la validación");
  });
});
