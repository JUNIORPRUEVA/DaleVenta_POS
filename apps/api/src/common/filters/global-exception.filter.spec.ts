import { BadRequestException, HttpException, HttpStatus } from '@nestjs/common';
import { GlobalExceptionFilter } from './global-exception.filter';

function createHost(req: Record<string, unknown>) {
  const captured: { status?: number; body?: any } = {};
  const res = {
    status(code: number) {
      captured.status = code;
      return this;
    },
    json(body: any) {
      captured.body = body;
      return this;
    },
  };
  return {
    captured,
    host: {
      switchToHttp: () => ({
        getRequest: () => req,
        getResponse: () => res,
      }),
    } as any,
  };
}

describe('GlobalExceptionFilter — correlación y respuesta segura', () => {
  let errorSpy: jest.SpyInstance;
  let warnSpy: jest.SpyInstance;

  function withNodeEnv<T>(value: string, fn: () => T): T {
    const previous = process.env.NODE_ENV;
    process.env.NODE_ENV = value;
    try {
      return fn();
    } finally {
      if (previous === undefined) delete process.env.NODE_ENV;
      else process.env.NODE_ENV = previous;
    }
  }

  beforeEach(() => {
    errorSpy = jest.spyOn(console, 'error').mockImplementation(() => undefined);
    warnSpy = jest.spyOn(console, 'warn').mockImplementation(() => undefined);
  });

  afterEach(() => {
    errorSpy.mockRestore();
    warnSpy.mockRestore();
  });

  it('incluye el requestId en el log y en la respuesta de un 500', () => {
    const { captured, host } = createHost({
      method: 'POST',
      originalUrl: '/sales',
      requestId: 'req-abc-123456',
    });

    withNodeEnv('production', () =>
      new GlobalExceptionFilter().catch(new Error('fallo interno'), host),
    );

    expect(captured.status).toBe(HttpStatus.INTERNAL_SERVER_ERROR);
    expect(captured.body.requestId).toBe('req-abc-123456');
    expect(captured.body.message).toBe('Error interno del servidor');
    expect(errorSpy).toHaveBeenCalledTimes(1);
    const logged = JSON.stringify(errorSpy.mock.calls[0]);
    expect(logged).toContain('req-abc-123456');
    expect(logged).toContain('fallo interno');
  });

  it('en producción no expone stack ni detalles internos', () => {
    const { captured, host } = createHost({
      method: 'GET',
      url: '/cash',
      requestId: 'req-abc-123456',
    });

    const error = new Error('boom');
    error.stack = 'Error: boom\n    at interno (/app/privado.ts:1:1)';
    withNodeEnv('production', () => new GlobalExceptionFilter().catch(error, host));

    expect(captured.body.stack).toBeUndefined();
    expect(JSON.stringify(captured.body)).not.toContain('/app/privado.ts');
    expect(JSON.stringify(captured.body)).not.toContain('authorization');
  });

  it('fuera de producción conserva el comportamiento actual (stack disponible para diagnóstico)', () => {
    const { captured, host } = createHost({ method: 'GET', url: '/cash' });

    withNodeEnv('development', () =>
      new GlobalExceptionFilter().catch(new Error('boom'), host),
    );

    expect(captured.body.stack).toContain('boom');
  });

  it('conserva el payload de una HttpException y añade el requestId', () => {
    const { captured, host } = createHost({
      method: 'POST',
      originalUrl: '/sales',
      requestId: 'req-abc-123456',
    });

    new GlobalExceptionFilter().catch(
      new BadRequestException({ message: 'Datos inválidos', errorCode: 'VALIDATION_ERROR' }),
      host,
    );

    expect(captured.status).toBe(HttpStatus.BAD_REQUEST);
    expect(captured.body.message).toBe('Datos inválidos');
    expect(captured.body.errorCode).toBe('VALIDATION_ERROR');
    expect(captured.body.requestId).toBe('req-abc-123456');
    expect(warnSpy).toHaveBeenCalledTimes(1);
  });

  it('no añade el campo requestId si la petición no fue correlacionada', () => {
    const { captured, host } = createHost({ method: 'GET', url: '/health' });

    new GlobalExceptionFilter().catch(new HttpException('no', 418), host);

    expect(captured.body).not.toHaveProperty('requestId');
  });
});
