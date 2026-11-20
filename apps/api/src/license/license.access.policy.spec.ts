import {
  isAllowedWhileRestricted,
  remainingDays,
  resolveLicenseAccess,
} from './license.access.policy';

const now = new Date('2026-11-16T12:00:00.000Z');

describe('resolveLicenseAccess', () => {
  it('deja trabajar durante la prueba vigente', () => {
    const access = resolveLicenseAccess(
      {
        status: 'ACTIVE',
        licenseStatus: 'TRIAL',
        trialEndsAt: new Date('2026-11-20T12:00:00.000Z'),
        licenseExpiresAt: null,
      },
      now,
    );
    expect(access).toMatchObject({
      level: 'FULL',
      reason: 'TRIAL',
      effectiveStatus: 'TRIAL',
      restricted: false,
    });
    expect(access.daysRemaining).toBe(4);
  });

  it('deja entrar con licencia vencida pero en modo restringido', () => {
    const access = resolveLicenseAccess(
      {
        status: 'ACTIVE',
        licenseStatus: 'ACTIVE',
        trialEndsAt: null,
        licenseExpiresAt: new Date('2026-11-10T12:00:00.000Z'),
      },
      now,
    );
    expect(access).toMatchObject({
      level: 'RESTRICTED',
      reason: 'EXPIRED',
      restricted: true,
    });
    expect(access.daysRemaining).toBeLessThan(0);
  });

  it('resta el acceso cuando la prueba ya termino', () => {
    const access = resolveLicenseAccess(
      {
        status: 'ACTIVE',
        licenseStatus: 'TRIAL',
        trialEndsAt: new Date('2026-11-01T12:00:00.000Z'),
        licenseExpiresAt: null,
      },
      now,
    );
    expect(access.level).toBe('RESTRICTED');
    expect(access.reason).toBe('TRIAL_EXPIRED');
  });

  it('bloquea la empresa suspendida', () => {
    const access = resolveLicenseAccess(
      {
        status: 'SUSPENDED',
        licenseStatus: 'ACTIVE',
        trialEndsAt: null,
        licenseExpiresAt: new Date('2027-01-01T00:00:00.000Z'),
      },
      now,
    );
    expect(access).toMatchObject({ level: 'BLOCKED', reason: 'COMPANY_INACTIVE' });
  });

  it('bloquea cuando una persona bloqueo la licencia', () => {
    const access = resolveLicenseAccess(
      {
        status: 'ACTIVE',
        licenseStatus: 'BLOCKED',
        trialEndsAt: null,
        licenseExpiresAt: new Date('2027-01-01T00:00:00.000Z'),
      },
      now,
    );
    expect(access).toMatchObject({ level: 'BLOCKED', reason: 'BLOCKED' });
  });

  it('un usuario sin empresa no se limita', () => {
    expect(resolveLicenseAccess(null, now)).toMatchObject({
      level: 'FULL',
      reason: 'NO_COMPANY',
      restricted: false,
    });
  });

  it('calcula los dias restantes y tolera fecha nula', () => {
    expect(remainingDays(new Date('2026-11-17T12:00:00.000Z'), now)).toBe(1);
    expect(remainingDays(null, now)).toBeNull();
  });
});

describe('isAllowedWhileRestricted', () => {
  it('permite leer licencia, planes y soporte', () => {
    expect(isAllowedWhileRestricted('GET', '/license')).toBe(true);
    expect(isAllowedWhileRestricted('GET', '/license/plans')).toBe(true);
    expect(isAllowedWhileRestricted('GET', '/support/tickets')).toBe(true);
    expect(isAllowedWhileRestricted('POST', '/auth/refresh')).toBe(true);
  });

  it('permite comprar o renovar', () => {
    expect(isAllowedWhileRestricted('POST', '/license/orders')).toBe(true);
    expect(
      isAllowedWhileRestricted('POST', '/license/orders/abc/evidence'),
    ).toBe(true);
    expect(isAllowedWhileRestricted('GET', '/license/payment-instructions')).toBe(
      true,
    );
  });

  it('bloquea el trabajo normal y la administracion', () => {
    expect(isAllowedWhileRestricted('GET', '/sales')).toBe(false);
    expect(isAllowedWhileRestricted('POST', '/sales')).toBe(false);
    expect(isAllowedWhileRestricted('GET', '/products?page=1')).toBe(false);
    expect(isAllowedWhileRestricted('PATCH', '/license/admin/abc')).toBe(false);
  });
});
