import { ForbiddenException } from "@nestjs/common";
import { Role } from "@prisma/client";
import jwt from "jsonwebtoken";
import { PERMISSIONS_KEY, ROLES_KEY } from "./roles.decorator";
import { RolesGuard } from "./roles.guard";

function contextFor(
  user: { id: string; role: Role; companyId: string; sessionId?: string },
  headers: Record<string, unknown> = {},
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
  capabilityConsumeCount = 1,
}: {
  roles: Role[];
  permissions: string[];
  userPermissions?: Record<string, boolean>;
  capabilityConsumeCount?: number;
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
    adminAuthorizationCapability: {
      updateMany: jest.fn().mockResolvedValue({ count: capabilityConsumeCount }),
    },
  };

  return {
    guard: new RolesGuard(reflector as any, config as any, prisma as any),
    prisma,
  };
}

function adminToken({
  userId = "user-1",
  companyId = "company-1",
  sessionId = "session-1",
  jti = "11111111-1111-4111-8111-111111111111",
  scopes = ["company.settings"],
} = {}) {
  return jwt.sign(
    {
      sub: userId,
      companyId,
      sessionId,
      jti,
      tokenType: "admin-authorization",
      scopes,
    },
    "test-secret",
    { expiresIn: "10m" },
  );
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

  it("allows only the permission covered by a delegated admin scope", async () => {
    const { guard } = guardWith({
      roles: [Role.ADMIN],
      permissions: ["manageSettings"],
      userPermissions: {},
    });
    const token = adminToken();

    await expect(
      guard.canActivate(
        contextFor(
          {
            id: "user-1",
            role: Role.CAJERO,
            companyId: "company-1",
            sessionId: "session-1",
          },
          { "x-admin-authorization": token },
        ),
      ),
    ).resolves.toBe(true);
  });

  it("denies delegated admin tokens when scope does not cover the permission", async () => {
    const { guard } = guardWith({
      roles: [Role.ADMIN],
      permissions: ["manageUsers"],
      userPermissions: {},
    });
    const token = adminToken();

    await expect(
      guard.canActivate(
        contextFor(
          {
            id: "user-1",
            role: Role.CAJERO,
            companyId: "company-1",
            sessionId: "session-1",
          },
          { "x-admin-authorization": token },
        ),
      ),
    ).rejects.toBeInstanceOf(ForbiddenException);
  });

  it("denies reused delegated admin capabilities", async () => {
    const { guard } = guardWith({
      roles: [Role.ADMIN],
      permissions: ["manageSettings"],
      userPermissions: {},
      capabilityConsumeCount: 0,
    });

    await expect(
      guard.canActivate(
        contextFor(
          {
            id: "user-1",
            role: Role.CAJERO,
            companyId: "company-1",
            sessionId: "session-1",
          },
          { "x-admin-authorization": adminToken() },
        ),
      ),
    ).rejects.toBeInstanceOf(ForbiddenException);
  });

  it("denies company A capability in company B", async () => {
    const { guard, prisma } = guardWith({
      roles: [Role.ADMIN],
      permissions: ["manageSettings"],
      userPermissions: {},
    });

    await expect(
      guard.canActivate(
        contextFor(
          {
            id: "user-1",
            role: Role.CAJERO,
            companyId: "company-b",
            sessionId: "session-1",
          },
          {
            "x-admin-authorization": adminToken({
              companyId: "company-a",
            }),
          },
        ),
      ),
    ).rejects.toBeInstanceOf(ForbiddenException);
    expect(prisma.adminAuthorizationCapability.updateMany).not.toHaveBeenCalled();
  });

  it("denies employee A capability for employee B", async () => {
    const { guard, prisma } = guardWith({
      roles: [Role.ADMIN],
      permissions: ["manageSettings"],
      userPermissions: {},
    });

    await expect(
      guard.canActivate(
        contextFor(
          {
            id: "employee-b",
            role: Role.CAJERO,
            companyId: "company-1",
            sessionId: "session-1",
          },
          {
            "x-admin-authorization": adminToken({
              userId: "employee-a",
            }),
          },
        ),
      ),
    ).rejects.toBeInstanceOf(ForbiddenException);
    expect(prisma.adminAuthorizationCapability.updateMany).not.toHaveBeenCalled();
  });
});
