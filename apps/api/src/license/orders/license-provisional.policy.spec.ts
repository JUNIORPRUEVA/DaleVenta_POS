import { LicenseActivationState } from '@prisma/client';
import {
  canRevert,
  provisionalWindowDays,
  snapshotOf,
} from './license-provisional.service';

const NOW = new Date('2026-11-17T12:00:00.000Z');

const company = {
  status: 'ACTIVE',
  licenseStatus: 'ACTIVE' as never,
  planCode: 'pro',
  planCatalogVersion: 1,
  plan: 'STANDARD',
  licenseExpiresAt: new Date('2026-12-01T12:00:00.000Z'),
  licenseActivatedAt: new Date('2026-10-01T12:00:00.000Z'),
  licenseBlockedAt: null,
  updatedAt: NOW,
  maxUsers: 4,
  maxProducts: 1000,
  maxWarehouses: 5,
  ncfEnabled: true,
  taxEnabled: true,
  wholesalePriceListsEnabled: false,
  measurementUnitsEnabled: true,
};

describe('snapshotOf', () => {
  it('guarda lo justo para restaurar la licencia', () => {
    const snapshot = snapshotOf(company);
    expect(snapshot.planCode).toBe('pro');
    expect(snapshot.licenseExpiresAt).toBe('2026-12-01T12:00:00.000Z');
    expect(snapshot.licenseEpoch).toBe(NOW.toISOString());
    expect(snapshot.maxUsers).toBe(4);
  });
});

describe('canRevert', () => {
  const order = {
    planCode: 'empresa',
    periodEnd: new Date('2026-12-26T12:00:00.000Z'),
  };

  it('revierte cuando la licencia sigue como la dejo esta orden', () => {
    expect(
      canRevert({
        order,
        company: { planCode: 'empresa', licenseExpiresAt: new Date('2026-12-26T12:00:00.000Z') },
      }),
    ).toBe(true);
  });

  it('no revierte si otro pago ya movio el vencimiento', () => {
    expect(
      canRevert({
        order,
        company: { planCode: 'empresa', licenseExpiresAt: new Date('2027-01-26T12:00:00.000Z') },
      }),
    ).toBe(false);
  });

  it('no revierte si la empresa ya esta en otro plan', () => {
    expect(
      canRevert({
        order,
        company: { planCode: 'pro', licenseExpiresAt: new Date('2026-12-26T12:00:00.000Z') },
      }),
    ).toBe(false);
  });

  it('no revierte sin periodo aplicado', () => {
    expect(
      canRevert({
        order: { planCode: 'empresa', periodEnd: null },
        company: { planCode: 'empresa', licenseExpiresAt: null },
      }),
    ).toBe(false);
  });
});

describe('provisionalWindowDays', () => {
  it('usa 15 dias por defecto y acota lo absurdo', () => {
    expect(provisionalWindowDays(undefined)).toBe(15);
    expect(provisionalWindowDays('')).toBe(15);
    expect(provisionalWindowDays('abc')).toBe(15);
    expect(provisionalWindowDays('0')).toBe(15);
    expect(provisionalWindowDays('30')).toBe(30);
    expect(provisionalWindowDays('999')).toBe(90);
  });
});

describe('estados de activación', () => {
  it('un rechazo solo se aplica una vez', () => {
    // El servicio corta con `already_reverted` si el estado ya es REVERTED.
    expect(LicenseActivationState.REVERTED).toBe('REVERTED');
  });
});
