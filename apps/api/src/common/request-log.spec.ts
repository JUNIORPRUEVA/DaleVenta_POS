import { sanitizeRequestUrl } from './request-log';

describe('sanitizeRequestUrl', () => {
  it('enmascara el verify token de la verificación de Meta', () => {
    const url =
      '/guardian/webhooks/whatsapp?hub.mode=subscribe&hub.verify_token=secreto-real&hub.challenge=12345';
    const sanitized = sanitizeRequestUrl(url);
    expect(sanitized).not.toContain('secreto-real');
    expect(sanitized).toContain('hub.verify_token=***');
    expect(sanitized).toContain('hub.mode=subscribe');
    expect(sanitized).toContain('hub.challenge=12345');
  });

  it('enmascara claves sensibles habituales sin alterar las innocuas', () => {
    const sanitized = sanitizeRequestUrl(
      '/api/x?token=abc&access_token=def&page=2&status=OPEN&secret=ghi&signature=jkl',
    );
    expect(sanitized).toBe('/api/x?token=***&access_token=***&page=2&status=OPEN&secret=***&signature=***');
  });

  it('enmascara la clave aunque llegue codificada', () => {
    const sanitized = sanitizeRequestUrl('/hook?hub.verify%5Ftoken=valor-real');
    expect(sanitized).not.toContain('valor-real');
  });

  it('enmascara parámetros sensibles sin valor', () => {
    expect(sanitizeRequestUrl('/hook?verify_token')).toBe('/hook?verify_token=***');
  });

  it('deja intactas las URLs sin query o con query vacía', () => {
    expect(sanitizeRequestUrl('/guardian/webhooks/whatsapp')).toBe('/guardian/webhooks/whatsapp');
    expect(sanitizeRequestUrl('/guardian/webhooks/whatsapp?')).toBe('/guardian/webhooks/whatsapp');
    expect(sanitizeRequestUrl(undefined)).toBe('');
    expect(sanitizeRequestUrl(null)).toBe('');
  });

  it('preserva el resto de la query tal cual, incluido el orden', () => {
    const sanitized = sanitizeRequestUrl('/a?b=1&token=x&c=3');
    expect(sanitized).toBe('/a?b=1&token=***&c=3');
  });

  // Cobertura exhaustiva: ningún parámetro sensible conocido puede sobrevivir.
  const SENSITIVE_KEYS = [
    'verify_token',
    'hub.verify_token',
    'token',
    'handoff',
    'ticket',
    'reset_token',
    'id_token',
    'access_token',
    'refresh_token',
    'api_key',
    'apikey',
    'secret',
    'client_secret',
    'password',
    'signature',
    'sig',
    'authorization',
  ];

  it.each(SENSITIVE_KEYS)('enmascara el parámetro %s', (key) => {
    const sanitized = sanitizeRequestUrl(`/hook?${key}=VALOR_UNICO_123&ok=1`);
    expect(sanitized).not.toContain('VALOR_UNICO_123');
    expect(sanitized).toContain('***');
    expect(sanitized).toContain('ok=1');
  });

  it('enmascara también con distinta capitalización', () => {
    const sanitized = sanitizeRequestUrl('/hook?Verify_Token=VALOR_UNICO_123');
    expect(sanitized).not.toContain('VALOR_UNICO_123');
  });

  it('no deja ningún secreto en una URL real de verificación de Meta', () => {
    const url =
      '/guardian/webhooks/whatsapp?hub.mode=subscribe&hub.verify_token=SECRETO_A&hub.challenge=CH_1&access_token=SECRETO_B';
    const sanitized = sanitizeRequestUrl(url);
    expect(sanitized).not.toContain('SECRETO_A');
    expect(sanitized).not.toContain('SECRETO_B');
    expect(sanitized).toContain('hub.challenge=CH_1');
    expect(sanitized).toContain('hub.mode=subscribe');
  });
});
