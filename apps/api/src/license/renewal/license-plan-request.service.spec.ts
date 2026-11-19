import { LicensePlanRequestStatus } from '@prisma/client';
import { LicensePlanRequestService } from './license-plan-request.service';

const user = { id: 'user-1', role: 'ADMIN', companyId: 'company-1' } as never;

function fakePrisma(input: { existing?: unknown; planCode?: string | null }) {
  const created: Array<Record<string, unknown>> = [];
  const audits: Array<Record<string, unknown>> = [];
  const tx = {
    licensePlanRequest: {
      create: async ({ data }: { data: Record<string, unknown> }) => {
        created.push(data);
        return {
          id: 'request-1',
          reference: data.reference,
          status: LicensePlanRequestStatus.OPEN,
          currentPlanCode: data.currentPlanCode ?? null,
          requestedPlanCode: data.requestedPlanCode ?? null,
          message: data.message ?? null,
          createdAt: new Date('2026-11-17T12:00:00.000Z'),
        };
      },
      findUnique: async () => null,
    },
    companyLicenseAuditLog: {
      create: async ({ data }: { data: Record<string, unknown> }) => {
        audits.push(data);
        return data;
      },
    },
  };
  return {
    created,
    audits,
    prisma: {
      company: {
        findUnique: async () => ({ planCode: input.planCode ?? 'empresa' }),
      },
      licensePlanRequest: {
        findFirst: async () => input.existing ?? null,
      },
      $transaction: async (fn: (t: unknown) => Promise<unknown>) => fn(tx),
    } as never,
  };
}

describe('LicensePlanRequestService', () => {
  it('abre un ticket con referencia y deja auditoria', async () => {
    const fake = fakePrisma({});
    const service = new LicensePlanRequestService(fake.prisma);
    const result = await service.create(user, { message: 'Necesitamos mas usuarios' });

    expect(result.reused).toBe(false);
    expect(result.request.reference).toMatch(/^SOL-\d{4}-\d{6}$/);
    expect(result.request.status).toBe('OPEN');
    expect(result.request.currentPlanCode).toBe('empresa');
    expect(fake.created).toHaveLength(1);
    expect(fake.audits[0]?.action).toBe('license.plan_upgrade_requested');
  });

  it('no duplica: si ya hay una solicitud abierta devuelve la misma', async () => {
    const existing = {
      id: 'request-9',
      reference: 'SOL-2026-000999',
      status: LicensePlanRequestStatus.OPEN,
      currentPlanCode: 'empresa',
      requestedPlanCode: null,
      message: null,
      createdAt: new Date('2026-11-10T12:00:00.000Z'),
    };
    const fake = fakePrisma({ existing });
    const service = new LicensePlanRequestService(fake.prisma);
    const result = await service.create(user, {});

    expect(result.reused).toBe(true);
    expect(result.request.reference).toBe('SOL-2026-000999');
    expect(fake.created).toHaveLength(0);
  });

  it('rechaza a un usuario que no administra la empresa', async () => {
    const fake = fakePrisma({});
    const service = new LicensePlanRequestService(fake.prisma);
    await expect(
      service.create({ id: 'u2', role: 'CAJERO', companyId: 'company-1' } as never, {}),
    ).rejects.toThrow(/propietario o un administrador/);
  });
});
