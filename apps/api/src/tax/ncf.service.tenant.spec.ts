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

  it("reserveNextNcf returns the sequence validUntil (snapshot) scoped by company/type", async () => {
    const validUntil = new Date("2026-12-31T00:00:00.000Z");
    const tx = {
      $queryRaw: jest.fn().mockResolvedValue([
        {
          id: "33333333-3333-4333-8333-333333333333",
          company_id: user.companyId,
          voucher_type: "B01",
          prefix: "B01",
          start_number: 1,
          next_number: 3,
          end_number: 100000,
          valid_until: validUntil,
          active: true,
        },
      ]),
      ncfSequence: {
        update: jest.fn().mockResolvedValue({}),
      },
      ncfAuditLog: {
        create: jest.fn().mockResolvedValue({}),
      },
    };
    const service = new NcfService({} as never);

    const result = await service.reserveNextNcf(tx as never, {
      companyId: user.companyId,
      userId: user.id,
      voucherType: "B01",
    });

    expect(tx.$queryRaw).toHaveBeenCalledWith(
      expect.any(Array),
      user.companyId,
      "B01",
    );
    expect(result).toEqual({
      ncf: "B0100000003",
      sequenceId: "33333333-3333-4333-8333-333333333333",
      type: "B01",
      validUntil,
    });
    expect(tx.ncfSequence.update).toHaveBeenCalledWith({
      where: { id: "33333333-3333-4333-8333-333333333333" },
      data: { nextNumber: { increment: 1 } },
    });
  });
});
