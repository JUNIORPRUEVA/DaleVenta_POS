/**
 * Política de CONCESIONES DE ASISTENCIA (customer → FULLTECH).
 *
 * Función pura: decide si una concesión permite una acción, sin tocar la base
 * ni el reloj del sistema (la fecha entra como parámetro), para poder probar
 * expiración y revocación de forma determinista.
 *
 * Regla que gobierna el módulo: pertenecer al staff de plataforma NO concede
 * acceso. El acceso lo concede la empresa, con alcance, caducidad y revocación.
 */

export const ECF_SUPPORT_SCOPES = [
  "VIEW_DOSSIER",
  "REVIEW_EVIDENCE",
  "REQUEST_CORRECTION",
] as const;
export type EcfSupportScope = (typeof ECF_SUPPORT_SCOPES)[number];

/** Vista mínima de una concesión que necesita la política. */
export type EcfSupportGrantLike = {
  scopes: readonly string[];
  expiresAt: Date | string;
  revokedAt?: Date | string | null;
};

export type EcfSupportDenial =
  | "ECF_SUPPORT_GRANT_MISSING"
  | "ECF_SUPPORT_GRANT_REVOKED"
  | "ECF_SUPPORT_GRANT_EXPIRED"
  | "ECF_SUPPORT_SCOPE_NOT_GRANTED";

function toTime(value: Date | string): number {
  return value instanceof Date
    ? value.getTime()
    : new Date(value).getTime();
}

/**
 * Motivo por el que la concesión NO permite la acción, o `null` si la permite.
 *
 * El orden importa: primero "no existe", luego revocada, luego expirada y solo
 * al final el alcance. Así el mensaje que recibe el staff dice la verdad sobre
 * por qué se le niega el acceso.
 */
export function supportGrantRefusal(
  grant: EcfSupportGrantLike | null | undefined,
  scope: EcfSupportScope,
  now: Date = new Date(),
): EcfSupportDenial | null {
  if (!grant) return "ECF_SUPPORT_GRANT_MISSING";
  if (grant.revokedAt) return "ECF_SUPPORT_GRANT_REVOKED";
  const expiry = toTime(grant.expiresAt);
  if (!Number.isFinite(expiry) || expiry <= now.getTime()) {
    return "ECF_SUPPORT_GRANT_EXPIRED";
  }
  if (!grant.scopes.includes(scope)) return "ECF_SUPPORT_SCOPE_NOT_GRANTED";
  return null;
}

/** `true` solo si la concesión permite el alcance en ese instante. */
export function supportGrantAllows(
  grant: EcfSupportGrantLike | null | undefined,
  scope: EcfSupportScope,
  now: Date = new Date(),
): boolean {
  return supportGrantRefusal(grant, scope, now) === null;
}

/** Normaliza y valida los alcances pedidos al crear una concesión. */
export function normalizeScopes(input: readonly string[]): EcfSupportScope[] {
  const unique = new Set<EcfSupportScope>();
  for (const raw of input) {
    const value = raw.trim().toUpperCase();
    if ((ECF_SUPPORT_SCOPES as readonly string[]).includes(value)) {
      unique.add(value as EcfSupportScope);
    }
  }
  return [...unique];
}

/** Caducidad máxima admitida: una concesión no debe ser eterna. */
export const ECF_SUPPORT_GRANT_MAX_DAYS = 30;

/**
 * `true` si la expiración pedida es aceptable: futura y dentro del máximo.
 * Se rechaza el pasado para que una concesión nazca ya caducada.
 */
export function isValidGrantExpiry(
  expiresAt: Date | string,
  now: Date = new Date(),
): boolean {
  const expiry = toTime(expiresAt);
  if (!Number.isFinite(expiry)) return false;
  const max = now.getTime() + ECF_SUPPORT_GRANT_MAX_DAYS * 24 * 60 * 60 * 1000;
  return expiry > now.getTime() && expiry <= max;
}
