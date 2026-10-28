import { GuardianCaptureRegistry } from '../guardian.capture.registry';
import { GuardianTelemetryBridgeService } from './guardian.telemetry.bridge.service';

/**
 * Puente de telemetría: garantías que no pueden romperse.
 *
 * Estas pruebas son la red de seguridad del contrato con clientes reales:
 * si Guardian falla, tarda, no existe o responde 401, el POS no puede notarlo.
 */
describe('puente de telemetría Guardian', () => {
  const originalEnv = { ...process.env };
  const URL_OK = 'https://guardian.test/guardian/machine/incidents';
  const KEY_OK = 'gmk_0123456789abcdefghijklmnopqrstuvwxyz';
  let bridge: GuardianTelemetryBridgeService | null = null;
  let fetchMock: jest.Mock;

  const configure = (extra: Record<string, string> = {}) => {
    process.env = {
      ...originalEnv,
      GUARDIAN_TELEMETRY_ENABLED: 'true',
      GUARDIAN_TELEMETRY_URL: URL_OK,
      GUARDIAN_TELEMETRY_KEY: KEY_OK,
      GUARDIAN_TELEMETRY_INSTALL_ID: 'pos-test',
      GUARDIAN_TELEMETRY_APP_VERSION: '1.0.5',
      GUARDIAN_TELEMETRY_FLUSH_INTERVAL_MS: '60000',
      ...extra,
    };
  };

  const build = () => {
    bridge = new GuardianTelemetryBridgeService();
    bridge.onModuleInit();
    return bridge;
  };

  const okResponse = () =>
    Promise.resolve({
      ok: true,
      status: 202,
      json: async () => ({ ok: true, accepted: 1, duplicates: 0, rejected: 0 }),
    } as unknown as Response);

  beforeEach(() => {
    fetchMock = jest.fn(() => okResponse());
    (global as unknown as { fetch: unknown }).fetch = fetchMock;
  });

  afterEach(() => {
    bridge?.onModuleDestroy();
    bridge = null;
    GuardianCaptureRegistry.registerBridge(null);
    process.env = { ...originalEnv };
    jest.restoreAllMocks();
  });

  it('sin configuración no envía nada y no registra consumidor', async () => {
    process.env = { ...originalEnv, GUARDIAN_TELEMETRY_ENABLED: '' };
    const service = build();
    service.offer({ method: 'GET', path: '/api/v1/sales', status: 500, message: 'boom' });
    await service.flush();
    expect(fetchMock).not.toHaveBeenCalled();
    expect(service.snapshot().stats.received).toBe(0);
  });

  it('envía un fallo técnico real con credencial de máquina y sin datos sensibles', async () => {
    configure();
    const service = build();

    service.offer({
      method: 'POST',
      path: '/api/v1/cash/close?token=secreto',
      status: 500,
      exceptionType: 'CashCloseError',
      message: 'Fallo al cerrar turno: usuario cliente@ejemplo.com token eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxIn0.abcdefgh',
      stack: 'CashCloseError: boom\n    at CashService.close (src/cash/cash.service.ts:412:15)',
      requestId: 'req-123',
    });

    await service.flush();

    expect(fetchMock).toHaveBeenCalledTimes(1);
    const [url, init] = fetchMock.mock.calls[0] as [string, RequestInit];
    expect(url).toBe(URL_OK);
    const headers = init.headers as Record<string, string>;
    expect(headers['x-guardian-key']).toBe(KEY_OK);
    expect(headers['x-guardian-ts']).toMatch(/^\d{10}$/);

    const body = JSON.parse(String(init.body)) as { events: Array<Record<string, unknown>> };
    expect(body.events).toHaveLength(1);
    const event = body.events[0];
    expect(event.severity).toBe('SEV2');
    expect(event.module).toBe('cash');
    expect(event.operation).toBe('POST /api/v1/cash/close');
    expect(event.platform).toBe('backend');
    expect(event.appVersion).toBe('1.0.5');
    expect(event.schemaVersion).toBe(1);

    // El cuerpo NO puede contener la clave, el token, el correo ni la query.
    const serialized = JSON.stringify(body);
    expect(serialized).not.toContain(KEY_OK);
    expect(serialized).not.toContain('eyJhbGciOiJIUzI1NiJ9');
    expect(serialized).not.toContain('cliente@ejemplo.com');
    expect(serialized).not.toContain('token=secreto');

    const stats = service.snapshot().stats;
    expect(stats.accepted).toBe(1);
    expect(stats.sent).toBe(1);
  });

  it('no envía reglas de negocio aunque lleguen como 500', async () => {
    configure();
    const service = build();
    service.offer({
      method: 'POST',
      path: '/api/v1/sales',
      status: 500,
      exceptionType: 'PrismaClientKnownRequestError',
      message: 'Stock insuficiente para el producto',
      prismaCode: 'P2002',
    });
    await service.flush();
    expect(fetchMock).not.toHaveBeenCalled();
    expect(service.snapshot().stats.droppedBusinessRule).toBe(1);
  });

  it('suprime repeticiones idénticas dentro de la ventana de deduplicación', async () => {
    configure();
    const service = build();
    const input = {
      method: 'GET',
      path: '/api/v1/inventory/stock',
      status: 500,
      exceptionType: 'InventoryError',
      message: 'consistencia rota',
    };
    service.offer(input);
    service.offer(input);
    service.offer(input);
    await service.flush();
    expect(fetchMock).toHaveBeenCalledTimes(1);
    const body = JSON.parse(String((fetchMock.mock.calls[0][1] as RequestInit).body));
    expect(body.events).toHaveLength(1);
    expect(service.snapshot().stats.droppedDuplicate).toBe(2);
  });

  it('respeta la capacidad de la cola descartando el más antiguo', async () => {
    configure({ GUARDIAN_TELEMETRY_QUEUE_CAPACITY: '2', GUARDIAN_TELEMETRY_BATCH_SIZE: '10' });
    const service = build();
    for (const path of ['/api/v1/a', '/api/v1/b', '/api/v1/c']) {
      service.offer({ method: 'GET', path, status: 500, message: `fallo ${path}` });
    }
    const snapshot = service.snapshot();
    expect(snapshot.queued).toBe(2);
    expect(snapshot.stats.droppedQueueFull).toBe(1);
  });

  it('aplica el límite de caudal por minuto', async () => {
    configure({ GUARDIAN_TELEMETRY_MAX_PER_MINUTE: '1' });
    const service = build();
    service.offer({ method: 'GET', path: '/api/v1/a', status: 500, message: 'uno' });
    service.offer({ method: 'GET', path: '/api/v1/b', status: 500, message: 'dos' });
    expect(service.snapshot().stats.droppedRateLimit).toBe(1);
  });

  it('aplica muestreo cuando la tasa es cero', async () => {
    configure({ GUARDIAN_TELEMETRY_SAMPLE_RATE: '0' });
    const service = build();
    service.offer({ method: 'GET', path: '/api/v1/a', status: 500, message: 'uno' });
    expect(service.snapshot().stats.droppedSample).toBe(1);
  });

  it('no propaga errores cuando Guardian está caído (fail-open)', async () => {
    configure();
    fetchMock.mockImplementation(() => Promise.reject(new Error('ECONNREFUSED')));
    const service = build();

    expect(() =>
      service.offer({ method: 'GET', path: '/api/v1/sales', status: 500, message: 'boom' }),
    ).not.toThrow();

    await expect(service.flush()).resolves.toBeUndefined();
    const stats = service.snapshot().stats;
    expect(stats.droppedAfterAttempts).toBe(1);
    expect(stats.failedAttempts).toBeGreaterThanOrEqual(1);
    expect(stats.lastError).toContain('ECONNREFUSED');
  });

  it('no reintenta credenciales rechazadas (401) y cuenta el rechazo', async () => {
    configure({ GUARDIAN_TELEMETRY_MAX_ATTEMPTS: '3' });
    fetchMock.mockImplementation(() =>
      Promise.resolve({ ok: false, status: 401, json: async () => ({}) } as unknown as Response),
    );
    const service = build();
    service.offer({ method: 'GET', path: '/api/v1/sales', status: 500, message: 'boom' });
    await service.flush();
    expect(fetchMock).toHaveBeenCalledTimes(1);
    const stats = service.snapshot().stats;
    expect(stats.rejectedRemote).toBe(1);
    expect(stats.droppedAfterAttempts).toBe(0);
  });

  it('aborta la petición por timeout sin lanzar', async () => {
    configure({ GUARDIAN_TELEMETRY_TIMEOUT_MS: '200', GUARDIAN_TELEMETRY_MAX_ATTEMPTS: '1' });
    fetchMock.mockImplementation(
      () =>
        new Promise((_resolve, reject) => {
          const error = new Error('aborted');
          error.name = 'AbortError';
          setTimeout(() => reject(error), 10);
        }),
    );
    const service = build();
    service.offer({ method: 'GET', path: '/api/v1/sales', status: 500, message: 'boom' });
    await expect(service.flush()).resolves.toBeUndefined();
    expect(service.snapshot().stats.droppedAfterAttempts).toBe(1);
  });

  it('no envía nada cuando la cola está vacía', async () => {
    configure();
    const service = build();
    await service.flush();
    expect(fetchMock).not.toHaveBeenCalled();
  });

  it('el registro alimenta el puente sin romper la captura local existente', () => {
    configure();
    const service = build();
    const localHandler = jest.fn();
    GuardianCaptureRegistry.register(localHandler);

    GuardianCaptureRegistry.capture({
      method: 'GET',
      path: '/api/v1/sales',
      status: 500,
      message: 'boom',
    });

    expect(localHandler).toHaveBeenCalledTimes(1);
    expect(service.snapshot().stats.received).toBe(1);
  });
});
