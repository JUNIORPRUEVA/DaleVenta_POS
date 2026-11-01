/**
 * APPYRA Guardian AI — interruptores del auto-enrolamiento por empresa.
 *
 * Contexto: hasta la fase 13, una instalación solo podía enrolarse con un código
 * de un solo uso entregado a mano. El auto-enrolamiento permite que la propia
 * instalación, **ya autenticada**, pida su autorización de enrolamiento de vida
 * corta.
 *
 * Reglas de seguridad (fail-closed):
 * - `GUARDIAN_AUTO_ENROLL_ENABLED` es `false` por defecto: sin este interruptor el
 *   endpoint de concesión no existe funcionalmente.
 * - Aunque el interruptor esté activo, **la lista de empresas manda**: vacía =
 *   ninguna empresa puede auto-enrolarse; `*` = todas las elegibles. Así el
 *   despliegue es siempre incremental y auditable.
 * - La autorización es un código de un solo uso de vida corta (por defecto 5
 *   minutos). Nunca hay un secreto compartido ni un token administrativo
 *   embebido en el instalador.
 */
export type GuardianAutoEnrollmentConfig = {
  /** Interruptor maestro del flujo de concesión de enrolamiento. */
  enabled: boolean;
  /** Empresas autorizadas. Vacío = ninguna. `*` = todas. */
  allowedCompanyIds: string[];
  /** Permite auto-activar `companies.guardian_enabled` al conceder. */
  activateOnGrant: boolean;
  /** Vida de la autorización de enrolamiento (segundos). */
  grantTtlSeconds: number;
  /** Máximo de instalaciones con credencial vigente por empresa. */
  maxInstallationsPerCompany: number;
  /** Máximo de autorizaciones emitidas por empresa en una hora. */
  grantsPerCompanyHour: number;
};

const ALL = '*';

function readBool(raw: string | undefined, fallback = false): boolean {
  const value = String(raw ?? '').trim().toLowerCase();
  if (!value) return fallback;
  return value === '1' || value === 'true' || value === 'yes' || value === 'on';
}

function readInt(raw: string | undefined, fallback: number, min: number, max: number): number {
  const parsed = Number.parseInt(String(raw ?? '').trim(), 10);
  if (!Number.isFinite(parsed)) return fallback;
  return Math.min(max, Math.max(min, parsed));
}

function readList(raw: string | undefined): string[] {
  const value = String(raw ?? '').trim();
  if (!value) return [];
  return value
    .split(',')
    .map((entry) => entry.trim())
    .filter((entry) => entry.length > 0);
}

export function resolveGuardianAutoEnrollmentConfig(
  env: NodeJS.ProcessEnv = process.env,
): GuardianAutoEnrollmentConfig {
  return {
    enabled: readBool(env.GUARDIAN_AUTO_ENROLL_ENABLED, false),
    allowedCompanyIds: readList(env.GUARDIAN_AUTO_ENROLL_COMPANIES),
    activateOnGrant: readBool(env.GUARDIAN_AUTO_ENROLL_ACTIVATE, true),
    grantTtlSeconds: readInt(env.GUARDIAN_AUTO_ENROLL_GRANT_TTL_SECONDS, 300, 60, 1_800),
    // Capacidad por empresa: el valor anterior (10) bloqueaba negocios con más
    // terminales que el promedio y dejaba equipos sin monitoreo
    // (`INSTALLATION_LIMIT_REACHED`). El coste real se controla por el saldo del
    // proveedor de IA, no limitando equipos.
    maxInstallationsPerCompany: readInt(
      env.GUARDIAN_MAX_INSTALLATIONS_PER_COMPANY,
      50,
      1,
      500,
    ),
    grantsPerCompanyHour: readInt(env.GUARDIAN_AUTO_ENROLL_GRANTS_PER_HOUR, 12, 1, 120),
  };
}

/**
 * `true` si la empresa está autorizada por la lista de despliegue.
 *
 * Fail-closed: sin lista, ninguna empresa entra; un id vacío nunca coincide.
 */
export function isCompanyAllowedForAutoEnrollment(
  config: GuardianAutoEnrollmentConfig,
  companyId: string | null | undefined,
): boolean {
  const id = String(companyId ?? '').trim();
  if (!id) return false;
  if (config.allowedCompanyIds.includes(ALL)) return true;
  return config.allowedCompanyIds.includes(id);
}

/**
 * Elegibilidad de licencia: la empresa debe estar activa, con licencia vigente y
 * sin bloqueo. Se compara por cadena para no acoplarse a los miembros exactos de
 * los enums de Prisma; cualquier valor desconocido se trata como **no** elegible.
 */
export type GuardianLicenseSnapshot = {
  status?: string | null;
  licenseStatus?: string | null;
  licenseBlockedAt?: Date | null;
  licenseExpiresAt?: Date | null;
};

const ELIGIBLE_LICENSE_STATUSES = new Set(['ACTIVE', 'TRIAL', 'GRACE']);

export function isCompanyLicenseEligible(
  company: GuardianLicenseSnapshot | null | undefined,
  now: Date = new Date(),
): boolean {
  if (!company) return false;
  if (String(company.status ?? '').toUpperCase() !== 'ACTIVE') return false;
  if (company.licenseBlockedAt) return false;
  const expires = company.licenseExpiresAt;
  if (expires && expires.getTime() <= now.getTime()) return false;
  const license = String(company.licenseStatus ?? '').toUpperCase();
  if (!license) return false;
  return ELIGIBLE_LICENSE_STATUSES.has(license);
}
