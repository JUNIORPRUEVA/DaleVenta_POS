import {
  containsSensitiveData,
  redactContext,
  redactText,
  sanitizeHeaders,
} from './guardian.redaction';

describe('Guardian redaction', () => {
  it('elimina credenciales del texto libre', () => {
    const raw = 'Authorization: Bearer eyJhbGciOiJI.eyJzdWIiOiIxMjM0NTY3.SflKxwRJSMeKKF2QT4fwpMeJf36POk6yJV_adQssw5c';
    const clean = redactText(raw);
    expect(clean).not.toContain('eyJhbGciOiJI');
    expect(clean).toContain('[token]');
  });

  it('elimina correos y números largos', () => {
    const clean = redactText('cliente juan.perez@example.com pago 8095551234');
    expect(clean).not.toContain('juan.perez@example.com');
    expect(clean).not.toContain('8095551234');
    expect(clean).toContain('[email]');
    expect(clean).toContain('[numero]');
  });

  it('normaliza rutas absolutas del equipo del cliente', () => {
    const clean = redactText('fallo en C:\\Users\\Antonio\\AppData\\Roaming\\FullPOS\\db.sqlite y /home/user/app/main.dart');
    expect(clean).not.toContain('Antonio');
    expect(clean).not.toContain('/home/user');
    expect(clean).toContain('<ruta>');
  });

  it('redacta claves sensibles de un contexto anidado', () => {
    const clean = redactContext({
      saleId: 'abc',
      user: { email: 'a@b.com', password: 'secreto', rnc: '131-12345-6' },
      token: 'jwt-value',
      nested: { deep: { creditCard: '4111111111111111' } },
    }) as Record<string, any>;

    expect(clean.saleId).toBe('abc');
    expect(clean.user.password).toBe('[redacted]');
    expect(clean.user.email).toBe('[redacted]');
    expect(clean.token).toBe('[redacted]');
    expect(JSON.stringify(clean)).not.toContain('4111111111111111');
  });

  it('redacta credenciales embebidas en el texto del error', () => {
    // Caso detectado en UAT: los errores de ORM arrastran parámetros de la
    // sentencia y ahí viajaba una contraseña en claro.
    const raw =
      'Fallo con usuario cliente@ejemplo.com y token eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0In0.abcdefghijkl ' +
      'password=SuperSecreta1 clave: 0traClave token=abc123 api_key=xyz789';

    const clean = redactText(raw);
    expect(clean).not.toContain('SuperSecreta1');
    expect(clean).not.toContain('0traClave');
    expect(clean).not.toContain('abc123');
    expect(clean).not.toContain('xyz789');
    expect(clean).not.toContain('cliente@ejemplo.com');
    expect(clean).toContain('[redacted]');
    expect(clean).toContain('[email]');
    expect(clean).toContain('[token]');
  });

  it('acota profundidad, claves y longitud', () => {
    const deep = { a: { b: { c: { d: 'muy profundo' } } } };
    const clean = redactContext(deep) as any;
    expect(clean.a.b.c).toEqual({});

    const wide: Record<string, number> = {};
    for (let i = 0; i < 80; i += 1) wide[`k${i}`] = i;
    expect(Object.keys(redactContext(wide) as object)).toHaveLength(40);

    expect((redactContext({ long: 'x'.repeat(900) }) as any).long.length).toBe(500);
  });

  it('solo conserva cabeceras permitidas y nunca auth/cookies', () => {
    const headers = sanitizeHeaders({
      authorization: 'Bearer secreto',
      cookie: 'session=secreto',
      'user-agent': 'Dart/3.5 (dart:io)',
      'x-cloud-key': 'secreto',
      'x-client-platform': 'windows',
    });

    expect(headers).toHaveProperty('user-agent');
    expect(headers).toHaveProperty('x-client-platform');
    expect(JSON.stringify(headers)).not.toContain('secreto');
  });

  it('detecta datos sensibles residuales', () => {
    expect(containsSensitiveData('{"password":"abc12345"}')).toBe(true);
    expect(containsSensitiveData('{"token":"eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxIn0.abcd"}')).toBe(true);
    expect(containsSensitiveData('cliente a@b.com')).toBe(true);
    expect(containsSensitiveData('{"saleId":"123"}')).toBe(false);
  });
});
