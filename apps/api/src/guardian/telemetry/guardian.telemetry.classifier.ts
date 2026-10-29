/**
 * Clasificación de fallos técnicos del backend de DaleVentas POS para Guardian.
 *
 * Objetivo: convertir un error HTTP 5xx en un incidente con módulo, severidad y
 * operación estables, y **descartar** lo que no es un defecto técnico.
 *
 * Regla de oro: una validación de negocio (stock insuficiente, duplicado, caja
 * cerrada, crédito excedido, datos inválidos) NUNCA es un incidente, aunque el
 * cliente la convierta por error en 5xx. Se detecta por codice de Prisma y por
 * patrones del mensaje, y se descarta.
 *
 * Este módulo es puro (sin Nest, sin red, sin base de datos) para poder probarlo
 * de forma determinista.
 */

export const GUARDIAN_TELEMETRY_MODULES = [
  'auth',
  'cash',
  'sales',
  'inventory',
  'sync',
  'license',
  'updater',
  'printing',
  'fiscal',
  'reporting',
  'network',
  'flutter',
  'backend',
  'unknown',
] as const;

export type GuardianTelemetryModule = (typeof GUARDIAN_TELEMETRY_MODULES)[number];
export type GuardianTelemetrySeverity = 'SEV1' | 'SEV2' | 'SEV3' | 'SEV4';

export type GuardianTelemetryInput = {
  method?: string;
  path?: string;
  status?: number;
  exceptionType?: string | null;
  message?: string | null;
  stack?: string | null;
  prismaCode?: string | null;
  prismaKind?: string | null;
};

export type GuardianTelemetryClassification = {
  module: GuardianTelemetryModule;
  severity: GuardianTelemetrySeverity;
  operation: string;
  retryable: boolean;
  /** Motivo por el que se descartó el evento (solo cuando el retorno es `null`). */
  discardedReason?: string;
};

/** Códigos de Prisma que indican negocio, no infraestructura (no son incidentes). */
const BUSINESS_PRISMA_CODES = new Set([
  'P2000', // valor demasiado largo para la columna
  'P2001', // registro no encontrado para la condición
  'P2002', // restricción única (duplicado)
  'P2003', // clave foránea
  'P2004', // restricción del motor
  'P2005', // valor inválido para el tipo
  'P2006', // valor inválido enviado
  'P2007', // error de validación de datos
  'P2011', // nulo en columna no nula
  'P2012', // valor requerido ausente
  'P2013', // argumento requerido ausente
  'P2014', // relación requerida
  'P2019', // error de entrada
  'P2020', // valor fuera de rango
  'P2025', // registro requerido no encontrado
]);

/** Códigos de Prisma que indican caída o degradación de infraestructura. */
const INFRA_PRISMA_CODES = new Set([
  'P1000', // autenticación fallida contra la base
  'P1001', // no se puede alcanzar el servidor
  'P1002', // timeout de la base
  'P1008', // timeout de operación
  'P1010', // acceso denegado
  'P1017', // el servidor cerró la conexión
  'P2024', // timeout del pool de conexiones
  'P2034', // conflicto de escritura / deadlock
  'P2021', // la tabla no existe (deriva de esquema)
  'P2022', // la columna no existe (deriva de esquema)
]);

const RETRYABLE_PRISMA_CODES = new Set(['P1001', 'P1002', 'P1008', 'P1017', 'P2024', 'P2034']);

/**
 * Mensajes que delatan una regla de negocio. Se comparan en minúsculas y sin
 * acentos para no depender de la redacción exacta del módulo que falla.
 */
const BUSINESS_MESSAGE_PATTERNS: RegExp[] = [
  /stock insuficiente/,
  /inventario insuficiente/,
  /no hay suficiente/,
  /sin existencias/,
  /ya existe/,
  /duplicad[oa]/,
  /saldo insuficiente/,
  /credito excedido/,
  /limite de credito/,
  /caja (ya )?(esta )?cerrada/,
  /no hay (una )?caja abierta/,
  /turno (ya )?(esta )?cerrado/,
  /no hay turno/,
  /cantidad invalida/,
  /precio invalido/,
  /datos invalidos/,
  /licencia (vencida|expirada|invalida)/,
];

/** Prefijos de ruta → módulo funcional. Orden: el primero que coincide gana. */
const PATH_MODULE_RULES: Array<{ test: RegExp; module: GuardianTelemetryModule }> = [
  { test: /(^|\/)(auth|login|session)(\/|$)/i, module: 'auth' },
  { test: /(^|\/)(cash|caja|turnos?|cash-sessions?)(\/|$)/i, module: 'cash' },
  { test: /(^|\/)(sales?|ventas?|invoices?|facturas?)(\/|$)/i, module: 'sales' },
  { test: /(^|\/)(inventory|inventario|products?|productos?|warehouses?|almacenes?|stock)(\/|$)/i, module: 'inventory' },
  { test: /(^|\/)(purchases?|compras?|suppliers?|proveedores?)(\/|$)/i, module: 'inventory' },
  { test: /(^|\/)(sync|offline|outbox|reconcile|reconciliacion)(\/|$)/i, module: 'sync' },
  { test: /(^|\/)(license|licencia|licensing)(\/|$)/i, module: 'license' },
  { test: /(^|\/)(updater|update|releases?)(\/|$)/i, module: 'updater' },
  { test: /(^|\/)(print|printer|printing|impresion)(\/|$)/i, module: 'printing' },
  { test: /(^|\/)(fiscal|ecf|dgii|tax|impuestos?)(\/|$)/i, module: 'fiscal' },
  { test: /(^|\/)(reports?|reportes?|contabilidad|accounting|payroll|nomina)(\/|$)/i, module: 'reporting' },
  { test: /(^|\/)(clients?|clientes?|cotizaciones?|quotes?)(\/|$)/i, module: 'sales' },
  { test: /(^|\/)(notifications?|whatsapp|meta)(\/|$)/i, module: 'network' },
  { test: /(^|\/)(backups?|maintenance|jobs?)(\/|$)/i, module: 'backend' },
];

const UUID_PATTERN = /[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/gi;
const NUMERIC_SEGMENT_PATTERN = /\/\d{2,}(?=\/|$)/g;

/** Sin acentos ni mayúsculas: comparación estable de mensajes en español. */
export function foldForMatching(value: string): string {
  return String(value ?? '')
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '')
    .toLowerCase();
}

/**
 * Normaliza la ruta a una operación estable: quita query, sustituye UUID y
 * tramos numéricos por marcadores. Evita filtrar identificadores a Guardian y
 * hace que la misma ruta agrupe siempre en la misma firma.
 */
export function sanitizeOperation(method: string | undefined, path: string | undefined): string {
  const rawPath = String(path ?? '').split('?')[0].split('#')[0];
  const verb = String(method ?? 'UNKNOWN').toUpperCase().slice(0, 10);
  const normalized = rawPath
    .replace(UUID_PATTERN, ':id')
    .replace(NUMERIC_SEGMENT_PATTERN, '/:n')
    .replace(/\/{2,}/g, '/')
    .slice(0, 80);
  return `${verb} ${normalized || '/'}`.slice(0, 80);
}

export function resolveModule(path: string | undefined): GuardianTelemetryModule {
  const rawPath = String(path ?? '');

  // Tareas de fondo: `/jobs/<modulo>/<operacion>` declara el módulo de forma
  // explícita, sin depender de la heurística de rutas HTTP.
  const jobMatch = /^\/jobs\/([a-z]+)\//i.exec(rawPath);
  if (jobMatch) {
    const declared = jobMatch[1].toLowerCase() as GuardianTelemetryModule;
    if ((GUARDIAN_TELEMETRY_MODULES as readonly string[]).includes(declared)) return declared;
  }

  for (const rule of PATH_MODULE_RULES) {
    if (rule.test.test(rawPath)) return rule.module;
  }
  return 'backend';
}

export function isBusinessRuleFailure(input: GuardianTelemetryInput): boolean {
  const code = String(input.prismaCode ?? '').trim().toUpperCase();
  if (code && BUSINESS_PRISMA_CODES.has(code)) return true;

  const folded = foldForMatching(`${input.message ?? ''} ${input.exceptionType ?? ''}`);
  return BUSINESS_MESSAGE_PATTERNS.some((pattern) => pattern.test(folded));
}

export function isInfrastructureFailure(input: GuardianTelemetryInput): boolean {
  const code = String(input.prismaCode ?? '').trim().toUpperCase();
  if (code && INFRA_PRISMA_CODES.has(code)) return true;
  const kind = foldForMatching(String(input.prismaKind ?? ''));
  if (kind.includes('initialization') || kind.includes('unable to reach')) return true;
  const message = foldForMatching(String(input.message ?? ''));
  if (/no se puede alcanzar|connection refused|econnrefused|etimedout|connect timeout|too many connections/.test(message)) {
    return true;
  }
  // `$queryRaw` y otras rutas envuelven el fallo real en el mensaje: el SQLSTATE
  // es la evidencia de infraestructura (tabla/columna ausente, conexión caída).
  return /code: `?(42p01|42703|08001|08003|08004|08006|53300|57p01|57p03)'?/.test(message);
}

/**
 * Clasifica un fallo. Devuelve `null` cuando el evento NO debe enviarse:
 * - status < 500 (validación de negocio o error de usuario),
 * - rechazo de regla de negocio aunque el módulo responda 5xx.
 */
export function classifyBackendFailure(
  input: GuardianTelemetryInput,
): GuardianTelemetryClassification | null {
  const status = Number(input.status ?? 0);
  if (!Number.isFinite(status) || status < 500) {
    return null;
  }

  const path = String(input.path ?? '');
  if (/^\/(api\/)?guardian(\/|$)/.test(path)) {
    // Nunca capturar la propia ruta de telemetría (bucle de realimentación).
    return null;
  }

  // La infraestructura tiene prioridad: una caída de base de datos no puede
  // confundirse con una regla de negocio aunque el mensaje sea genérico.
  const infra = isInfrastructureFailure(input);
  if (!infra && isBusinessRuleFailure(input)) {
    return null;
  }

  const module = resolveModule(path);
  const code = String(input.prismaCode ?? '').trim().toUpperCase();
  const severity: GuardianTelemetrySeverity = infra ? 'SEV1' : 'SEV2';
  const retryable =
    Boolean(code && RETRYABLE_PRISMA_CODES.has(code)) ||
    status === 502 ||
    status === 503 ||
    status === 504;

  return {
    module,
    severity,
    operation: sanitizeOperation(input.method, path),
    retryable: Boolean(retryable),
  };
}
