import {
  canAcceptEvidence,
  evaluateEvidence,
} from './license-evidence.validation';

const base = {
  mime: 'image/png',
  sizeBytes: 120_000,
  order: { amount: 5000, months: 1, planActive: true },
  companyActive: true,
  now: new Date('2026-11-17T12:00:00.000Z'),
};

describe('evaluateEvidence', () => {
  it('con el comprobante sano deja activar', () => {
    const result = evaluateEvidence(base);
    expect(result.passed).toBe(true);
    expect(result.analysis).toBe('PENDING');
    expect(result.score).toBeGreaterThan(0.9);
    expect(result.validatedAt).toBe('2026-11-17T12:00:00.000Z');
  });

  it('un tipo de archivo no permitido no activa', () => {
    const result = evaluateEvidence({ ...base, mime: 'application/zip' });
    expect(result.passed).toBe(false);
    expect(result.checks.find((c) => c.code === 'EVIDENCE_TYPE')?.ok).toBe(false);
  });

  it('un archivo demasiado grande no activa', () => {
    const result = evaluateEvidence({ ...base, sizeBytes: 99_000_000 });
    expect(result.passed).toBe(false);
  });

  it('un plan apagado o una empresa suspendida no activan', () => {
    expect(
      evaluateEvidence({
        ...base,
        order: { ...base.order, planActive: false },
      }).passed,
    ).toBe(false);
    expect(evaluateEvidence({ ...base, companyActive: false }).passed).toBe(false);
  });

  it('importe leido igual al de la orden: coincide', () => {
    const result = evaluateEvidence({
      ...base,
      extracted: { amount: 5000 },
    });
    expect(result.analysis).toBe('MATCH');
    expect(result.passed).toBe(true);
  });

  it('importe leido distinto: no se activa y queda como discrepancia', () => {
    const result = evaluateEvidence({
      ...base,
      extracted: { amount: 3500 },
    });
    expect(result.analysis).toBe('MISMATCH');
    expect(result.passed).toBe(false);
    expect(result.extractedAmount).toBe(3500);
  });

  it('sin lectura del comprobante solo bloquea si la politica lo exige', () => {
    expect(evaluateEvidence({ ...base, requireAnalysis: false }).passed).toBe(true);
    const strict = evaluateEvidence({ ...base, requireAnalysis: true });
    expect(strict.passed).toBe(false);
    expect(strict.checks.some((c) => c.code === 'ANALYSIS_AVAILABLE' && !c.ok)).toBe(
      true,
    );
  });
});

describe('canAcceptEvidence', () => {
  it('acepta solo ordenes abiertas', () => {
    expect(canAcceptEvidence('AWAITING_TRANSFER', 'NONE').ok).toBe(true);
    expect(canAcceptEvidence('CREATED', 'NONE').ok).toBe(true);
    expect(canAcceptEvidence('AWAITING_TRANSFER', 'REVERTED').code).toBe(
      'ORDER_ALREADY_REVIEWED',
    );
    expect(canAcceptEvidence('REJECTED', 'REVERTED').code).toBe('ORDER_REJECTED');
    expect(canAcceptEvidence('UNCONFIRMED', 'PROVISIONAL').ok).toBe(false);
    expect(canAcceptEvidence('SETTLED', 'CONFIRMED').ok).toBe(false);
  });
});
