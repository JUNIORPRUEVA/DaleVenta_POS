import { CompanyMemberRole, CompanyMemberStatus, Role } from '@prisma/client';
import { JwtStrategy } from './jwt.strategy';

describe('JwtStrategy tenant authorization role', () => {
  it('uses active membership role when validating existing access tokens', async () => {
    const prisma = {
      user: {
        findUnique: jest.fn().mockResolvedValue({
          id: 'employee-a',
          email: 'employee@example.com',
          role: Role.ADMIN,
          blocked: false,
          companyId: 'company-a',
          companyMemberships: [
            {
              id: 'membership-a',
              companyId: 'company-a',
              role: CompanyMemberRole.CASHIER,
              status: CompanyMemberStatus.ACTIVE,
            },
          ],
        }),
      },
      authSession: {
        findFirst: jest.fn().mockResolvedValue({
          id: 'session-a',
          company: {
            id: 'company-a',
            status: 'ACTIVE',
            licenseStatus: 'ACTIVE',
            trialEndsAt: null,
            licenseExpiresAt: null,
          },
        }),
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
    });
  });
});
