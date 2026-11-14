import { EcfDocumentQueryService } from "./ecf-document-query.service";
import { Role } from "@prisma/client";

describe("POS e-CF readiness", () => {
  const user = { id: "operator", role: Role.ADMIN, companyId: "company-a" };

  function setup(certificationStatus = "AUTHORIZED_SANDBOX", enabled = true) {
    const prisma = {
      ecfCompanyConfiguration: {
        findUnique: jest.fn().mockResolvedValue({
          enabled, certificationStatus, environment: "SANDBOX", allowedTypes: ["E31", "E32", "E34"],
        }),
      },
      ecfSequence: {
        findMany: jest.fn().mockResolvedValue([]),
      },
    };
    return { prisma, service: new EcfDocumentQueryService(prisma as any) };
  }

  it("does not offer a selector for a newly activated company", async () => {
    const { service } = setup("NOT_STARTED");
    expect(await service.capabilities(user)).toMatchObject({ enabled: true, posReady: false });
  });

  it("requires remaining numbering even after certification", async () => {
    const { service, prisma } = setup();
    prisma.ecfSequence.findMany.mockResolvedValue([
      { documentType: "E31", nextNumber: 11, endNumber: 10 },
    ] as never);
    expect(await service.capabilities(user)).toMatchObject({ posReady: false, posAvailableTypes: [] });
  });

  it("offers only available sale types, scoped to the current company", async () => {
    const { service, prisma } = setup();
    prisma.ecfSequence.findMany.mockResolvedValue([
      { documentType: "E32", nextNumber: 10, endNumber: 10 },
    ] as never);
    expect(await service.capabilities(user)).toMatchObject({ posReady: true, posAvailableTypes: ["E32"] });
    expect(prisma.ecfSequence.findMany).toHaveBeenCalledWith(expect.objectContaining({
      where: {
        companyId: "company-a", environment: "SANDBOX", active: true, documentType: { in: ["E31", "E32"] },
        OR: [{ validUntil: null }, { validUntil: { gt: expect.any(Date) } }],
      },
    }));
  });

  it("does not offer the selector before certification, even with numbering", async () => {
    const { service, prisma } = setup("NOT_STARTED");
    prisma.ecfSequence.findMany.mockResolvedValue([
      { documentType: "E32", nextNumber: 1, endNumber: 10 },
    ] as never);
    expect((await service.capabilities(user)).posReady).toBe(false);
  });

  it("does not query numbering for a disabled company", async () => {
    const { service, prisma } = setup("AUTHORIZED_SANDBOX", false);
    expect((await service.capabilities(user)).posReady).toBe(false);
    expect(prisma.ecfSequence.findMany).not.toHaveBeenCalled();
  });
});
