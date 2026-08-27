import { ConflictException, NotFoundException } from "@nestjs/common";
import { CompanyMemberRole, Role } from "@prisma/client";
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
          .mockResolvedValueOnce({
            id: "user-a",
            companyId: "company-a",
            role: Role.CAJERO,
            blocked: false,
          }),
        count: jest.fn(),
      },
      companyMember: {
        findFirst: jest.fn().mockResolvedValue({
          role: CompanyMemberRole.CASHIER,
        }),
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

  it("blocks and detaches a non-admin user when removing the last active company membership", async () => {
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
          .mockResolvedValueOnce({
            id: "user-a",
            companyId: "company-a",
            role: Role.CAJERO,
            blocked: false,
          }),
        count: jest.fn(),
      },
      companyMember: {
        findFirst: jest.fn().mockResolvedValue({
          role: CompanyMemberRole.CASHIER,
        }),
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

  it("rejects self-blocking the authenticated user", async () => {
    const prisma = {
      user: {
        findFirst: jest
          .fn()
          .mockResolvedValueOnce({ id: "admin-a" })
          .mockResolvedValueOnce({
            id: "admin-a",
            companyId: "company-a",
            role: Role.ADMIN,
            blocked: false,
          }),
      },
    };
    const { service } = buildService(prisma);

    await expect(
      service.setBlocked(
        { id: "admin-a", role: Role.ADMIN, companyId: "company-a" },
        "admin-a",
        true,
      ),
    ).rejects.toMatchObject({
      response: expect.objectContaining({ code: "SELF_BLOCK_NOT_ALLOWED" }),
    });
  });

  it("rejects blocking the last operational admin in a company", async () => {
    const prisma = {
      user: {
        findFirst: jest
          .fn()
          .mockResolvedValueOnce({ id: "admin-b" })
          .mockResolvedValueOnce({
            id: "admin-b",
            companyId: "company-a",
            role: Role.ADMIN,
            blocked: false,
          }),
        count: jest.fn().mockResolvedValue(0),
      },
      companyMember: {
        findFirst: jest.fn().mockResolvedValue({
          role: CompanyMemberRole.ADMIN,
        }),
      },
    };
    const { service } = buildService(prisma);

    await expect(
      service.setBlocked(
        { id: "admin-a", role: Role.ADMIN, companyId: "company-a" },
        "admin-b",
        true,
      ),
    ).rejects.toBeInstanceOf(ConflictException);
  });

  it("allows blocking one admin when another operational admin remains", async () => {
    const updatedAt = new Date("2026-08-27T13:00:00.000Z");
    const prisma = {
      user: {
        findFirst: jest
          .fn()
          .mockResolvedValueOnce({ id: "admin-b" })
          .mockResolvedValueOnce({
            id: "admin-b",
            companyId: "company-a",
            role: Role.ADMIN,
            blocked: false,
          }),
        count: jest.fn().mockResolvedValue(1),
        update: jest.fn().mockResolvedValue({
          id: "admin-b",
          email: "admin-b@test.local",
          role: Role.ADMIN,
          blocked: true,
          updatedAt,
        }),
      },
      companyMember: {
        findFirst: jest.fn().mockResolvedValue({
          role: CompanyMemberRole.ADMIN,
        }),
      },
    };
    const { service } = buildService(prisma);

    await expect(
      service.setBlocked(
        { id: "admin-a", role: Role.ADMIN, companyId: "company-a" },
        "admin-b",
        true,
      ),
    ).resolves.toMatchObject({ id: "admin-b", blocked: true });
  });

  it("rejects removing the last operational admin in a company", async () => {
    const prisma = {
      user: {
        findFirst: jest
          .fn()
          .mockResolvedValueOnce({ id: "admin-b" })
          .mockResolvedValueOnce({
            id: "admin-b",
            companyId: "company-a",
            role: Role.ADMIN,
            blocked: false,
          }),
        count: jest.fn().mockResolvedValue(0),
      },
      companyMember: {
        findFirst: jest.fn().mockResolvedValue({
          role: CompanyMemberRole.OWNER,
        }),
      },
    };
    const { service } = buildService(prisma);

    await expect(
      service.remove(
        { id: "admin-a", role: Role.ADMIN, companyId: "company-a" },
        "admin-b",
      ),
    ).rejects.toBeInstanceOf(ConflictException);
  });

  it("rejects removing the last operational admin role", async () => {
    const prisma = {
      user: {
        findFirst: jest
          .fn()
          .mockResolvedValueOnce({ id: "admin-b" })
          .mockResolvedValueOnce({
            id: "admin-b",
            companyId: "company-a",
            role: Role.ADMIN,
            blocked: false,
            numeroFlota: "1",
          }),
        count: jest.fn().mockResolvedValue(0),
      },
      companyMember: {
        findFirst: jest.fn().mockResolvedValue({
          role: CompanyMemberRole.OWNER,
        }),
      },
    };
    const { service } = buildService(prisma);

    await expect(
      service.update(
        { id: "admin-a", role: Role.ADMIN, companyId: "company-a" },
        "admin-b",
        { role: Role.CAJERO } as any,
      ),
    ).rejects.toBeInstanceOf(ConflictException);
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
