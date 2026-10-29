import { buildFingerprint, normalizeStackFrames } from './guardian.fingerprint';

describe('Guardian fingerprint', () => {
  it('agrupa el mismo defecto aunque cambien los números de línea', () => {
    const a = buildFingerprint({
      module: 'cash',
      operation: 'closeSession',
      exceptionType: 'TimeoutError',
      stack: 'Error: timeout\n    at CashService.close (cash.service.ts:412:19)\n    at Router.handle (router.ts:88:5)',
      appVersion: '1.4.5',
    });
    const b = buildFingerprint({
      module: 'cash',
      operation: 'closeSession',
      exceptionType: 'TimeoutError',
      stack: 'Error: timeout\n    at CashService.close (cash.service.ts:455:11)\n    at Router.handle (router.ts:90:3)',
      appVersion: '1.4.9',
    });

    expect(a).toBe(b);
  });

  it('separa módulos u operaciones distintas', () => {
    const base = { exceptionType: 'TimeoutError', stack: null, appVersion: '1.4.5' };
    expect(buildFingerprint({ ...base, module: 'cash', operation: 'closeSession' })).not.toBe(
      buildFingerprint({ ...base, module: 'sales', operation: 'closeSession' }),
    );
    expect(buildFingerprint({ ...base, module: 'cash', operation: 'closeSession' })).not.toBe(
      buildFingerprint({ ...base, module: 'cash', operation: 'openSession' }),
    );
  });

  it('separa versiones mayores distintas', () => {
    const base = { module: 'cash', operation: 'close', exceptionType: 'E', stack: null };
    expect(buildFingerprint({ ...base, appVersion: '1.9.9' })).not.toBe(
      buildFingerprint({ ...base, appVersion: '2.0.0' }),
    );
  });

  it('normaliza marcos de stack y los acota a 3', () => {
    const frames = normalizeStackFrames(
      'Error: x\n    at a (f.ts:1:1)\n    at b (g.ts:2:2)\n    at c (h.ts:3:3)\n    at d (i.ts:4:4)',
    );
    expect(frames).toHaveLength(3);
    expect(frames[0]).toBe('at a');
    expect(frames[2]).toBe('at c');
  });

  it('es estable sin stack', () => {
    const input = { module: 'sync', operation: 'push', exceptionType: 'Http', stack: null, appVersion: '1.0.0' };
    expect(buildFingerprint(input)).toBe(buildFingerprint(input));
    expect(buildFingerprint(input)).toHaveLength(40);
  });
});
