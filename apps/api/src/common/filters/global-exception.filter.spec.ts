import { BadRequestException, HttpException, HttpStatus } from '@nestjs/common';
import { GlobalExceptionFilter } from './global-exception.filter';
import { Prisma } from '@prisma/client';

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
  it.each([
    ['NOT_ACTIVE',409,'PRODUCT_NOT_ACTIVE'],
    ['ANNULLED',409,'PRODUCT_ANNULLED'],
    ['TENANT_MISMATCH',403,'PRODUCT_COMPANY_MISMATCH'],
  ])('maps PostgreSQL lifecycle %s to a controlled response without raw SQL', (signal,status,code) => {
    const {captured,host}=createHost({method:'POST',originalUrl:'/products'});
    const error=new Prisma.PrismaClientUnknownRequestError(`Raw query failed: PRODUCT_LIFECYCLE_${signal}`,{clientVersion:'5.22.0'});
    new GlobalExceptionFilter().catch(error,host);
    expect(captured.status).toBe(status);
    expect(captured.body.code).toBe(code);
    expect(JSON.stringify(captured.body)).not.toContain('Raw query');
    expect(JSON.stringify(captured.body)).not.toContain('PRODUCT_LIFECYCLE_');
  });
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

  it.each([400, 500])('redacta credenciales en URLs del log de error %s', (status) => {
    const rawUrl = '/guardian/webhooks/whatsapp?hub.verify_token=qa-private-marker&token=qa-other-marker&page=2';
    const { captured, host } = createHost({
      method: 'GET',
      originalUrl: rawUrl,
      requestId: 'req-safe-log',
    });
    withNodeEnv('production', () => new GlobalExceptionFilter().catch(new HttpException({ message: `Cannot GET ${rawUrl}` }, status), host));
    const logged = JSON.stringify([...errorSpy.mock.calls, ...warnSpy.mock.calls]);
    expect(logged).not.toContain('qa-private-marker');
    expect(logged).not.toContain('qa-other-marker');
    expect(logged).toContain('hub.verify_token=***');
    expect(logged).toContain('page=2');
    expect(captured.status).toBe(status);
    expect(captured.body.requestId).toBe('req-safe-log');
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
