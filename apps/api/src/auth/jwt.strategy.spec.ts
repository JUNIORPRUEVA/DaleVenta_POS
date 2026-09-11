import { CompanyMemberRole, CompanyMemberStatus, Role } from '@prisma/client';
import { JwtStrategy } from './jwt.strategy';

describe('JwtStrategy tenant authorization role', () => {
  function activeSession() {
    return {
      id: 'session-a',
      company: {
        id: 'company-a',
        status: 'ACTIVE',
        licenseStatus: 'ACTIVE',
        trialEndsAt: null,
        licenseExpiresAt: null,
      },
    };
  }

  function activeUser(userPermissions: Record<string, boolean>) {
    return {
      id: 'employee-a',
      email: 'employee@example.com',
      role: Role.ADMIN,
      blocked: false,
      companyId: 'company-a',
      userPermissions,
      companyMemberships: [
        {
          id: 'membership-a',
          companyId: 'company-a',
          role: CompanyMemberRole.CASHIER,
          status: CompanyMemberStatus.ACTIVE,
        },
      ],
    };
  }

  it('uses active membership role when validating existing access tokens', async () => {
    const prisma = {
      user: {
        findUnique: jest.fn().mockResolvedValue(activeUser({ viewClients: true })),
      },
      authSession: {
        findFirst: jest.fn().mockResolvedValue(activeSession()),
      },
    };
    const strategy = new JwtStrategy(
      { get: jest.fn().mockReturnValue('test-secret') } as any,
      prisma as any,
      { assertCompanyCanUseApp: jest.fn() } as any,
    );

    const user = await strategy.validate({
      sub: 'employee-a',
      email: 'employee@example.com',
      role: Role.ADMIN,
      companyId: 'company-a',
      sessionId: 'session-a',
      tokenType: 'access',
    } as any);

    expect(user).toMatchObject({
      id: 'employee-a',
      role: Role.CAJERO,
      memberRole: CompanyMemberRole.CASHIER,
      companyId: 'company-a',
      userPermissions: { viewClients: true },
    });
  });

  it('reflects permission revocation on the next validation request', async () => {
    const prisma = {
      user: {
        findUnique: jest
          .fn()
          .mockResolvedValueOnce(activeUser({ viewClients: true }))
          .mockResolvedValueOnce(activeUser({ viewClients: false })),
      },
      authSession: {
        findFirst: jest.fn().mockResolvedValue(activeSession()),
      },
    };
    const strategy = new JwtStrategy(
      { get: jest.fn().mockReturnValue('test-secret') } as any,
      prisma as any,
      { assertCompanyCanUseApp: jest.fn() } as any,
    );

    const payload = {
      sub: 'employee-a',
      email: 'employee@example.com',
      role: Role.ADMIN,
      companyId: 'company-a',
      sessionId: 'session-a',
      tokenType: 'access',
    } as any;

    await expect(strategy.validate(payload)).resolves.toMatchObject({
      userPermissions: { viewClients: true },
    });
    await expect(strategy.validate(payload)).resolves.toMatchObject({
      userPermissions: { viewClients: false },
    });
    expect(prisma.user.findUnique).toHaveBeenCalledTimes(2);
  });
});
