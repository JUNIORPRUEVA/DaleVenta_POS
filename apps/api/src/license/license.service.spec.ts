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
