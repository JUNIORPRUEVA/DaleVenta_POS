import { Prisma } from '@prisma/client';
import {
  describeOrderOperation,
  describeOrders,
  InvalidInsightsError,
  normalizeEvidenceInsights,
} from './license-order-insights';

const dec = (value: number) => new Prisma.Decimal(value);

describe('normalizeEvidenceInsights', () => {
  it('acepta lo que se lee del comprobante y limpia espacios', () => {
    const result = normalizeEvidenceInsights({
      receivedOn: '2026-11-17T10:00:00.000Z',
      amount: 'RD$5,000.00',
      bank: ' Banco Popular ',
      bankReference: ' 001234 ',
      confidence: 0.82,
    });
    expect(result.amount).toBe(5000);
    expect(result.bank).toBe('Banco Popular');
    expect(result.bankReference).toBe('001234');
    expect(result.confidence).toBe(0.82);
    expect(result.source).toBe('appyra-crm');
  });

  it('un comprobante sin datos legibles es valido: todo queda nulo', () => {
    const result = normalizeEvidenceInsights({});
    expect(result.amount).toBeNull();
    expect(result.bank).toBeNull();
    expect(result.receivedOn).toBeNull();
  });

  it('rechaza importes imposibles y campos desconocidos', () => {
    expect(() => normalizeEvidenceInsights({ amount: -5 })).toThrow(
      InvalidInsightsError,
    );
    expect(() => normalizeEvidenceInsights({ amount: 99_000_000 })).toThrow(
      InvalidInsightsError,
    );
    expect(() => normalizeEvidenceInsights({ approved: true })).toThrow(
      /unsupported_field/,
    );
  });

  it('rechaza fechas fuera de rango y texto con caracteres de control', () => {
    expect(() => normalizeEvidenceInsights({ receivedOn: 'ayer' })).toThrow(
      /invalid_received_on/,
    );
    expect(() =>
      normalizeEvidenceInsights({ receivedOn: '2015-01-01T00:00:00.000Z' }),
    ).toThrow(/out_of_range/);
    expect(() => normalizeEvidenceInsights({ bank: 'Popular\u0007' })).toThrow(
      /invalid_text/,
    );
  });

  it('no permite que el agente marque la orden como aprobada', () => {
    const result = normalizeEvidenceInsights({ amount: 5000, notes: 'parece ok' });
    // El resultado solo describe: no hay estado ni bandera de aprobacion.
    expect(Object.keys(result).sort()).toEqual(
      [
        'amount',
        'bank',
        'bankReference',
        'confidence',
        'notes',
        'receivedOn',
        'source',
      ].sort(),
    );
  });
});

describe('describeOrderOperation', () => {
  it('mismo plan es una renovacion sin saldo a favor', () => {
    const op = describeOrderOperation({
      companyPlanCode: 'empresa',
      companyPlanPrice: 5000,
      orderPlanCode: 'empresa',
      orderPlanPrice: 5000,
      months: 1,
      amount: 5000,
    });
    expect(op.operationType).toBe('RENEWAL');
    expect(op.creditApplied).toBe(0);
  });

  it('un plan mas caro es mejora y el saldo es lo que no se transfiere', () => {
    const op = describeOrderOperation({
      companyPlanCode: 'pro',
      companyPlanPrice: 3500,
      orderPlanCode: 'empresa',
      orderPlanPrice: 5000,
      months: 1,
      amount: 450,
    });
    expect(op.operationType).toBe('UPGRADE');
    expect(op.creditApplied).toBe(4550);
    expect(op.subtotal).toBe(5000);
  });

  it('sin plan previo es una compra', () => {
    const op = describeOrderOperation({
      companyPlanCode: null,
      companyPlanPrice: null,
      orderPlanCode: 'basico',
      orderPlanPrice: 1000,
      months: 2,
      amount: 2000,
    });
    expect(op.operationType).toBe('PURCHASE');
    expect(op.creditApplied).toBe(0);
  });
});

describe('describeOrders', () => {
  it('resuelve precios en una sola consulta para toda la bandeja', async () => {
    const findMany = jest.fn(async () => [
      { code: 'pro', monthlyPrice: dec(3500) },
      { code: 'empresa', monthlyPrice: dec(5000) },
    ]);
    const map = await describeOrders(
      { licensePlan: { findMany } } as never,
      [
        {
          id: 'o1',
          planCode: 'empresa',
          months: 1,
          amount: dec(450),
          company: { planCode: 'pro' },
        },
      ],
    );
    expect(findMany).toHaveBeenCalledTimes(1);
    expect(map.get('o1')?.operationType).toBe('UPGRADE');
    expect(map.get('o1')?.creditApplied).toBe(4550);
  });
});
