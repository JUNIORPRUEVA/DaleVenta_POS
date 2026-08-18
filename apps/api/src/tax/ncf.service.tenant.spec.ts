import { NotFoundException } from "@nestjs/common";
import { NcfService } from "./ncf.service";

describe("NcfService tenant isolation", () => {
  const user = {
    id: "user-a",
    role: "ADMIN",
    companyId: "11111111-1111-1111-1111-111111111111",
  };

  it("lists only NCF sequences for the authenticated company", async () => {
    const prisma = {
      ncfSequence: { findMany: jest.fn().mockResolvedValue([]) },
    };
    const service = new NcfService(prisma as never);

    await service.listSequences(user as never);

    expect(prisma.ncfSequence.findMany).toHaveBeenCalledWith({
      where: { companyId: user.companyId },
      orderBy: [{ voucherType: "asc" }, { createdAt: "desc" }],
    });
  });

  it("does not update an NCF sequence from another company", async () => {
    const prisma = {
      ncfSequence: { findFirst: jest.fn().mockResolvedValue(null) },
    };
    const service = new NcfService(prisma as never);

    await expect(
      service.updateSequence(
        user as never,
        "22222222-2222-4222-8222-222222222222",
        { endNumber: 99 },
      ),
    ).rejects.toBeInstanceOf(NotFoundException);

    expect(prisma.ncfSequence.findFirst).toHaveBeenCalledWith({
      where: {
        id: "22222222-2222-4222-8222-222222222222",
        companyId: user.companyId,
      },
    });
  });
});
