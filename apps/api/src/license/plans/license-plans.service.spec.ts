import { LicensePlansService } from './license-plans.service';

function row(overrides: Record<string, unknown>) {
  return {
    id: 'uuid',
    code: 'basico',
    name: 'FullPOS Básico',
    version: 1,
    monthlyPrice: { toString: () => '1000' },
    currency: 'DOP',
    maxUsers: 2,
    maxProducts: 100,
    maxWarehouses: 1,
    multiWarehouse: false,
    wholesale: false,
    uom: true,
    ecf: false,
    taxes: false,
    ecfMonthlyQuota: null,
    active: true,
    createdAt: new Date('2026-11-16T00:00:00Z'),
    updatedAt: new Date('2026-11-16T00:00:00Z'),
    ...overrides,
  };
}

function build(rows: unknown[]) {
  const prisma = {
    licensePlan: {
      findMany: jest.fn().mockResolvedValue(rows),
      findFirst: jest.fn().mockResolvedValue(rows[0] ?? null),
    },
  };
  const service = new LicensePlansService(prisma as never);
  return { service, prisma };
}

describe('LicensePlansService', () => {
  it('devuelve solo planes activos ordenados por precio', async () => {
    const { service, prisma } = build([row({})]);

    const result = await service.listPublic();

    expect(prisma.licensePlan.findMany).toHaveBeenCalledWith({
      where: { active: true },
      orderBy: [{ monthlyPrice: 'asc' }, { code: 'asc' }],
    });
    expect(result.plans).toHaveLength(1);
  });

  it('expone precios como texto y separa límites de funciones', async () => {
    const { service } = build([
      row({
        code: 'negocio',
        name: 'FullPOS Negocio',
        monthlyPrice: { toString: () => '2500' },
        maxUsers: 5,
        maxProducts: 400,
        maxWarehouses: 1,
        multiWarehouse: false,
        wholesale: true,
        uom: true,
        ecf: true,
        taxes: true,
        ecfMonthlyQuota: 300,
      }),
    ]);

    const { plans } = await service.listPublic();
    const plan = plans[0] as (typeof plans)[number];

    expect(plan.code).toBe('negocio');
    expect(plan.monthlyPrice).toBe('2500');
    expect(plan.limits).toEqual({ maxUsers: 5, maxProducts: 400, maxWarehouses: 1 });
    expect(plan.features).toEqual({
      multiWarehouse: false,
      wholesale: true,
      uom: true,
      ecf: true,
      taxes: true,
    });
    expect(plan.ecfMonthlyQuota).toBe(300);
  });

  it('no inventa límites: el plan básico mantiene e-CF e impuestos apagados', async () => {
    const { service } = build([row({})]);

    const { plans } = await service.listPublic();
    const plan = plans[0] as (typeof plans)[number];

    expect(plan.features.ecf).toBe(false);
    expect(plan.features.taxes).toBe(false);
    expect(plan.features.multiWarehouse).toBe(false);
    expect(plan.ecfMonthlyQuota).toBeNull();
  });

  it('normaliza el código al buscar y devuelve null si viene vacío', async () => {
    const { service, prisma } = build([row({})]);

    await service.findByCode('  NEGOCIO ');
    expect(prisma.licensePlan.findFirst).toHaveBeenCalledWith({
      where: { code: 'negocio', active: true },
    });

    await expect(service.findByCode('   ')).resolves.toBeNull();
    expect(prisma.licensePlan.findFirst).toHaveBeenCalledTimes(1);
  });
});
