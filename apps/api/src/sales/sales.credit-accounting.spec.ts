import { Prisma } from '@prisma/client';
import { SalesService } from './sales.service';

describe('credit accounting with a real initial payment', () => {
  const service = new SalesService({} as never, {} as never, {} as never, {} as never);
  const dec = (value: number) => new Prisma.Decimal(value);
  function original(paid = 1000, balance = 1500) {
    return { paymentMethod: 'credit', totalSold: dec(2500),
      paymentCashAmount: dec(paid), paymentTransferAmount: dec(0),
      creditAmount: dec(1500), creditPaidAmount: dec(paid), creditBalance: dec(balance) };
  }
  const allocate = (sale: ReturnType<typeof original>, amount: number) =>
    (service as any).allocateRefundPayment(sale, dec(-amount));

  it('uses the persisted normalization: initial 1000, financed balance 1500', () => {
    const payment = (service as any).normalizeSalePayment({ paymentMethod: 'credit', paymentCashAmount: 1000, paymentTransferAmount: 0 }, dec(2500));
    expect(payment.creditAmount.toString()).toBe('1500');
    expect(payment.paidAmount.toString()).toBe('1000');
    expect(payment.creditBalance.toString()).toBe('1500');
  });
  it('never refunds two cents when a one-cent return is split between channels', () => {
    const result = allocate({ ...original(0.02,0), totalSold: dec(0.02), creditAmount: dec(0.02), paymentCashAmount: dec(0.01), paymentTransferAmount: dec(0.01) },0.01);
    expect(result.paymentCashAmount.plus(result.paymentTransferAmount).toString()).toBe('-0.01');
    expect(result.originalCreditUpdate.creditPaidAmount.toString()).toBe('0.01');
  });
  it.each([
    [1000,1500,500,1000,1000,0,'open'],
    [1500,1000,500,1500,500,0,'open'],
    [1000,1500,1500,1000,0,0,'paid'],
    [1000,1500,2000,500,0,-500,'paid'],
    [1000,1500,2500,0,0,-1000,'none'],
    [2500,0,500,2000,0,-500,'paid'],
  ])('paid %s + debt %s, return %s preserves remaining paid %s and debt %s',
    (paid,balance,returned,nextPaid,nextBalance,cash,status) => {
      const result = allocate(original(paid as number,balance as number),returned as number);
      expect(result.paymentCashAmount.toString()).toBe(String(cash));
      expect(result.originalCreditUpdate.creditPaidAmount.toString()).toBe(String(nextPaid));
      expect(result.originalCreditUpdate.creditBalance.toString()).toBe(String(nextBalance));
      expect(result.originalCreditUpdate.creditStatus).toBe(status);
      expect(result.originalCreditUpdate.creditPaidAmount.plus(result.originalCreditUpdate.creditBalance).toNumber()).toBe((paid as number)+(balance as number)-(returned as number));
    });
});
