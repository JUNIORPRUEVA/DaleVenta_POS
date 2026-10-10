import { ConflictException, NotFoundException } from "@nestjs/common";
import { ClientsService } from "./clients.service";

describe("ClientsService multi-tenant isolation", () => {
  const companyA = "11111111-1111-1111-1111-111111111111";
  const companyB = "22222222-2222-4222-8222-222222222222";
  const userA = {
    id: "user-a",
    role: "ADMIN",
    companyId: companyA,
  };

  function serviceWith(prisma: Record<string, unknown>) {
    if (!('$transaction' in prisma)) {
      (prisma as any).$transaction = jest.fn(
        async (work: (tx: typeof prisma) => unknown) => work(prisma),
      );
    }
    return new ClientsService(
      prisma as never,
      { emitOps: jest.fn() } as never,
    );
  }

  function clientRow(companyId: string) {
    return {
      id: "33333333-3333-4333-8333-333333333333",
      ownerId: "user-a",
      companyId,
      nombre: "Potatoes Dres, SRL",
      telefono: "8090000000",
      email: null,
      direccion: null,
      notas: null,
      taxId: "133020253",
      businessName: "Potatoes Dres, SRL",
      taxIdType: "RNC",
      phoneNormalized: "8090000000",
      locationUrl: null,
      latitude: null,
      longitude: null,
      createdAt: new Date(),
      updatedAt: new Date(),
      isDeleted: false,
    };
  }

  it("scopes taxId dedup by companyId when creating a client", async () => {
    const prisma = {
      client: {
        findFirst: jest.fn().mockResolvedValue(null),
        create: jest.fn().mockResolvedValue(clientRow(companyA)),
      },
    };
    const service = serviceWith(prisma);

    await service.create(userA as never, {
      nombre: "Potatoes Dres, SRL",
      telefono: "8090000000",
      taxId: "133020253",
      businessName: "Potatoes Dres, SRL",
      taxIdType: "RNC",
    });

    expect(prisma.client.findFirst).toHaveBeenCalledWith({
      where: {
        isDeleted: false,
        companyId: companyA,
        taxId: "133020253",
      },
      select: { id: true },
    });

    expect(prisma.client.create).toHaveBeenCalledWith({
      data: expect.objectContaining({
        companyId: companyA,
        ownerId: userA.id,
        taxId: "133020253",
      }),
    });
  });

  it("aplica ownerFilter=mine en el servidor sin perder el aislamiento por empresa", async () => {
    const findMany = jest.fn().mockResolvedValue([clientRow(companyA)]);
    const prisma = {
      client: { findMany, count: jest.fn().mockResolvedValue(1) },
    };
    const service = serviceWith(prisma);

    await service.findAll(userA as never, { ownerFilter: "mine" } as never);

    expect(findMany.mock.calls[0][0].where).toEqual(
      expect.objectContaining({ companyId: companyA, ownerId: userA.id }),
    );
  });

  it("aplica correoFilter conCorreo/sinCorreo en el servidor", async () => {
    const findMany = jest.fn().mockResolvedValue([]);
    const prisma = {
      client: { findMany, count: jest.fn().mockResolvedValue(0) },
    };
    const service = serviceWith(prisma);

    await service.findAll(userA as never, { correoFilter: "conCorreo" } as never);
    expect(findMany.mock.calls[0][0].where.AND).toEqual([
      { email: { not: null } },
      { NOT: { email: "" } },
    ]);

    findMany.mockClear();
    await service.findAll(userA as never, { correoFilter: "sinCorreo" } as never);
    expect(findMany.mock.calls[0][0].where.NOT).toEqual({
      AND: [{ email: { not: null } }, { NOT: { email: "" } }],
    });
  });

  it("order az/za se resuelve en el servidor y el envelope conserva total y hasMore", async () => {
    const findMany = jest.fn().mockResolvedValue([]);
    const prisma = {
      client: {
        findMany,
        count: jest.fn().mockResolvedValue(500),
      },
    };
    const service = serviceWith(prisma);

    const result = await service.findAll(userA as never, {
      order: "az",
      page: 1,
      pageSize: 50,
    } as never);

    expect(findMany.mock.calls[0][0].orderBy).toEqual([
      { nombre: "asc" },
      { id: "desc" },
    ]);
    expect(result.total).toBe(500);
    expect(result.limit).toBe(50);
    expect(result.hasMore).toBe(true);
    expect(result.nextPage).toBe(2);
  });

  it("sin order conserva el orden por actividad (compatibilidad)", async () => {
    const findMany = jest.fn().mockResolvedValue([]);
    const prisma = {
      client: { findMany, count: jest.fn().mockResolvedValue(0) },
    };
    const service = serviceWith(prisma);

    await service.findAll(userA as never, {} as never);

    expect(findMany.mock.calls[0][0].orderBy).toEqual([
      { lastActivityAt: "desc" },
      { createdAt: "desc" },
      { id: "desc" },
    ]);
  });

  it("allows the same taxId in a different company (no cross-tenant dedup)", async () => {
    const prisma = {
      client: {
        findFirst: jest.fn().mockResolvedValue(null),
        create: jest.fn().mockResolvedValue(clientRow(companyB)),
      },
    };
    const service = serviceWith(prisma);

    const userB = { ...userA, id: "user-b", companyId: companyB };
    await service.create(userB as never, {
      nombre: "Potatoes Dres, SRL",
      telefono: "8290000000",
      taxId: "133020253",
      businessName: "Potatoes Dres, SRL",
    });

    expect(prisma.client.create).toHaveBeenCalledWith({
      data: expect.objectContaining({
        companyId: companyB,
        taxId: "133020253",
      }),
    });
  });

  it("throws ConflictException when the taxId already exists in the same company", async () => {
    const prisma = {
      client: {
        findFirst: jest.fn().mockResolvedValue({ id: "33333333-3333-4333-8333-333333333333" }),
        create: jest.fn(),
      },
    };
    const service = serviceWith(prisma);

    await expect(
      service.create(userA as never, {
        nombre: "Duplicado",
        telefono: "8090000001",
        taxId: "133020253",
      }),
    ).rejects.toBeInstanceOf(ConflictException);
  });

  it("scopes findAll search by companyId (RNC search included)", async () => {
    const prisma = {
      client: {
        findMany: jest.fn().mockResolvedValue([]),
        count: jest.fn().mockResolvedValue(0),
      },
    };
    const service = serviceWith(prisma);

    const result = await service.findAll(userA as never, {
      search: "133020253",
      page: 1,
      pageSize: 20,
    } as never);

    expect(result.total).toBe(0);
    const where = prisma.client.findMany.mock.calls[0][0].where;
    const parts = Array.isArray(where.AND) ? where.AND : [where];
    expect(parts).toContainEqual({
      companyId: companyA,
      isDeleted: false,
    });
    expect(parts).toContainEqual(
      expect.objectContaining({
        OR: expect.arrayContaining([
          { taxId: { contains: "133020253" } },
        ]),
      }),
    );
    expect(prisma.client.count).toHaveBeenCalledWith({ where });
  });

  it("accepts backup page-limit pagination and returns a bounded envelope", async () => {
    const rows = [
      clientRow(companyA),
      { ...clientRow(companyA), id: "44444444-4444-4444-8444-444444444444" },
      { ...clientRow(companyA), id: "55555555-5555-4555-8555-555555555555" },
    ];
    const prisma = {
      client: {
        findMany: jest.fn().mockResolvedValue(rows),
        count: jest.fn().mockResolvedValue(3),
      },
    };
    const service = serviceWith(prisma);

    const result = await service.findAll(userA as never, {
      page: 2,
      limit: 2,
    } as never);

    expect(prisma.client.findMany).toHaveBeenCalledWith(
      expect.objectContaining({
        skip: 2,
        take: 3,
      }),
    );
    expect(result.items).toHaveLength(2);
    expect(result.page).toBe(2);
    expect(result.limit).toBe(2);
    expect(result.pageSize).toBe(2);
    expect(result.hasMore).toBe(true);
    expect(result.nextPage).toBe(3);
    expect(result.total).toBe(3);
  });

  it("rejects update of a client that belongs to another company", async () => {
    const prisma = {
      client: {
        findFirst: jest.fn().mockResolvedValue(null),
      },
    };
    const service = serviceWith(prisma);

    const foreignClientId = "44444444-4444-4444-8444-444444444444";

    await expect(
      service.update(userA as never, foreignClientId, {
        businessName: "Otra empresa",
      } as never),
    ).rejects.toBeInstanceOf(NotFoundException);

    expect(prisma.client.findFirst).toHaveBeenCalledWith({
      where: {
        id: foreignClientId,
        companyId: companyA,
      },
    });
  });
});
