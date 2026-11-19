import { LicenseStatus } from '@prisma/client';

/**
 * Acceso efectivo de una empresa a la aplicacion.
 *
 * - `FULL`: trabaja con normalidad (prueba vigente o licencia pagada vigente).
 * - `RESTRICTED`: la licencia vencio. **Entra** y solo ve Planes y Soporte
 *   (mas auth/licencia/actualizaciones). No es un bloqueo.
 * - `BLOCKED`: la empresa esta suspendida o bloqueada por decision humana.
 */
export type LicenseAccessLevel = 'FULL' | 'RESTRICTED' | 'BLOCKED';

export type LicenseAccessReason =
  | 'NO_COMPANY'
  | 'TRIAL'
  | 'ACTIVE'
  | 'TRIAL_EXPIRED'
  | 'EXPIRED'
  | 'BLOCKED'
  | 'COMPANY_INACTIVE';

export type LicenseSnapshot = {
  status: string;
  licenseStatus: LicenseStatus | string;
  trialEndsAt: Date | null;
  licenseExpiresAt: Date | null;
  licenseActivatedAt?: Date | null;
};

export type LicenseAccess = {
  level: LicenseAccessLevel;
  reason: LicenseAccessReason;
  effectiveStatus: LicenseStatus;
  isTrial: boolean;
  periodEndsAt: Date | null;
  /** Dias completos que quedan del periodo; `null` si no hay fecha. */
  daysRemaining: number | null;
  /** Atajo para la app: true cuando el cliente tiene que renovar para trabajar. */
  restricted: boolean;
};

const MS_PER_DAY = 24 * 60 * 60 * 1000;

/**
 * Regla unica de acceso. Es pura a proposito: la usan el guard, el login y la
 * pantalla Planes, y asi los tres no pueden discrepar.
 */
export function resolveLicenseAccess(
  snapshot: LicenseSnapshot | null | undefined,
  now: Date = new Date(),
): LicenseAccess {
  if (!snapshot) {
    return {
      level: 'FULL',
      reason: 'NO_COMPANY',
      effectiveStatus: LicenseStatus.ACTIVE,
      isTrial: false,
      periodEndsAt: null,
      daysRemaining: null,
      restricted: false,
    };
  }

  const isTrial = snapshot.licenseStatus === LicenseStatus.TRIAL;
  const periodEndsAt = isTrial
    ? snapshot.trialEndsAt
    : snapshot.licenseExpiresAt;
  const daysRemaining = remainingDays(periodEndsAt, now);

  if (snapshot.status !== 'ACTIVE') {
    return access('BLOCKED', 'COMPANY_INACTIVE', LicenseStatus.BLOCKED);
  }

  if (snapshot.licenseStatus === LicenseStatus.BLOCKED) {
    return access('BLOCKED', 'BLOCKED', LicenseStatus.BLOCKED);
  }

  if (isTrial && isPast(periodEndsAt, now)) {
    return access('RESTRICTED', 'TRIAL_EXPIRED', LicenseStatus.EXPIRED);
  }

  if (
    snapshot.licenseStatus === LicenseStatus.ACTIVE &&
    isPast(periodEndsAt, now)
  ) {
    return access('RESTRICTED', 'EXPIRED', LicenseStatus.EXPIRED);
  }

  if (snapshot.licenseStatus === LicenseStatus.EXPIRED) {
    return access('RESTRICTED', 'EXPIRED', LicenseStatus.EXPIRED);
  }

  if (isTrial) {
    return access('FULL', 'TRIAL', LicenseStatus.TRIAL);
  }

  return access('FULL', 'ACTIVE', LicenseStatus.ACTIVE);

  function access(
    level: LicenseAccessLevel,
    reason: LicenseAccessReason,
    effectiveStatus: LicenseStatus,
  ): LicenseAccess {
    return {
      level,
      reason,
      effectiveStatus,
      isTrial,
      periodEndsAt,
      daysRemaining,
      restricted: level === 'RESTRICTED',
    };
  }
}

function isPast(value: Date | null, now: Date) {
  return !!value && value.getTime() < now.getTime();
}

export function remainingDays(value: Date | null, now: Date = new Date()) {
  if (!value) return null;
  return Math.ceil((value.getTime() - now.getTime()) / MS_PER_DAY);
}

/**
 * Rutas que siguen disponibles con la licencia vencida. La lista es cerrada a
 * proposito: lo que no este aqui exige licencia vigente (fallo cerrado).
 */
const RESTRICTED_ALLOWED_PREFIXES = [
  '/auth',
  '/health',
  '/license',
  '/app-updates',
  '/support',
  '/notifications',
];

/** Rutas de `/license` que se pueden escribir sin licencia vigente. */
const RESTRICTED_LICENSE_WRITE_ALLOWED = [
  '/license/orders',
  '/license/payment-instructions',
];

/** Prefijos que admiten escritura: sesion, soporte y renovacion del plan. */
const RESTRICTED_WRITE_PREFIXES = ['/auth', '/support', '/notifications'];

/**
 * Lista blanca de lo que sigue disponible cuando la empresa **no** puede
 * trabajar: licencia vencida (`RESTRICTED`) o cuenta suspendida (`BLOCKED`).
 *
 * La lista es la misma a proposito: en los dos casos el cliente tiene que poder
 * ver su estado, pagar (si debe dinero) y pedir ayuda. Lo que no esta aqui
 * exige licencia vigente (fallo cerrado).
 *
 * `POST /license/activate` **no** esta en la lista: activar sin pagar ya no
 * existe; solo el flujo de ordenes puede cambiar la licencia.
 */
export function isAllowedWhileRestricted(
  method: string,
  rawPath: string,
): boolean {
  const path = normalizePath(rawPath);
  if (!path) return false;
  const prefixAllowed = RESTRICTED_ALLOWED_PREFIXES.some(
    (prefix) => path === prefix || path.startsWith(`${prefix}/`),
  );
  if (!prefixAllowed) return false;
  if (path.startsWith('/license/admin')) return false;
  const verb = (method || 'GET').toUpperCase();
  // Con la licencia vencida `GET` se permite en todas las rutas autorizadas;
  // escribir solo donde hace falta para poder renovar o pedir ayuda.
  if (verb === 'GET' || verb === 'HEAD' || verb === 'OPTIONS') return true;
  if (
    RESTRICTED_WRITE_PREFIXES.some(
      (prefix) => path === prefix || path.startsWith(`${prefix}/`),
    )
  ) {
    return true;
  }
  return RESTRICTED_LICENSE_WRITE_ALLOWED.some(
    (allowed) => path === allowed || path.startsWith(`${allowed}/`),
  );
}

function normalizePath(rawPath: string) {
  const value = (rawPath || '').split('?')[0]?.trim() ?? '';
  if (!value.startsWith('/')) return `/${value}`.replace(/\/+$/, '') || '/';
  return value.replace(/\/+$/, '') || '/';
}
