import { Role } from "@prisma/client";
import { CashService } from "./cash.service";

describe("CashService pagination", () => {
  const user = {
    id: "user-a",
    role: Role.ADMIN,
    companyId: "company-a",
  };

  function serviceWith(prisma: Record<string, unknown>) {
    return new CashService(
      prisma as never,
      { emitCompany: jest.fn() } as never,
    );
  }

  it("paginates movement history with tenant scope and a max limit of 200", async () => {
    const prisma = {
      cashMovement: {
        findMany: jest.fn().mockResolvedValue([
          {
            id: "movement-1",
            session: {
              userName: "Caja",
              businessDate: "2026-10-07",
              status: "CLOSED",
              openedAt: new Date("2026-10-07T10:00:00.000Z"),
              closedAt: new Date("2026-10-07T18:00:00.000Z"),
            },
          },
        ]),
      },
    };
    const service = serviceWith(prisma);

    const result = await service.movementHistory(user, {
      page: "2",
      take: "999",
      type: "OUT",
    });

    expect(result).toMatchObject({
      page: 2,
      limit: 200,
      hasMore: false,
      nextPage: null,
    });
    expect(result.items).toHaveLength(1);
    expect(prisma.cashMovement.findMany).toHaveBeenCalledWith(
      expect.objectContaining({
        where: expect.objectContaining({ companyId: user.companyId, type: "OUT" }),
        orderBy: [{ createdAt: "desc" }, { id: "desc" }],
        skip: 200,
        take: 201,
      }),
    );
  });

  it("paginates closed sessions with tenant scope and stable ordering", async () => {
    const prisma = {
      cashSession: {
        findMany: jest.fn().mockResolvedValue([]),
      },
    };
    const service = serviceWith(prisma);

    const result = await service.closedSessions(user, {
      page: "4",
      limit: "25",
    });

    expect(result).toMatchObject({
      items: [],
      page: 4,
      limit: 25,
      hasMore: false,
      nextPage: null,
    });
    expect(prisma.cashSession.findMany).toHaveBeenCalledWith({
      where: { companyId: user.companyId, status: "CLOSED" },
      orderBy: [{ closedAt: "desc" }, { id: "desc" }],
      skip: 75,
      take: 26,
    });
  });
});
