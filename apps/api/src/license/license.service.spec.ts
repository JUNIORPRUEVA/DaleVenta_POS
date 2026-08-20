import { LicenseStatus } from '@prisma/client';
import { LicenseService } from './license.service';

describe('LicenseService limits', () => {
  const service = new LicenseService({} as any, {} as any, {} as any) as any;

  it('defaults basic plan updates to 2 users and 100 products', () => {
    const data = service.licenseData({ plan: 'STANDARD' });

    expect(data.plan).toBe('STANDARD');
    expect(data.maxUsers).toBe(2);
    expect(data.maxProducts).toBe(100);
  });

  it('labels trial accounts as plan demo', () => {
    const label = service.licenseTypeLabel(
      'STANDARD',
      LicenseStatus.TRIAL,
      { maxUsers: 2, maxProducts: 100 },
    );

    expect(label).toBe('Plan demo');
  });

  it('keeps Appyra paid add-on limits for a basic license', () => {
    const data = service.licenseData({
      plan: 'STANDARD',
      maxUsers: 5,
      maxProducts: 250,
    });
    const limits = service.effectiveLimits({
      plan: data.plan,
      licenseStatus: LicenseStatus.ACTIVE,
      maxUsers: data.maxUsers,
      maxProducts: data.maxProducts,
    });

    expect(limits).toEqual({ maxUsers: 5, maxProducts: 250 });
  });

  it('accepts Appyra company name aliases for display-name sync', () => {
    expect(service.displayNameValue({ companyName: 'FULLTECH, SRL' })).toBe(
      'FULLTECH, SRL',
    );
    expect(service.displayNameValue({ businessName: 'Mi negocio' })).toBe(
      'Mi negocio',
    );
    expect(service.displayNameValue({ name: 'Licencia Demo' })).toBe(
      'Licencia Demo',
    );
  });

  it('uses companies.name as the license display name when appConfig is stale', async () => {
    const prisma = {
      company: {
        findUnique: jest.fn().mockResolvedValue({
          id: 'company-a',
          name: 'Nombre Nuevo',
          slug: 'empresa-a',
          status: 'ACTIVE',
          plan: 'STANDARD',
          licenseStatus: LicenseStatus.TRIAL,
          licenseKey: null,
          trialStartedAt: new Date('2026-08-01T00:00:00Z'),
          trialEndsAt: new Date('2026-08-30T00:00:00Z'),
          licenseActivatedAt: null,
          licenseExpiresAt: null,
          licenseBlockedAt: null,
          licenseNotes: null,
          maxUsers: 2,
          maxProducts: 100,
        }),
      },
      user: { count: jest.fn().mockResolvedValue(1) },
      product: { count: jest.fn().mockResolvedValue(0) },
      companyMember: { findFirst: jest.fn().mockResolvedValue(null) },
      appConfig: {
        findFirst: jest.fn().mockResolvedValue({
          companyName: 'Nombre Viejo',
          rnc: null,
          phone: null,
          address: null,
          description: null,
          legalRepresentativeName: null,
          legalRepresentativeCedula: null,
          legalRepresentativeRole: null,
        }),
      },
    };
    const scopedService = new LicenseService(
      prisma as any,
      {} as any,
      {} as any,
    ) as any;

    const status = await scopedService.getCompanyLicenseStatus('company-a');

    expect(status.companyName).toBe('Nombre Nuevo');
    expect(status.account.businessName).toBe('Nombre Nuevo');
  });

  it('returns a structured inactive-license error for blocked accounts', () => {
    const error = service.licenseInactiveException({
      status: LicenseStatus.BLOCKED,
      rawStatus: LicenseStatus.BLOCKED,
      blockReason: 'Licencia bloqueada',
      licenseTypeLabel: 'Plan basico',
      daysRemaining: 0,
    });

    expect(error.getStatus()).toBe(401);
    expect(error.getResponse()).toMatchObject({
      message: 'Licencia bloqueada',
      errorCode: 'LICENSE_BLOCKED',
      licenseStatus: 'BLOCKED',
      supportPhone: '829-534-4286',
    });
  });
});
