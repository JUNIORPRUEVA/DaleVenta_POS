import {
  classifyBackendFailure,
  foldForMatching,
  isBusinessRuleFailure,
  isInfrastructureFailure,
  resolveModule,
  sanitizeOperation,
} from './guardian.telemetry.classifier';

/**
 * Clasificación de fallos técnicos del backend del POS.
 *
 * Reglas que se protegen aquí (y que no pueden relajarse sin autorización):
 * - Una validación de negocio jamás se convierte en incidente.
 * - Una caída de infraestructura se clasifica SEV1 y reintentable.
 * - La ruta de telemetría no se captura a sí misma.
 * - Los identificadores de la URL no viajan a Guardian.
 */
describe('clasificación de fallos para telemetría Guardian', () => {
  it('descarta errores de validación (status < 500)', () => {
    expect(
      classifyBackendFailure({ method: 'POST', path: '/api/v1/sales', status: 400, message: 'bad request' }),
    ).toBeNull();
    expect(
      classifyBackendFailure({ method: 'GET', path: '/api/v1/products/1', status: 404, message: 'no encontrado' }),
    ).toBeNull();
    expect(
      classifyBackendFailure({ method: 'POST', path: '/api/v1/clients', status: 422, message: 'invalido' }),
    ).toBeNull();
  });

  it('descarta reglas de negocio aunque respondan 5xx', () => {
    const cases = [
      'Stock insuficiente para el producto',
      'El turno ya está cerrado',
      'No hay una caja abierta para esta terminal',
      'Crédito excedido para el cliente',
      'Registro duplicado en inventario',
    ];
    for (const message of cases) {
      expect(
        classifyBackendFailure({ method: 'POST', path: '/api/v1/sales', status: 500, message }),
      ).toBeNull();
    }
  });

  it('descarta códigos de Prisma de negocio (P2002, P2025)', () => {
    expect(
      classifyBackendFailure({ method: 'POST', path: '/api/v1/products', status: 500, prismaCode: 'P2002' }),
    ).toBeNull();
    expect(
      classifyBackendFailure({ method: 'DELETE', path: '/api/v1/products/x', status: 500, prismaCode: 'P2025' }),
    ).toBeNull();
  });

  it('clasifica una caída de base de datos como SEV1 reintentable', () => {
    const result = classifyBackendFailure({
      method: 'GET',
      path: '/api/v1/sales',
      status: 500,
      prismaCode: 'P1001',
      prismaKind: 'PrismaClientInitializationError',
      message: 'Can\'t reach database server',
    });
    expect(result).not.toBeNull();
    expect(result?.severity).toBe('SEV1');
    expect(result?.retryable).toBe(true);
    expect(result?.module).toBe('sales');
  });

  it('la infraestructura gana a un mensaje genérico de negocio', () => {
    expect(
      isInfrastructureFailure({ prismaCode: 'P1002', message: 'no existe la tabla esperada' }),
    ).toBe(true);
    const result = classifyBackendFailure({
      method: 'POST',
      path: '/api/v1/cash/close',
      status: 500,
      prismaCode: 'P1002',
      message: 'la caja ya esta cerrada',
    });
    expect(result?.severity).toBe('SEV1');
  });

  it('detecta infraestructura dentro de un error de consulta cruda (SQLSTATE)', () => {
    // Caso real de UAT: `$queryRaw` falla porque la tabla no existe y el
    // SQLSTATE viaja en el mensaje, no en `code` (Prisma lo reporta como P2010).
    const result = classifyBackendFailure({
      method: 'POST',
      path: '/auth/login',
      status: 500,
      exceptionType: 'PrismaClientKnownRequestError',
      prismaCode: 'P2010',
      message:
        'Raw query failed. Code: `42P01`. Message: `relation "users" does not exist`',
    });
    expect(result?.severity).toBe('SEV1');
    expect(result?.module).toBe('auth');
    expect(isInfrastructureFailure({ message: 'Code: `08006`. Message: connection failure' })).toBe(true);
    expect(isInfrastructureFailure({ message: 'Code: `53300`. too many clients' })).toBe(true);
  });

  it('un fallo técnico normal es SEV2 y no reintentable', () => {    const result = classifyBackendFailure({
      method: 'POST',
      path: '/api/v1/cash/close',
      status: 500,
      exceptionType: 'CashCloseError',
      message: 'No se pudo calcular el efectivo esperado',
    });
    expect(result).toMatchObject({
      module: 'cash',
      severity: 'SEV2',
      operation: 'POST /api/v1/cash/close',
      retryable: false,
    });
  });

  it('nunca captura la propia ruta de telemetría', () => {
    expect(
      classifyBackendFailure({ method: 'POST', path: '/guardian/machine/incidents', status: 500 }),
    ).toBeNull();
    expect(classifyBackendFailure({ method: 'POST', path: '/api/guardian/incidents', status: 502 })).toBeNull();
  });

  it('resuelve el módulo por ruta y por declaración explícita de tarea', () => {
    expect(resolveModule('/api/v1/cash/sessions')).toBe('cash');
    expect(resolveModule('/api/v1/products/abc')).toBe('inventory');
    expect(resolveModule('/api/v1/sync/push')).toBe('sync');
    expect(resolveModule('/api/v1/license/status')).toBe('license');
    expect(resolveModule('/api/v1/impresion/ticket')).toBe('printing');
    expect(resolveModule('/api/v1/dgii/ecf')).toBe('fiscal');
    expect(resolveModule('/jobs/network/notificationsOutboxCycle')).toBe('network');
    expect(resolveModule('/jobs/noexiste/x')).toBe('backend');
    expect(resolveModule('/api/v1/algo-desconocido')).toBe('backend');
  });

  it('normaliza la ruta sin identificadores ni query', () => {
    expect(sanitizeOperation('get', '/api/v1/products/8f14e45f-ceea-467a-9d0b-11c1a1b7c1a1?expand=all')).toBe(
      'GET /api/v1/products/:id',
    );
    expect(sanitizeOperation('post', '/api/v1/sales/1234/items?x=1')).toBe('POST /api/v1/sales/:n/items');
    expect(sanitizeOperation(undefined, undefined)).toBe('UNKNOWN /');
  });

  it('pliega acentos para comparar mensajes en español', () => {
    expect(foldForMatching('El turno ya está CERRADO')).toBe('el turno ya esta cerrado');
    expect(isBusinessRuleFailure({ message: 'El turno ya está cerrado' })).toBe(true);
  });
});
