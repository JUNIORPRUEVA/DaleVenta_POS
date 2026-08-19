import { NotFoundException } from "@nestjs/common";
import { Role } from "@prisma/client";
import { UsersService } from "./users.service";

function buildService(prisma: any) {
  const config = { get: jest.fn().mockReturnValue(undefined) };
  const licenses = {
    assertCanCreateUser: jest.fn().mockResolvedValue(undefined),
  };
  const realtime = { emitCompanyUser: jest.fn() };
  return {
    service: new UsersService(
      prisma,
      config as any,
      licenses as any,
      realtime as any,
    ),
    realtime,
  };
}

describe("UsersService tenant isolation", () => {
  it("rejects updating a user that is not in the request tenant", async () => {
    const prisma = {
      user: { findFirst: jest.fn().mockResolvedValue(null) },
    };
    const { service } = buildService(prisma);

    await expect(
      service.update(
        { id: "admin-a", role: Role.ADMIN, companyId: "company-a" },
        "user-from-company-b",
        { nombreCompleto: "Cross tenant edit" } as any,
      ),
    ).rejects.toBeInstanceOf(NotFoundException);

    expect(prisma.user.findFirst).toHaveBeenCalledWith({
      where: {
        id: "user-from-company-b",
        OR: [
          { companyId: "company-a" },
          {
            companyMemberships: {
              some: {
                companyId: "company-a",
                status: "ACTIVE",
              },
            },
          },
        ],
      },
      select: { id: true },
    });
  });

  it("removes only the tenant membership when the user belongs to another active company", async () => {
    const tx = {
      companyMember: {
        deleteMany: jest.fn().mockResolvedValue({ count: 1 }),
        findFirst: jest.fn().mockResolvedValue({ companyId: "company-b" }),
      },
      user: {
        update: jest.fn().mockResolvedValue({ id: "user-a" }),
      },
    };
    const prisma = {
      user: {
        findFirst: jest
          .fn()
          .mockResolvedValueOnce({ id: "user-a" })
          .mockResolvedValueOnce({ id: "user-a", companyId: "company-a" }),
      },
      $transaction: jest.fn(async (callback: any) => callback(tx)),
    };
    const { service } = buildService(prisma);

    await expect(
      service.remove(
        { id: "admin-a", role: Role.ADMIN, companyId: "company-a" },
        "user-a",
      ),
    ).resolves.toEqual({ ok: true });

    expect(tx.companyMember.deleteMany).toHaveBeenCalledWith({
      where: { userId: "user-a", companyId: "company-a" },
    });
    expect(tx.user.update).toHaveBeenCalledWith({
      where: { id: "user-a" },
      data: { companyId: "company-b" },
      select: { id: true },
    });
  });

  it("blocks and detaches the user when removing the last active company membership", async () => {
    const tx = {
      companyMember: {
        deleteMany: jest.fn().mockResolvedValue({ count: 1 }),
        findFirst: jest.fn().mockResolvedValue(null),
      },
      user: {
        update: jest.fn().mockResolvedValue({ id: "user-a" }),
      },
    };
    const prisma = {
      user: {
        findFirst: jest
          .fn()
          .mockResolvedValueOnce({ id: "user-a" })
          .mockResolvedValueOnce({ id: "user-a", companyId: "company-a" }),
      },
      $transaction: jest.fn(async (callback: any) => callback(tx)),
    };
    const { service } = buildService(prisma);

    await expect(
      service.remove(
        { id: "admin-a", role: Role.ADMIN, companyId: "company-a" },
        "user-a",
      ),
    ).resolves.toEqual({ ok: true });

    expect(tx.user.update).toHaveBeenCalledWith({
      where: { id: "user-a" },
      data: { blocked: true, companyId: null },
      select: { id: true },
    });
  });

  it("emits a scoped permissions.updated event after updating permissions", async () => {
    const updatedAt = new Date("2026-08-18T20:01:00.000Z");
    const prisma = {
      user: {
        findFirst: jest
          .fn()
          .mockResolvedValueOnce({ id: "employee-a" })
          .mockResolvedValueOnce({ id: "employee-a", role: Role.CAJERO })
          .mockResolvedValueOnce({
            id: "employee-a",
            email: "employee-a@test.local",
            nombreCompleto: "Employee A",
            telefono: "",
            role: Role.CAJERO,
            userPermissions: { viewSales: true },
          }),
        update: jest.fn().mockResolvedValue({ id: "employee-a", updatedAt }),
      },
    };
    const { service, realtime } = buildService(prisma);

    await service.updatePermissions(
      { id: "admin-a", role: Role.ADMIN, companyId: "company-a" },
      "employee-a",
      { viewSales: true },
    );

    expect(realtime.emitCompanyUser).toHaveBeenCalledWith(
      "company-a",
      "employee-a",
      "permissions.updated",
      expect.objectContaining({
        type: "permissions.updated",
        companyId: "company-a",
        userId: "employee-a",
        version: updatedAt.getTime(),
        updatedAt: updatedAt.toISOString(),
      }),
    );
  });
});
