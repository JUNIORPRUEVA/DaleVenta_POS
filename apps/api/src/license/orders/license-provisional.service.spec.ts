import { LicenseActivationState, LicenseStatus } from '@prisma/client';
import { LicenseProvisionalService } from './license-provisional.service';

function fakeTx(order: Record<string, unknown>, company: Record<string, unknown>) {
  const updates: Array<Record<string, unknown>> = [];
  const companyUpdates: Array<Record<string, unknown>> = [];
  const audits: Array<Record<string, unknown>> = [];
  return {
    updates,
    companyUpdates,
    audits,
    tx: {
      licensePaymentOrder: {
        findUnique: async () => order,
        update: async ({ data }: { data: Record<string, unknown> }) => {
          updates.push(data);
          return {
            id: order.id,
            activationState: data.activationState ?? order.activationState,
          };
        },
      },
      company: {
        findUnique: async () => company,
        update: async ({ data }: { data: Record<string, unknown> }) => {
          companyUpdates.push(data);
          return { id: company.id };
        },
      },
      companyLicenseAuditLog: {
        create: async ({ data }: { data: Record<string, unknown> }) => {
          audits.push(data);
          return data;
        },
      },
    } as never,
  };
}

const snapshot = {
  status: 'ACTIVE',
  licenseStatus: 'ACTIVE',
  planCode: 'empresa',
  planCatalogVersion: 1,
  plan: 'ENTERPRISE',
  licenseExpiresAt: '2026-12-01T12:00:00.000Z',
  licenseActivatedAt: '2026-10-01T12:00:00.000Z',
  licenseBlockedAt: null,
  licenseEpoch: '2026-11-17T12:00:00.000Z',
  maxUsers: 7,
  maxProducts: 5000,
  maxWarehouses: 10,
  ncfEnabled: true,
  taxEnabled: true,
  wholesalePriceListsEnabled: true,
  measurementUnitsEnabled: true,
};

describe('LicenseProvisionalService.confirm', () => {
  it('confirma sin tocar la licencia (no vuelve a sumar meses)', async () => {
    const fake = fakeTx(
      { id: 'o1', activationState: LicenseActivationState.PROVISIONAL, status: 'UNCONFIRMED', reference: 'FP-1' },
      {},
    );
    const service = new LicenseProvisionalService();
    const result = await service.confirm(fake.tx, 'o1');
    expect(result.changed).toBe(true);
    expect(result.state).toBe(LicenseActivationState.CONFIRMED);
    expect(fake.companyUpdates).toHaveLength(0);
    expect(fake.updates[0]?.provisionalUntil).toBeNull();
  });

  it('es idempotente si ya estaba confirmada', async () => {
    const fake = fakeTx(
      { id: 'o1', activationState: LicenseActivationState.CONFIRMED, status: 'SETTLED', reference: 'FP-1' },
      {},
    );
    const service = new LicenseProvisionalService();
    const result = await service.confirm(fake.tx, 'o1');
    expect(result.changed).toBe(false);
    expect(fake.updates).toHaveLength(0);
  });
});

describe('LicenseProvisionalService.revert', () => {
  it('restaura el estado anterior cuando la licencia no se ha movido', async () => {
    const fake = fakeTx(
      {
        id: 'o1',
        companyId: 'c1',
        reference: 'FP-1',
        planCode: 'empresa',
        periodEnd: new Date('2026-12-26T12:00:00.000Z'),
        activationState: LicenseActivationState.PROVISIONAL,
        licenseSnapshot: snapshot,
      },
      {
        id: 'c1',
        planCode: 'empresa',
        licenseExpiresAt: new Date('2026-12-26T12:00:00.000Z'),
        status: 'ACTIVE',
        licenseStatus: LicenseStatus.ACTIVE,
      },
    );
    const service = new LicenseProvisionalService();
    const result = await service.revert(fake.tx, { orderId: 'o1' });
    expect(result.reverted).toBe(true);
    // Vuelve al vencimiento legitimo que tenia antes de esta orden.
    expect(fake.companyUpdates[0]?.licenseExpiresAt).toEqual(
      new Date('2026-12-01T12:00:00.000Z'),
    );
    expect(fake.companyUpdates[0]?.licenseStatus).toBe(LicenseStatus.ACTIVE);
    expect(fake.audits[0]?.action).toBe('license.provisional_reverted');
  });

  it('deja la licencia vencida (no suspendida) si al revertir ya no queda periodo pagado', async () => {
    const fake = fakeTx(
      {
        id: 'o1',
        companyId: 'c1',
        reference: 'FP-1',
        planCode: 'empresa',
        periodEnd: new Date('2026-12-26T12:00:00.000Z'),
        activationState: LicenseActivationState.PROVISIONAL,
        licenseSnapshot: { ...snapshot, licenseExpiresAt: '2026-11-10T12:00:00.000Z' },
      },
      {
        id: 'c1',
        planCode: 'empresa',
        licenseExpiresAt: new Date('2026-12-26T12:00:00.000Z'),
        status: 'ACTIVE',
        licenseStatus: LicenseStatus.ACTIVE,
      },
    );
    const service = new LicenseProvisionalService();
    const result = await service.revert(fake.tx, { orderId: 'o1' });
    expect(result.reverted).toBe(true);
    expect(result.expiredNow).toBe(true);
    // La empresa **no** se suspende: queda vencida para que el cliente pueda
    // volver a entrar a Planes y pagar. Suspenderla lo dejaba fuera de la app.
    expect(fake.companyUpdates[0]?.status).toBe('ACTIVE');
    expect(fake.companyUpdates[0]?.licenseStatus).toBe(LicenseStatus.EXPIRED);
    expect(fake.companyUpdates[0]?.licenseBlockedAt).toBeNull();
  });

  it('no toca la licencia si otro pago legitimo ya la movio', async () => {
    const fake = fakeTx(
      {
        id: 'o1',
        companyId: 'c1',
        reference: 'FP-1',
        planCode: 'empresa',
        periodEnd: new Date('2026-12-26T12:00:00.000Z'),
        activationState: LicenseActivationState.PROVISIONAL,
        licenseSnapshot: snapshot,
      },
      {
        id: 'c1',
        planCode: 'empresa',
        licenseExpiresAt: new Date('2027-03-01T12:00:00.000Z'),
        status: 'ACTIVE',
        licenseStatus: LicenseStatus.ACTIVE,
      },
    );
    const service = new LicenseProvisionalService();
    const result = await service.revert(fake.tx, { orderId: 'o1' });
    expect(result.reverted).toBe(false);
    expect(result.reason).toBe('license_changed');
    expect(fake.companyUpdates).toHaveLength(0);
    expect(fake.updates[0]?.activationState).toBe(LicenseActivationState.REVERTED);
  });

  it('no revierte dos veces', async () => {
    const fake = fakeTx(
      {
        id: 'o1',
        companyId: 'c1',
        reference: 'FP-1',
        planCode: 'empresa',
        periodEnd: new Date('2026-12-26T12:00:00.000Z'),
        activationState: LicenseActivationState.REVERTED,
        licenseSnapshot: snapshot,
      },
      {},
    );
    const service = new LicenseProvisionalService();
    const result = await service.revert(fake.tx, { orderId: 'o1' });
    expect(result.reverted).toBe(false);
    expect(result.reason).toBe('already_reverted');
    expect(fake.companyUpdates).toHaveLength(0);
  });
});
