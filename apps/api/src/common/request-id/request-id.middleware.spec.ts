import {
  CORRELATION_ID_HEADER,
  REQUEST_ID_HEADER,
  requestIdMiddleware,
  resolveRequestId,
  sanitizeRequestId,
} from './request-id.middleware';

const UUID_V4 = /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

function createResponseDouble() {
  const headers: Record<string, string> = {};
  return {
    headers,
    setHeader: (name: string, value: string) => {
      headers[name.toLowerCase()] = value;
    },
  };
}

describe('sanitizeRequestId', () => {
  it('acepta identificadores con charset acotado', () => {
    expect(sanitizeRequestId('req-2026.10.26:abc_123')).toBe('req-2026.10.26:abc_123');
  });

  it('rechaza valores demasiado cortos', () => {
    expect(sanitizeRequestId('abc')).toBeNull();
  });

  it('rechaza valores con espacios o caracteres de control (inyección)', () => {
    expect(sanitizeRequestId('abc defghij')).toBeNull();
    expect(sanitizeRequestId('abc\r\nX-Injected: 1')).toBeNull();
    expect(sanitizeRequestId('{"a":1}')).toBeNull();
  });

  it('rechaza tipos que no son string', () => {
    expect(sanitizeRequestId(undefined)).toBeNull();
    expect(sanitizeRequestId(12345)).toBeNull();
    expect(sanitizeRequestId({ id: 'abcdefgh' })).toBeNull();
  });

  it('usa el primer valor cuando llega un array de cabeceras', () => {
    expect(sanitizeRequestId(['abcdefgh', 'ijklmnop'])).toBe('abcdefgh');
  });
});

describe('resolveRequestId', () => {
  it('prioriza x-request-id', () => {
    expect(
      resolveRequestId({
        [REQUEST_ID_HEADER]: 'aaaaaaaa-bbbb',
        [CORRELATION_ID_HEADER]: 'cccccccc-dddd',
      }),
    ).toBe('aaaaaaaa-bbbb');
  });

  it('usa x-correlation-id si no hay x-request-id', () => {
    expect(resolveRequestId({ [CORRELATION_ID_HEADER]: 'cccccccc-dddd' })).toBe('cccccccc-dddd');
  });

  it('genera un UUID v4 cuando no hay cabecera válida', () => {
    const generated = resolveRequestId({ [REQUEST_ID_HEADER]: 'no valido con espacios' });
    expect(generated).toMatch(UUID_V4);
  });

  it('no reutiliza un identificador inválido ni lo refleja', () => {
    const generated = resolveRequestId({ [REQUEST_ID_HEADER]: '<script>alert(1)</script>' });
    expect(generated).not.toContain('script');
    expect(generated).toMatch(UUID_V4);
  });
});

describe('requestIdMiddleware', () => {
  it('propaga el identificador válido y lo devuelve en la respuesta', () => {
    const req: any = { headers: { [REQUEST_ID_HEADER]: 'aaaaaaaa-bbbb' } };
    const res = createResponseDouble();
    const next = jest.fn();

    requestIdMiddleware(req, res as any, next);

    expect(req.requestId).toBe('aaaaaaaa-bbbb');
    expect(res.headers[REQUEST_ID_HEADER]).toBe('aaaaaaaa-bbbb');
    expect(res.headers[CORRELATION_ID_HEADER]).toBe('aaaaaaaa-bbbb');
    expect(next).toHaveBeenCalledWith();
  });

  it('genera uno nuevo cuando la cabecera es inválida', () => {
    const req: any = { headers: { [REQUEST_ID_HEADER]: 'x' } };
    const res = createResponseDouble();

    requestIdMiddleware(req, res as any, jest.fn());

    expect(req.requestId).toMatch(UUID_V4);
    expect(res.headers[REQUEST_ID_HEADER]).toBe(req.requestId);
  });

  it('no copia cabeceras sensibles a la respuesta ni al identificador', () => {
    const req: any = {
      headers: {
        authorization: 'Bearer secreto',
        'x-cloud-key': 'secreto',
        cookie: 'session=secreto',
      },
    };
    const res = createResponseDouble();

    requestIdMiddleware(req, res as any, jest.fn());

    expect(Object.keys(res.headers)).toEqual(
      expect.arrayContaining([REQUEST_ID_HEADER, CORRELATION_ID_HEADER]),
    );
    expect(JSON.stringify(res.headers)).not.toContain('secreto');
  });
});
