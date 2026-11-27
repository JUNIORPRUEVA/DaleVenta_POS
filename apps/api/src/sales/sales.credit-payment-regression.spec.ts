import { Prisma } from '@prisma/client';
import { SalesService } from './sales.service';

describe('credit payment financial snapshot and replay', () => {
  const user = { id: 'cashier', companyId: 'company', role: 'ADMIN' };
  const dto = { operationId: 'payment-1', operationCashSessionId: 'session', paidAt: '2026-11-26T14:00:00Z', cashAmount: 500, transferAmount: 0 };
  const existing = () => ({ saleId: 'sale', userId: user.id, cashSessionId: 'session', cashAmount: new Prisma.Decimal(500), transferAmount: new Prisma.Decimal(0), paidAt: new Date(dto.paidAt), sale: { id: 'sale' } });
  const service = (prisma: object) => new SalesService(prisma as never, { get: () => '' } as never, { emitCompany: jest.fn() } as never, {} as never);

  it('reads an original invoice only within the authenticated company', async () => {
    const prisma = { sale: { findFirst: jest.fn().mockResolvedValue({ id: 'sale', kind: 'invoice', fiscalVoucherType: 'NORMAL' }) } };
    expect((await service(prisma).getById(user as never, 'sale')).id).toBe('sale');
    expect(prisma.sale.findFirst).toHaveBeenCalledWith(expect.objectContaining({ where: { id: 'sale', companyId: user.companyId, isDeleted: false } }));
    prisma.sale.findFirst.mockResolvedValueOnce(null as never);
    await expect(service(prisma).getById({ ...user, companyId: 'other-company' } as never, 'sale')).rejects.toMatchObject({ status: 404 });
  });

  it.each([
    ['saleId', 'another-sale'], ['userId', 'another-cashier'],
    ['cashSessionId', 'another-session'], ['cashAmount', new Prisma.Decimal(501)],
    ['transferAmount', new Prisma.Decimal(1)], ['paidAt', new Date('2026-11-26T15:00:00Z')],
  ])('rejects a reused identity with different %s', async (field, value) => {
    const prisma = { saleCreditPayment: { findFirst: jest.fn().mockResolvedValue({ ...existing(), [field as string]: value }) }, $transaction: jest.fn() };
    await expect(service(prisma).addCreditPayment(user as never, 'sale', dto)).rejects.toMatchObject({ status: 409 });
    expect(prisma.$transaction).not.toHaveBeenCalled();
  });

  it('returns the original operation only for an identical retry', async () => {
    const payment = existing();
    const prisma = { saleCreditPayment: { findFirst: jest.fn().mockResolvedValue(payment) }, $transaction: jest.fn() };
    const result = await service(prisma).addCreditPayment(user as never, 'sale', dto);
    expect(result.payment).toBe(payment);
    expect(prisma.$transaction).not.toHaveBeenCalled();
  });

  it.each([0, 1])('updates only the unchanged financial snapshot (matched rows=%s)', async count => {
    const sale = { id: 'sale', isDeleted: false, creditStatus: 'open', creditBalance: new Prisma.Decimal(1500), creditPaidAmount: new Prisma.Decimal(1000), paymentCashAmount: new Prisma.Decimal(1000), paymentTransferAmount: new Prisma.Decimal(0) };
    const tx = { saleCreditPayment: { create: jest.fn().mockResolvedValue({ id: 'payment' }) }, sale: { updateMany: jest.fn().mockResolvedValue({ count }), findFirstOrThrow: jest.fn().mockResolvedValue({ ...sale, creditBalance: new Prisma.Decimal(1000) }) } };
    const prisma = { saleCreditPayment: { findFirst: jest.fn().mockResolvedValue(null) }, sale: { findFirst: jest.fn().mockResolvedValue(sale) }, $transaction: jest.fn(async callback => callback(tx)) };
    const target = service(prisma);
    // Session policy has its own tests; this isolates the write race.
    jest.spyOn(target as never, 'resolveOperationCashSession' as never).mockResolvedValue({ id: 'session' } as never);
    const result = target.addCreditPayment(user as never, 'sale', dto);
    if (count === 0) {
      await expect(result).rejects.toMatchObject({ status: 409 });
      expect(tx.sale.findFirstOrThrow).not.toHaveBeenCalled();
    } else {
      expect((await result).sale.creditBalance.toString()).toBe('1000');
    }
    expect(tx.sale.updateMany).toHaveBeenCalledWith(expect.objectContaining({
      where: expect.objectContaining({ companyId: 'company', isDeleted: false, creditBalance: sale.creditBalance, creditPaidAmount: sale.creditPaidAmount }),
      data: expect.objectContaining({ creditPaidAmount: new Prisma.Decimal(1500), creditBalance: new Prisma.Decimal(1000) }),
    }));
  });
});
