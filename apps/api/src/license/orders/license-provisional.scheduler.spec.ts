import { LicenseActivationState, LicenseOrderStatus } from '@prisma/client';
import { LicenseProvisionalScheduler } from './license-provisional.scheduler';

function fakeDeps(action: string, orders: Array<{ id: string }>) {
  const updated: Array<Record<string, unknown>> = [];
  const audits: Array<Record<string, unknown>> = [];
  const reverted: string[] = [];
  return {
    updated,
    audits,
    reverted,
    prisma: {
      licensePaymentOrder: {
        findMany: async () => orders,
        update: async ({ data }: { data: Record<string, unknown> }) => {
          updated.push(data);
          return { id: 'x' };
        },
      },
      companyLicenseAuditLog: {
        create: async ({ data }: { data: Record<string, unknown> }) => {
          audits.push(data);
          return data;
        },
      },
      $transaction: async (fn: (tx: unknown) => Promise<unknown>) => fn({}),
    } as never,
    config: {
      get: (key: string) =>
        key === 'LICENSE_PROVISIONAL_EXPIRY_ACTION' ? action : undefined,
    } as never,
    provisional: {
      revert: async (_tx: unknown, input: { orderId: string }) => {
        reverted.push(input.orderId);
        return { reverted: true, reason: 'restored' };
      },
    } as never,
  };
}

const NOW = new Date('2026-12-20T12:00:00.000Z');

describe('LicenseProvisionalScheduler', () => {
  it('por defecto no corta el servicio: marca la orden para revision', async () => {
    const deps = fakeDeps('keep', [{ id: 'o1' }, { id: 'o2' }]);
    const scheduler = new LicenseProvisionalScheduler(
      deps.prisma,
      deps.provisional,
      deps.config,
    );
    const summary = await scheduler.runCheck(NOW);
    expect(summary).toEqual({ reviewed: 2, reverted: 0, action: 'keep' });
    expect(deps.reverted).toHaveLength(0);
    expect(deps.updated.every((u) => u.activationState === LicenseActivationState.EXPIRED_REVIEW)).toBe(true);
    expect(deps.audits).toHaveLength(2);
    expect(deps.audits[0]?.action).toBe('license.provisional_expired_review');
  });

  it('con LICENSE_PROVISIONAL_EXPIRY_ACTION=revert si revoca', async () => {
    const deps = fakeDeps('revert', [{ id: 'o1' }]);
    const scheduler = new LicenseProvisionalScheduler(
      deps.prisma,
      deps.provisional,
      deps.config,
    );
    const summary = await scheduler.runCheck(NOW);
    expect(summary.reverted).toBe(1);
    expect(deps.reverted).toEqual(['o1']);
    expect(deps.updated).toHaveLength(0);
  });

  it('un valor raro vuelve al comportamiento seguro (no cortar)', async () => {
    const deps = fakeDeps('borrar-todo', [{ id: 'o1' }]);
    const scheduler = new LicenseProvisionalScheduler(
      deps.prisma,
      deps.provisional,
      deps.config,
    );
    const summary = await scheduler.runCheck(NOW);
    expect(summary.action).toBe('keep');
    expect(deps.reverted).toHaveLength(0);
  });

  it('solo mira ordenes aun sin verificar', async () => {
    let where: Record<string, unknown> = {};
    const prisma = {
      licensePaymentOrder: {
        findMany: async (args: { where: Record<string, unknown> }) => {
          where = args.where;
          return [];
        },
      },
    } as never;
    const scheduler = new LicenseProvisionalScheduler(
      prisma,
      { revert: async () => ({ reverted: false }) } as never,
      { get: () => undefined } as never,
    );
    await scheduler.runCheck(NOW);
    expect(where.activationState).toBe(LicenseActivationState.PROVISIONAL);
    expect(where.status).toEqual({
      in: [LicenseOrderStatus.UNCONFIRMED, LicenseOrderStatus.EVIDENCE_RECEIVED],
    });
  });
});
