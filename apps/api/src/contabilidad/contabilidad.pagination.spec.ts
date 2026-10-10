import { ContabilidadService } from './contabilidad.service';

describe('ContabilidadService pagination', () => {
  const actor = {
    id: 'user-a',
    role: 'ADMIN',
    companyId: 'company-a',
  };

  function serviceWith(prisma: Record<string, unknown>) {
    return new ContabilidadService(
      prisma as never,
      {} as never,
      {} as never,
      {} as never,
    );
  }

  it('paginates deposit orders with tenant scope', async () => {
    const rows = Array.from({ length: 51 }, (_, index) => ({
      id: `deposit-${index}`,
    }));
    const prisma = {
      depositOrder: {
        findMany: jest.fn().mockResolvedValue(rows),
      },
    };
    const service = serviceWith(prisma);

    const result = await service.getDepositOrders(
      { page: '2', limit: '50', status: 'PENDING' },
      actor,
    );

    expect(result).toMatchObject({
      page: 2,
      limit: 50,
      hasMore: true,
      nextPage: 3,
    });
    expect(result.items).toHaveLength(50);
    expect(prisma.depositOrder.findMany).toHaveBeenCalledWith(
      expect.objectContaining({
        where: { companyId: actor.companyId, status: 'PENDING' },
        skip: 50,
        take: 51,
      }),
    );
  });

  it('paginates fiscal invoices with tenant scope', async () => {
    const prisma = {
      fiscalInvoice: {
        findMany: jest.fn().mockResolvedValue([]),
      },
    };
    const service = serviceWith(prisma);

    const result = await service.getFiscalInvoices(
      { page: '4', limit: '25', kind: 'SALE' },
      actor,
    );

    expect(result).toMatchObject({
      items: [],
      page: 4,
      limit: 25,
      hasMore: false,
      nextPage: null,
    });
    expect(prisma.fiscalInvoice.findMany).toHaveBeenCalledWith(
      expect.objectContaining({
        where: { companyId: actor.companyId, kind: 'SALE' },
        skip: 75,
        take: 26,
      }),
    );
  });

  it('paginates payable services with tenant scope', async () => {
    const prisma = {
      payableService: {
        findMany: jest.fn().mockResolvedValue([]),
      },
    };
    const service = serviceWith(prisma);

    const result = await service.getPayableServices(
      { page: '3', limit: '50', active: true },
      actor,
    );

    expect(result).toMatchObject({
      items: [],
      page: 3,
      limit: 50,
      hasMore: false,
      nextPage: null,
    });
    expect(prisma.payableService.findMany).toHaveBeenCalledWith(
      expect.objectContaining({
        where: { companyId: actor.companyId, active: true },
        skip: 100,
        take: 51,
      }),
    );
  });
});
