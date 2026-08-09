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
});
