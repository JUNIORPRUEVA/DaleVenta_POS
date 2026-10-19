import { BadRequestException, UnauthorizedException } from "@nestjs/common";
import { CompanyMemberRole, CompanyMemberStatus, Role } from "@prisma/client";
import { AuthService } from "./auth.service";

describe("AuthService tenant role hydration", () => {
  function buildService() {
    return new AuthService(
      {} as any,
      {} as any,
      {} as any,
      {} as any,
      {} as any,
      {} as any,
      {} as any,
    ) as any;
  }

  it("uses the active company membership role instead of stale users.role", () => {
    const service = buildService();

    const session = service.resolveCompanySession({
      id: "employee-a",
      role: Role.ADMIN,
      companyId: "company-a",
      companyMemberships: [
        {
          id: "membership-a",
          role: CompanyMemberRole.CASHIER,
          status: CompanyMemberStatus.ACTIVE,
          company: {
            id: "company-a",
            name: "Nombre Nuevo",
            slug: "company-a",
            status: "ACTIVE",
            plan: "STANDARD",
            maxUsers: 10,
          },
        },
      ],
    });

    expect(session.effectiveRole).toBe(Role.CAJERO);
    expect(session.activeCompany.name).toBe("Nombre Nuevo");
  });

  it("hydrates all users in the same company from the same company row", () => {
    const service = buildService();
    const sharedCompany = {
      id: "company-a",
      name: "Nombre Nuevo",
      slug: "company-a",
      status: "ACTIVE",
      plan: "STANDARD",
      maxUsers: 10,
    };

    const adminSession = service.resolveCompanySession({
      id: "admin-a",
      role: Role.ADMIN,
      companyId: "company-a",
      companyMemberships: [
        {
          id: "membership-admin",
          role: CompanyMemberRole.ADMIN,
          status: CompanyMemberStatus.ACTIVE,
          company: sharedCompany,
        },
      ],
    });
    const employeeSession = service.resolveCompanySession({
      id: "employee-a",
      role: Role.ADMIN,
      companyId: "company-a",
      companyMemberships: [
        {
          id: "membership-employee",
          role: CompanyMemberRole.SELLER,
          status: CompanyMemberStatus.ACTIVE,
          company: sharedCompany,
        },
      ],
    });

    expect(adminSession.activeCompany.id).toBe("company-a");
    expect(employeeSession.activeCompany.id).toBe("company-a");
    expect(adminSession.activeCompany.name).toBe("Nombre Nuevo");
    expect(employeeSession.activeCompany.name).toBe("Nombre Nuevo");
    expect(employeeSession.effectiveRole).toBe(Role.VENDEDOR);
  });

  it("does not require onboarding for existing companies without the new flag", () => {
    const service = buildService();

    const session = service.resolveCompanySession({
      id: "existing-admin",
      role: Role.ADMIN,
      companyId: "company-existing",
      companyMemberships: [
        {
          id: "membership-existing",
          role: CompanyMemberRole.OWNER,
          status: CompanyMemberStatus.ACTIVE,
          company: {
            id: "company-existing",
            name: "Empresa Existente",
            slug: "empresa-existente",
            status: "ACTIVE",
            plan: "STANDARD",
            maxUsers: 10,
          },
        },
      ],
    });

    expect(session.activeCompany.requiresOnboarding).toBe(false);
    expect(session.activeCompany.onboardingCompleted).toBe(true);
  });

  it("requires onboarding only for explicitly marked new companies", () => {
    const service = buildService();

    const session = service.resolveCompanySession({
      id: "new-admin",
      role: Role.ADMIN,
      companyId: "company-new",
      companyMemberships: [
        {
          id: "membership-new",
          role: CompanyMemberRole.OWNER,
          status: CompanyMemberStatus.ACTIVE,
          company: {
            id: "company-new",
            name: "Empresa Nueva",
            slug: "empresa-nueva",
            status: "ACTIVE",
            plan: "STANDARD",
            maxUsers: 2,
            onboardingRequired: true,
            onboardingStatus: "WELCOME_PENDING",
          },
        },
      ],
    });

    expect(session.activeCompany.requiresOnboarding).toBe(true);
    expect(session.activeCompany.onboardingCompleted).toBe(false);
  });
});

describe("AuthService login errors", () => {
  it("returns USER_BLOCKED for an active-license blocked user", async () => {
    const prisma = {
      user: {
        findUnique: jest.fn().mockResolvedValue({
          id: "blocked-user",
          email: "blocked@test.local",
          passwordHash: "hash",
          role: Role.ADMIN,
          blocked: true,
          companyId: "company-a",
          company: { id: "company-a", name: "Company A", slug: "company-a" },
          companyMemberships: [],
        }),
      },
    };
    const service = new AuthService(
      prisma as any,
      {} as any,
      {} as any,
      {} as any,
      { assertCompanyCanUseApp: jest.fn() } as any,
      {} as any,
      {} as any,
    );

    await expect(
      service.login("blocked@test.local", "whatever"),
    ).rejects.toMatchObject({
      response: expect.objectContaining({
        code: "USER_BLOCKED",
        message: "User blocked",
      }),
    });
    await expect(
      service.login("blocked@test.local", "whatever"),
    ).rejects.toBeInstanceOf(UnauthorizedException);
  });
});

describe("AuthService offline emergency authorization", () => {
  function buildOfflineService(prismaOverrides: Record<string, unknown> = {}) {
    const prisma = {
      $queryRaw: jest.fn().mockResolvedValue([{ ready: true }]),
      authSession: {
        findFirst: jest.fn().mockResolvedValue({
          id: "session-1",
          expiresAt: new Date("2026-10-14T12:00:00.000Z"),
        }),
      },
      user: {
        findFirst: jest.fn().mockResolvedValue({ id: "user-1" }),
      },
      ...prismaOverrides,
    };
    const licenses = {
      assertCompanyCanUseApp: jest.fn().mockResolvedValue(undefined),
    };
    const service = new AuthService(
      prisma as any,
      {} as any,
      {} as any,
      {} as any,
      licenses as any,
      {} as any,
      {} as any,
    );
    return { service, prisma, licenses };
  }

  it("issues a scoped 48h authorization for the authenticated session and device", async () => {
    jest.useFakeTimers().setSystemTime(new Date("2026-10-13T12:00:00.000Z"));
    const { service, prisma, licenses } = buildOfflineService();

    await expect(
      service.authorizeOfflineEmergency(
        {
          id: "user-1",
          companyId: "company-1",
          sessionId: "session-1",
          role: Role.CAJERO,
        },
        {
          deviceFingerprint: "device-1",
          platform: "windows",
          appVersion: "1.0.5+124",
        },
      ),
    ).resolves.toMatchObject({
      authorized: true,
      policyVersion: "offline-safe-48h.v1",
      companyId: "company-1",
      userId: "user-1",
      sessionId: "session-1",
      deviceFingerprint: "device-1",
      serverUtc: "2026-10-13T12:00:00.000Z",
      validUntilUtc: "2026-10-15T12:00:00.000Z",
      maxOfflineHours: 48,
      allowedOperations: ["sales.create"],
      capabilities: { protocolVersion: 2, inventoryOperationId: true, inventoryPayloadHash: true },
    });

    expect(prisma.authSession.findFirst).toHaveBeenCalledWith({
      where: {
        id: "session-1",
        userId: "user-1",
        companyId: "company-1",
        revokedAt: null,
        expiresAt: { gt: new Date("2026-10-13T12:00:00.000Z") },
      },
      select: { id: true, expiresAt: true },
    });
    expect(licenses.assertCompanyCanUseApp).toHaveBeenCalledWith("company-1");
    jest.useRealTimers();
  });

  it("rejects offline authorization without a device fingerprint", async () => {
    const { service } = buildOfflineService();

    await expect(
      service.authorizeOfflineEmergency(
        { id: "user-1", companyId: "company-1", sessionId: "session-1" },
        { deviceFingerprint: "" },
      ),
    ).rejects.toBeInstanceOf(BadRequestException);
  });

  it("does not advertise advanced idempotency before schema expansion", async () => {
    const { service } = buildOfflineService({ $queryRaw: jest.fn().mockResolvedValue([{ ready: false }]) });
    const result = await service.authorizeOfflineEmergency(
      { id: "user-1", companyId: "company-1", sessionId: "session-1", role: Role.ADMIN },
      { deviceFingerprint: "device-1" },
    );
    expect(result.capabilities).toMatchObject({ productOperationId: false, inventoryOperationId: false, inventoryPayloadHash: false });
  });

  it.each([
    [Role.ADMIN, {}, ["sales.create", "catalog.products.create", "catalog.products.stock"]],
    [Role.CAJERO, { addStock: true }, ["sales.create", "catalog.products.stock"]],
    [Role.CAJERO, { editProducts: true }, ["sales.create", "catalog.products.create"]],
    [Role.CAJERO, { addStock: false, editProducts: false }, ["sales.create"]],
  ])("scopes offline operation categories for %s with explicit permissions", async (role, userPermissions, allowedOperations) => {
    const { service } = buildOfflineService({ user: { findFirst: jest.fn().mockResolvedValue({ id: "user-1", userPermissions }) } });
    const result = await service.authorizeOfflineEmergency({ id: "user-1", companyId: "company-1", sessionId: "session-1", role }, { deviceFingerprint: "device-1" });
    expect(result.allowedOperations).toEqual(allowedOperations);
  });

  it("rejects offline authorization when the session was revoked or changed", async () => {
    const { service, prisma, licenses } = buildOfflineService({
      authSession: { findFirst: jest.fn().mockResolvedValue(null) },
    });

    await expect(
      service.authorizeOfflineEmergency(
        {
          id: "user-1",
          companyId: "company-1",
          sessionId: "revoked-session",
          role: Role.CAJERO,
        },
        { deviceFingerprint: "device-1" },
      ),
    ).rejects.toBeInstanceOf(UnauthorizedException);

    expect(prisma.authSession.findFirst).toHaveBeenCalledWith({
      where: {
        id: "revoked-session",
        userId: "user-1",
        companyId: "company-1",
        revokedAt: null,
        expiresAt: { gt: expect.any(Date) },
      },
      select: { id: true, expiresAt: true },
    });
    expect(licenses.assertCompanyCanUseApp).not.toHaveBeenCalled();
  });

  it("rejects offline authorization when the user is not active in the token company", async () => {
    const { service, prisma, licenses } = buildOfflineService({
      user: { findFirst: jest.fn().mockResolvedValue(null) },
    });

    await expect(
      service.authorizeOfflineEmergency(
        {
          id: "user-1",
          companyId: "wrong-company",
          sessionId: "session-1",
          role: Role.CAJERO,
        },
        { deviceFingerprint: "device-1" },
      ),
    ).rejects.toBeInstanceOf(UnauthorizedException);

    expect(prisma.user.findFirst).toHaveBeenCalledWith({
      where: {
        id: "user-1",
        blocked: false,
        OR: [
          { companyId: "wrong-company" },
          {
            companyMemberships: {
              some: {
                companyId: "wrong-company",
                status: CompanyMemberStatus.ACTIVE,
              },
            },
          },
        ],
      },
      select: { id: true, userPermissions: true },
    });
    expect(licenses.assertCompanyCanUseApp).not.toHaveBeenCalled();
  });

  it("rejects offline authorization when the company license is not usable", async () => {
    const { service, licenses } = buildOfflineService();
    licenses.assertCompanyCanUseApp.mockRejectedValue(
      new UnauthorizedException("Licencia no activa"),
    );

    await expect(
      service.authorizeOfflineEmergency(
        {
          id: "user-1",
          companyId: "company-1",
          sessionId: "session-1",
          role: Role.CAJERO,
        },
        { deviceFingerprint: "device-1" },
      ),
    ).rejects.toBeInstanceOf(UnauthorizedException);
  });
});
