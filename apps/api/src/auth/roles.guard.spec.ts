import { ForbiddenException } from "@nestjs/common";
import { Role } from "@prisma/client";
import jwt from "jsonwebtoken";
import { PERMISSIONS_KEY, ROLES_KEY } from "./roles.decorator";
import { RolesGuard } from "./roles.guard";

function contextFor(
  user: { id: string; role: Role; companyId: string },
  headers: Record<string, string> = {},
) {
  return {
    getHandler: jest.fn(),
    getClass: jest.fn(),
    switchToHttp: () => ({
      getRequest: () => ({ user, headers }),
    }),
  } as any;
}

function guardWith({
  roles,
  permissions,
  userPermissions,
}: {
  roles: Role[];
  permissions: string[];
  userPermissions?: Record<string, boolean>;
}) {
  const reflector = {
    getAllAndOverride: jest.fn((key: string) => {
      if (key === ROLES_KEY) return roles;
      if (key === PERMISSIONS_KEY) return permissions;
      return undefined;
    }),
  };
  const config = { get: jest.fn().mockReturnValue("test-secret") };
  const prisma = {
    user: {
      findFirst: jest.fn().mockResolvedValue({
        userPermissions: userPermissions ?? {},
      }),
    },
  };

  return {
    guard: new RolesGuard(reflector as any, config as any, prisma as any),
    prisma,
  };
}

describe("RolesGuard dynamic permissions", () => {
  it("allows a non-role user when the endpoint permission is granted", async () => {
    const { guard, prisma } = guardWith({
      roles: [Role.ADMIN, Role.ASISTENTE],
      permissions: ["viewClients"],
      userPermissions: { viewClients: true },
    });

    await expect(
      guard.canActivate(
        contextFor({ id: "user-1", role: Role.CAJERO, companyId: "company-1" }),
      ),
    ).resolves.toBe(true);
    expect(prisma.user.findFirst).toHaveBeenCalledWith(
      expect.objectContaining({
        select: { userPermissions: true },
      }),
    );
  });

  it("keeps denying a non-role user when the endpoint permission is missing", async () => {
    const { guard } = guardWith({
      roles: [Role.ADMIN, Role.ASISTENTE],
      permissions: ["viewClients"],
      userPermissions: { viewClients: false },
    });

    await expect(
      guard.canActivate(
        contextFor({ id: "user-1", role: Role.CAJERO, companyId: "company-1" }),
      ),
    ).rejects.toBeInstanceOf(ForbiddenException);
  });

  it("allows a scoped admin authorization token for the matching permission", async () => {
    const { guard } = guardWith({
      roles: [Role.ADMIN],
      permissions: ["addStock"],
      userPermissions: {},
    });
    const token = jwt.sign(
      {
        sub: "user-1",
        companyId: "company-1",
        tokenType: "admin-authorization",
        permissions: ["addStock"],
      },
      "test-secret",
      { expiresIn: "10m" },
    );

    await expect(
      guard.canActivate(
        contextFor(
          { id: "user-1", role: Role.CAJERO, companyId: "company-1" },
          { "x-admin-authorization": token },
        ),
      ),
    ).resolves.toBe(true);
  });

  it("rejects an admin authorization token with the wrong scope", async () => {
    const { guard } = guardWith({
      roles: [Role.ADMIN],
      permissions: ["createTransfers"],
      userPermissions: {},
    });
    const token = jwt.sign(
      {
        sub: "user-1",
        companyId: "company-1",
        tokenType: "admin-authorization",
        permissions: ["addStock"],
      },
      "test-secret",
      { expiresIn: "10m" },
    );

    await expect(
      guard.canActivate(
        contextFor(
          { id: "user-1", role: Role.CAJERO, companyId: "company-1" },
          { "x-admin-authorization": token },
        ),
      ),
    ).rejects.toBeInstanceOf(ForbiddenException);
  });

  it("rejects an admin authorization token from another tenant", async () => {
    const { guard } = guardWith({
      roles: [Role.ADMIN],
      permissions: ["addStock"],
      userPermissions: {},
    });
    const token = jwt.sign(
      {
        sub: "user-1",
        companyId: "company-2",
        tokenType: "admin-authorization",
        permissions: ["addStock"],
      },
      "test-secret",
      { expiresIn: "10m" },
    );

    await expect(
      guard.canActivate(
        contextFor(
          { id: "user-1", role: Role.CAJERO, companyId: "company-1" },
          { "x-admin-authorization": token },
        ),
      ),
    ).rejects.toBeInstanceOf(ForbiddenException);
  });
});
