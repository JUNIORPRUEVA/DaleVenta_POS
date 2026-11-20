import { LicenseOrderStatus } from '@prisma/client';
import { LicenseRenewalService } from './license-renewal.service';

const DAY = 86_400_000;
const NOW = new Date('2026-11-17T12:00:00.000Z');

function fakePrisma(input: {
  expiresAt: Date | null;
  planCode?: string | null;
  order?: {
    status: LicenseOrderStatus;
    amount: string;
    months?: number;
  } | null;
}) {
  const planCode = input.planCode === undefined ? 'pro' : input.planCode;
  const order = input.order ?? null;
  return {
    company: {
      findUnique: async () => ({
        planCode,
        licenseStatus: 'ACTIVE',
        licenseExpiresAt: input.expiresAt,
      }),
    },
    licensePlan: {
      findUnique: async () => ({
        code: 'pro',
        name: 'Pro',
        monthlyPrice: { toNumber: () => 5000 },
        currency: 'DOP',
      }),
    },
    licensePaymentOrder: {
      findFirst: async () =>
        order
          ? {
              id: 'order-1',
              reference: 'FP-2026-000123',
              amount: { toNumber: () => Number(order.amount) },
              currency: 'DOP',
              status: order.status,
              months: order.months ?? 1,
              expiresAt: new Date(NOW.getTime() + 10 * DAY),
            }
          : null,
    },
  } as never;
}

describe('LicenseRenewalService', () => {
  it('con 9 dias para vencer expone la proxima cuota con importe y fecha', async () => {
    const service = new LicenseRenewalService(
      fakePrisma({ expiresAt: new Date(NOW.getTime() + 9 * DAY) }),
    );
    const snapshot = await service.snapshot('company-1', NOW);
    expect(snapshot.state).toBe('UPCOMING');
    expect(snapshot.daysLeft).toBe(9);
    expect(snapshot.amount).toBe(5000);
    expect(snapshot.currency).toBe('DOP');
    expect(snapshot.order).toBeNull();
  });

  it('si ya hay una orden abierta manda su importe y su referencia', async () => {
    const service = new LicenseRenewalService(
      fakePrisma({
        expiresAt: new Date(NOW.getTime() + 4 * DAY),
        order: { status: LicenseOrderStatus.AWAITING_TRANSFER, amount: '5000.00' },
      }),
    );
    const snapshot = await service.snapshot('company-1', NOW);
    expect(snapshot.state).toBe('UPCOMING');
    expect(snapshot.order?.reference).toBe('FP-2026-000123');
    expect(snapshot.amount).toBe(5000);
  });

  it('un comprobante sin verificar deja la cuota en revision, no vencida', async () => {
    const service = new LicenseRenewalService(
      fakePrisma({
        expiresAt: new Date(NOW.getTime() + 2 * DAY),
        order: { status: LicenseOrderStatus.UNCONFIRMED, amount: '5000.00' },
      }),
    );
    const snapshot = await service.snapshot('company-1', NOW);
    expect(snapshot.state).toBe('IN_REVIEW');
  });

  it('una licencia sin vencimiento no muestra cuota', async () => {
    const service = new LicenseRenewalService(
      fakePrisma({ expiresAt: null }),
    );
    const snapshot = await service.snapshot('company-1', NOW);
    expect(snapshot.state).toBe('CURRENT');
    expect(snapshot.dueDate).toBeNull();
    expect(snapshot.daysLeft).toBeNull();
  });
});
