import {
  describeListenFailure,
  listenErrorCode,
  shouldFallbackToIpv4,
} from './listen-host';

/**
 * Regresión del defecto de doble instancia: el fallback IPv6 → IPv4 se aplicaba
 * también con EADDRINUSE, de modo que un segundo proceso "arrancaba" en IPv4
 * mientras el primero seguía en IPv6 y ambos servían el mismo puerto.
 */
describe('listen-host — fallback de host', () => {
  const withCode = (code: string) => Object.assign(new Error(`fallo ${code}`), { code });

  it('un puerto ocupado NO se reintenta en IPv4 (evita dos instancias)', () => {
    expect(shouldFallbackToIpv4(withCode('EADDRINUSE'))).toBe(false);
  });

  it('permisos insuficientes tampoco se reintentan', () => {
    expect(shouldFallbackToIpv4(withCode('EACCES'))).toBe(false);
  });

  it('una pila IPv6 no disponible SÍ cae a IPv4', () => {
    expect(shouldFallbackToIpv4(withCode('EAFNOSUPPORT'))).toBe(true);
    expect(shouldFallbackToIpv4(withCode('EADDRNOTAVAIL'))).toBe(true);
  });

  it('un error sin código de sistema no provoca fallback', () => {
    expect(shouldFallbackToIpv4(new Error('sin code'))).toBe(false);
    expect(shouldFallbackToIpv4(undefined)).toBe(false);
    expect(shouldFallbackToIpv4('texto')).toBe(false);
    expect(shouldFallbackToIpv4({ code: 42 })).toBe(false);
  });

  it('extrae el código cuando existe', () => {
    expect(listenErrorCode(withCode('EADDRINUSE'))).toBe('EADDRINUSE');
    expect(listenErrorCode(null)).toBeNull();
  });

  it('el mensaje de puerto ocupado explica la causa sin filtrar datos', () => {
    const message = describeListenFailure(4010, '::', withCode('EADDRINUSE'));
    expect(message).toContain('4010');
    expect(message).toContain('ya está en uso');
    expect(message).toMatch(/otra instancia/i);
  });

  it('otros errores se describen con host y puerto', () => {
    const message = describeListenFailure(4010, '0.0.0.0', withCode('EAFNOSUPPORT'));
    expect(message).toContain('0.0.0.0:4010');
    expect(message).toContain('EAFNOSUPPORT');
  });

  it('regresión: los cuatro códigos de familia y los dos fatales no se solapan', () => {
    const family = ['EAFNOSUPPORT', 'EADDRNOTAVAIL', 'EPROTONOSUPPORT', 'ENOTFOUND'];
    const fatal = ['EADDRINUSE', 'EACCES'];
    for (const code of family) expect(shouldFallbackToIpv4(withCode(code))).toBe(true);
    for (const code of fatal) expect(shouldFallbackToIpv4(withCode(code))).toBe(false);
  });
});
