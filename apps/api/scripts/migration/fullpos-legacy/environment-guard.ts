/**
 * Hard environment guards for the migration execute path.
 *
 * Two independent layers, because a CLI flag alone must never be trusted:
 *
 *  1. URL layer  - reuses the project's sanctioned gate `assertSafeUatEnvironment`
 *                  (src/common/uat-safety.ts): protected database names, expected
 *                  local UAT database name, loopback-only hosts, known remote
 *                  production infrastructure patterns.
 *  2. LIVE layer - verifies the ACTUAL PostgreSQL connection metadata
 *                  (`current_database()`, `inet_server_addr()`, `inet_server_port()`)
 *                  so a connection that resolves anywhere else is refused even if the
 *                  environment variables look correct.
 *
 * `--environment=production` always aborts: production execution is not implemented.
 */

import { assertSafeUatEnvironment } from '../../../src/common/uat-safety';
import { EXPECTED_SOURCE_SHA256, TARGET_COMPANY_ID, TARGET_WAREHOUSE_ID } from './constants';
import { MigrationAbortError } from './errors';

/** Databases that must never receive migration writes. */
export const PROTECTED_DATABASE_NAMES = ['daleventa', 'daleventa_pos'];

/** Known production hosts (host name fragments or literal addresses). */
export const PROTECTED_HOST_PATTERNS: RegExp[] = [
  /31\.97\.99\.70/,
  /easypanel/i,
  /gcdndd/i,
  /hostinger/i,
];

export type EnvironmentClass = 'uat' | 'production' | 'unknown';

export type ParsedDatabaseUrl = {
  host: string;
  port: string;
  database: string;
  user: string;
  isLoopback: boolean;
  isProtectedHost: boolean;
  isProtectedDatabase: boolean;
};

export type LiveDatabaseMetadata = {
  databaseName: string;
  serverAddress: string | null;
  serverPort: number | null;
  serverVersion: string;
  currentUser: string;
};

export function parseDatabaseUrl(rawUrl: string): ParsedDatabaseUrl {
  let parsed: URL;
  try {
    parsed = new URL(rawUrl);
  } catch {
    throw new MigrationAbortError('DATABASE_URL_INVALID', 'DATABASE_URL no es una URL válida', {});
  }
  const database = parsed.pathname.replace(/^\/+/, '').split('?')[0];
  const host = parsed.hostname.toLowerCase();
  const isLoopback = ['localhost', '127.0.0.1', '::1', '[::1]'].includes(host);
  return {
    host,
    port: parsed.port || '5432',
    database,
    user: decodeURIComponent(parsed.username || ''),
    isLoopback,
    isProtectedHost: PROTECTED_HOST_PATTERNS.some((pattern) => pattern.test(rawUrl)),
    isProtectedDatabase: PROTECTED_DATABASE_NAMES.includes(database.toLowerCase()),
  };
}

/** Sanitized description safe to print/log (never includes credentials). */
export function describeDatabaseUrl(rawUrl: string): string {
  const parsed = parseDatabaseUrl(rawUrl);
  return `${parsed.user}@${parsed.host}:${parsed.port}/${parsed.database}`;
}

export function classifyEnvironment(params: {
  environment: string;
  url: string;
  metadata?: LiveDatabaseMetadata | null;
}): { classification: EnvironmentClass; reasons: string[] } {
  const reasons: string[] = [];
  const parsed = parseDatabaseUrl(params.url);
  const requested = params.environment.trim().toLowerCase();

  if (requested === 'production') {
    return { classification: 'production', reasons: ['--environment=production'] };
  }

  const liveDatabase = params.metadata?.databaseName?.toLowerCase();
  if (liveDatabase && PROTECTED_DATABASE_NAMES.includes(liveDatabase)) {
    reasons.push(`live database "${params.metadata?.databaseName}" is protected`);
  }
  if (parsed.isProtectedDatabase) {
    reasons.push(`DATABASE_URL database "${parsed.database}" is protected`);
  }
  if (parsed.isProtectedHost) {
    reasons.push('DATABASE_URL matches known production infrastructure');
  }
  if (reasons.length > 0) {
    return { classification: 'production', reasons };
  }

  const isLocal = parsed.isLoopback;
  const hasUatName = /uat/i.test(parsed.database);
  if (liveDatabase && !/uat/i.test(liveDatabase)) {
    reasons.push(`live database "${params.metadata?.databaseName}" does not look like UAT`);
  }
  if (!isLocal) reasons.push(`host "${parsed.host}" is not loopback`);
  if (!hasUatName) reasons.push(`database "${parsed.database}" does not look like UAT`);

  if (reasons.length > 0) {
    return { classification: 'unknown', reasons };
  }
  return { classification: 'uat', reasons: [] };
}

/**
 * Pre-connection gate: validates the DESTINATION URL before any socket is opened, so a
 * production-looking destination can never even receive a connection attempt.
 */
export function assertUrlIsLocalUat(url: string): ParsedDatabaseUrl {
  const parsed = parseDatabaseUrl(url);
  const reasons: string[] = [];

  if (parsed.isProtectedDatabase) reasons.push(`protected database "${parsed.database}"`);
  if (parsed.isProtectedHost) reasons.push('URL matches known production infrastructure');
  if (reasons.length > 0) {
    throw new MigrationAbortError(
      'PRODUCTION_FORBIDDEN',
      'El destino es producción o infraestructura de producción: no se abre ninguna conexión',
      { reasons },
    );
  }

  if (!parsed.isLoopback) reasons.push(`host "${parsed.host}" is not loopback`);
  if (!/uat/i.test(parsed.database)) reasons.push(`database "${parsed.database}" does not look like UAT`);
  if (reasons.length > 0) {
    throw new MigrationAbortError(
      'ENVIRONMENT_NOT_VERIFIED',
      'El destino no es una base UAT local desechable: no se abre ninguna conexión',
      { reasons },
    );
  }

  return parsed;
}

/* ------------------------------------------------------------------ */
/* PRODUCTION CUTOVER PROFILE (prepared, not executed by default)     */
/* ------------------------------------------------------------------ */

/** The only production database the cutover profile may target. */
export const PRODUCTION_DATABASE_NAME = 'daleventa';

/** Known production hosts for the cutover destination (host name or literal address). */
export const PRODUCTION_HOST_PATTERNS: RegExp[] = [
  /31\.97\.99\.70/,
  /easypanel/i,
  /gcdndd/i,
];

/**
 * Local port reserved for the controlled SSH tunnel to production. The tunnel endpoint is
 * the production host's own loopback (`ssh -L 15432:127.0.0.1:25432 root@31.97.99.70`),
 * so the route is: `127.0.0.1:<this port>` -> ssh -> `127.0.0.1:25432` on the host ->
 * the database container's 5432. Nothing is exposed publicly by this route.
 */
export const PRODUCTION_TUNNEL_LOCAL_PORT = 15432;

/** The real server port on the far side of the tunnel (must NOT be the tunnel local port). */
export const PRODUCTION_SERVER_PORT = 5432;

/**
 * Explicit confirmation token for the final cutover. It is derived from the LOCKED
 * company id and the FROZEN source SHA, so it cannot be produced by a run that works
 * on a different source or target. It is NOT a secret: it is a deliberate, reviewable
 * confirmation that the operator must type.
 */
export function productionCutoverConfirmationToken(): string {
  return `CUTOVER:${TARGET_COMPANY_ID}:${EXPECTED_SOURCE_SHA256}`;
}

/**
 * Pre-connection gate for the production profile: the URL must point to the known
 * production database either directly (known production host) or through the controlled
 * SSH tunnel (loopback + the declared tunnel port + the explicit tunnel flag).
 *
 * A plain localhost URL is NEVER sufficient: the tunnel flag, the reserved tunnel port and
 * (later) the live metadata check are all mandatory.
 */
export function assertUrlIsProductionTarget(
  url: string,
  options: { sshTunnel?: boolean; tunnelLocalPort?: number } = {},
): ParsedDatabaseUrl {
  const parsed = parseDatabaseUrl(url);
  const reasons: string[] = [];

  if (parsed.database.toLowerCase() !== PRODUCTION_DATABASE_NAME) {
    reasons.push(`database "${parsed.database}" is not "${PRODUCTION_DATABASE_NAME}"`);
  }

  if (options.sshTunnel) {
    const expectedPort = String(options.tunnelLocalPort ?? PRODUCTION_TUNNEL_LOCAL_PORT);
    if (!parsed.isLoopback) {
      reasons.push(`tunnel route must be loopback, got "${parsed.host}"`);
    }
    if (parsed.port !== expectedPort) {
      reasons.push(`tunnel route must use the declared local port ${expectedPort}, got ${parsed.port}`);
    }
    if (reasons.length > 0) {
      throw new MigrationAbortError(
        'PRODUCTION_TUNNEL_NOT_ALLOWED',
        'La ruta de túnel SSH declarada no coincide con el túnel autorizado: no se abre ninguna conexión',
        { reasons },
      );
    }
    return parsed;
  }

  if (!PRODUCTION_HOST_PATTERNS.some((pattern) => pattern.test(url))) {
    reasons.push(`host "${parsed.host}" is not a known production host`);
    reasons.push('if production is reachable only through a tunnel, pass --production-via-ssh-tunnel');
  }
  if (reasons.length > 0) {
    throw new MigrationAbortError(
      'PRODUCTION_TARGET_NOT_ALLOWED',
      'El destino declarado como producción no coincide con la base/host de producción conocidos: no se abre ninguna conexión',
      { reasons },
    );
  }
  return parsed;
}

/**
 * Full production gate. `--environment=production` alone is NEVER enough: the live
 * connection must be the known production database AND the explicit cutover token must
 * match the locked company + frozen source SHA, AND the target ids must be the locked ones.
 */
export function assertProductionCutoverEnvironment(params: {
  environment: string;
  url: string;
  metadata: LiveDatabaseMetadata;
  confirmationToken: string | null;
  targetCompanyId: string | null;
  targetWarehouseId: string | null;
  sshTunnel?: boolean;
  tunnelLocalPort?: number;
}): { classification: EnvironmentClass; description: string; route: 'DIRECT' | 'SSH_TUNNEL' } {
  const requested = params.environment.trim().toLowerCase();
  if (requested !== 'production' && requested !== 'prod') {
    throw new MigrationAbortError(
      'ENVIRONMENT_NOT_PRODUCTION',
      'El perfil de cutover exige --environment=production',
      { requested },
    );
  }

  // Layer 0: never open a socket anywhere but the authorized production route.
  assertUrlIsProductionTarget(params.url, {
    sshTunnel: params.sshTunnel === true,
    tunnelLocalPort: params.tunnelLocalPort,
  });

  const expectedToken = productionCutoverConfirmationToken();
  if (!params.confirmationToken || params.confirmationToken.trim() !== expectedToken) {
    throw new MigrationAbortError(
      'PRODUCTION_CUTOVER_NOT_CONFIRMED',
      'Falta la confirmación explícita del cutover final (--confirm-production-cutover)',
      { requiredTokenFormat: expectedToken },
    );
  }

  if ((params.targetCompanyId ?? '').trim() !== TARGET_COMPANY_ID) {
    throw new MigrationAbortError('TARGET_COMPANY_MISMATCH', 'El company id de producción no es el bloqueado', {
      expected: TARGET_COMPANY_ID,
      actual: params.targetCompanyId,
    });
  }
  if ((params.targetWarehouseId ?? '').trim() !== TARGET_WAREHOUSE_ID) {
    throw new MigrationAbortError(
      'TARGET_WAREHOUSE_MISMATCH',
      'El warehouse id de producción no es el bloqueado',
      { expected: TARGET_WAREHOUSE_ID, actual: params.targetWarehouseId },
    );
  }

  // Layer 2: the LIVE connection must really be the production database.
  if (params.metadata.databaseName.toLowerCase() !== PRODUCTION_DATABASE_NAME) {
    throw new MigrationAbortError(
      'PRODUCTION_DATABASE_MISMATCH',
      'La base conectada no es la base de producción esperada',
      { connected: params.metadata.databaseName, expected: PRODUCTION_DATABASE_NAME },
    );
  }

  // The tunnel route is verified by its own block below (real server port + non-loopback address).
  if (params.sshTunnel !== true) {
    const parsed = parseDatabaseUrl(params.url);
    if (params.metadata.serverPort !== null && String(params.metadata.serverPort) !== parsed.port) {
      throw new MigrationAbortError(
        'PRODUCTION_PORT_MISMATCH',
        'El puerto de la conexión no coincide con el declarado',
        { connected: params.metadata.serverPort, expected: parsed.port },
      );
    }
  }

  if (params.sshTunnel === true) {
    // The tunnel route proves itself through the live server metadata: the server must report a
    // non-loopback address (a local database pretending to be production reports 127.0.0.1) and
    // its real listening port.
    const address = (params.metadata.serverAddress ?? '').replace('/32', '').replace('/128', '');
    if (!address) {
      throw new MigrationAbortError(
        'PRODUCTION_TUNNEL_UNVERIFIED',
        'La conexión del túnel no reporta dirección de servidor: no se puede verificar que sea producción',
        { serverAddress: params.metadata.serverAddress },
      );
    }
    if (['127.0.0.1', '::1', '::ffff:127.0.0.1', 'localhost'].includes(address.toLowerCase())) {
      throw new MigrationAbortError(
        'PRODUCTION_TUNNEL_UNVERIFIED',
        'La conexión del túnel apunta a un servidor local, no a producción',
        { serverAddress: params.metadata.serverAddress },
      );
    }
    if (params.metadata.serverPort !== PRODUCTION_SERVER_PORT) {
      throw new MigrationAbortError(
        'PRODUCTION_TUNNEL_UNVERIFIED',
        'El servidor tras el túnel no escucha en el puerto de producción',
        { connected: params.metadata.serverPort, expected: PRODUCTION_SERVER_PORT },
      );
    }
  }

  return {
    classification: 'production',
    description: describeDatabaseUrl(params.url),
    route: params.sshTunnel === true ? 'SSH_TUNNEL' : 'DIRECT',
  };
}

/**
 * Full gate for the UAT execute path. Throws unless the destination is proven to be a
 * local, disposable, non-production UAT database.
 */
export function assertUatEnvironment(params: {
  environment: string;
  url: string;
  metadata: LiveDatabaseMetadata;
  env?: NodeJS.ProcessEnv;
}): { classification: EnvironmentClass; description: string } {
  // Layer 1: the project's sanctioned UAT gate (URL based).
  assertSafeUatEnvironment({
    ...(params.env ?? process.env),
    APP_ENV: 'uat',
    UAT_LOCAL_ONLY: 'true',
    UAT_SERVER_MODE: '',
    DATABASE_URL: params.url,
  });

  const requested = params.environment.trim().toLowerCase();
  if (requested !== 'uat') {
    throw new MigrationAbortError(
      'ENVIRONMENT_NOT_UAT',
      'La ejecución solo está autorizada con --environment=uat',
      { requested },
    );
  }

  const { classification, reasons } = classifyEnvironment({
    environment: params.environment,
    url: params.url,
    metadata: params.metadata,
  });

  if (classification === 'production') {
    throw new MigrationAbortError(
      'PRODUCTION_FORBIDDEN',
      'El destino es producción o infraestructura de producción: ejecución bloqueada',
      { reasons },
    );
  }
  if (classification !== 'uat') {
    throw new MigrationAbortError(
      'ENVIRONMENT_NOT_VERIFIED',
      'No se pudo verificar que el destino sea una base UAT local desechable',
      { reasons },
    );
  }

  // Layer 2: the live connection must agree with the resolved URL.
  const parsed = parseDatabaseUrl(params.url);
  if (params.metadata.databaseName.toLowerCase() !== parsed.database.toLowerCase()) {
    throw new MigrationAbortError(
      'DATABASE_URL_MISMATCH',
      'La base conectada no coincide con DATABASE_URL',
      { connected: params.metadata.databaseName, expected: parsed.database },
    );
  }
  const serverAddress = (params.metadata.serverAddress ?? '').replace('/32', '').replace('/128', '');
  if (!['127.0.0.1', '::1', '::ffff:127.0.0.1'].includes(serverAddress)) {
    throw new MigrationAbortError(
      'UAT_NOT_LOOPBACK',
      'La conexión UAT debe ser loopback (127.0.0.1/::1)',
      { serverAddress: params.metadata.serverAddress },
    );
  }
  if (params.metadata.serverPort !== null && String(params.metadata.serverPort) !== parsed.port) {
    throw new MigrationAbortError(
      'UAT_PORT_MISMATCH',
      'El puerto de la conexión no coincide con DATABASE_URL',
      { connected: params.metadata.serverPort, expected: parsed.port },
    );
  }

  return { classification, description: describeDatabaseUrl(params.url) };
}
