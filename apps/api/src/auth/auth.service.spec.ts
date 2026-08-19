import { CompanyMemberRole, CompanyMemberStatus, Role } from '@prisma/client';
import { AuthService } from './auth.service';

describe('AuthService tenant role hydration', () => {
  function buildService() {
    return new AuthService(
      {} as any,
      {} as any,
      {} as any,
      {} as any,
      {} as any,
    ) as any;
  }

  it('uses the active company membership role instead of stale users.role', () => {
    const service = buildService();

    const session = service.resolveCompanySession({
      id: 'employee-a',
      role: Role.ADMIN,
      companyId: 'company-a',
      companyMemberships: [
        {
          id: 'membership-a',
          role: CompanyMemberRole.CASHIER,
          status: CompanyMemberStatus.ACTIVE,
          company: {
            id: 'company-a',
            name: 'Nombre Nuevo',
            slug: 'company-a',
            status: 'ACTIVE',
            plan: 'STANDARD',
            maxUsers: 10,
          },
        },
      ],
    });

    expect(session.effectiveRole).toBe(Role.CAJERO);
    expect(session.activeCompany.name).toBe('Nombre Nuevo');
  });

  it('hydrates all users in the same company from the same company row', () => {
    const service = buildService();
    const sharedCompany = {
      id: 'company-a',
      name: 'Nombre Nuevo',
      slug: 'company-a',
      status: 'ACTIVE',
      plan: 'STANDARD',
      maxUsers: 10,
    };

    const adminSession = service.resolveCompanySession({
      id: 'admin-a',
      role: Role.ADMIN,
      companyId: 'company-a',
      companyMemberships: [
        {
          id: 'membership-admin',
          role: CompanyMemberRole.ADMIN,
          status: CompanyMemberStatus.ACTIVE,
          company: sharedCompany,
        },
      ],
    });
    const employeeSession = service.resolveCompanySession({
      id: 'employee-a',
      role: Role.ADMIN,
      companyId: 'company-a',
      companyMemberships: [
        {
          id: 'membership-employee',
          role: CompanyMemberRole.SELLER,
          status: CompanyMemberStatus.ACTIVE,
          company: sharedCompany,
        },
      ],
    });

    expect(adminSession.activeCompany.id).toBe('company-a');
    expect(employeeSession.activeCompany.id).toBe('company-a');
    expect(adminSession.activeCompany.name).toBe('Nombre Nuevo');
    expect(employeeSession.activeCompany.name).toBe('Nombre Nuevo');
    expect(employeeSession.effectiveRole).toBe(Role.VENDEDOR);
  });
});
