/**
 * Decisión de elegibilidad del asistente e-CF. Función **pura**.
 *
 * Existe para que la regla viva en un solo sitio: la usan el servicio de
 * inscripción (lectura completa con historial) y la configuración de empresa
 * (solo necesita un booleano). Duplicar la lógica en dos consultas permitiría
 * que la interfaz ofreciera una entrada que el backend rechaza, o al revés.
 *
 * No accede a base de datos, no lee entorno y no escribe nada.
 */

export type PortalEnrollmentSnapshot = {
  status: string;
  source: string;
  expiresAt: Date | null;
  revokedAt: Date | null;
} | null;

export type PortalEligibilityDecision = {
  eligible: boolean;
  reason:
    | "ENROLLED"
    | "ENROLLED_LEGACY_ENV"
    | "NO_AUTHORIZATION"
    | "AUTHORIZATION_EXPIRED"
    | "AUTHORIZATION_REVOKED";
  expiresAt: Date | null;
  source: string | null;
  legacy: boolean;
};

/**
 * Decide con lo que ya se leyó.
 *
 * @param enrollment fila vigente o más reciente de la empresa (o `null`).
 * @param legacyEligible resultado de la lista heredada `ECF_PORTAL_PILOT_COMPANY_IDS`.
 * @param now instante de la decisión (inyectable para pruebas).
 */
export function decidePortalEligibility(input: {
  enrollment: PortalEnrollmentSnapshot;
  legacyEligible: boolean;
  now: Date;
}): PortalEligibilityDecision {
  const row = input.enrollment;

  if (row) {
    if (row.status !== "ACTIVE" || row.revokedAt) {
      return {
        eligible: false,
        reason: "AUTHORIZATION_REVOKED",
        expiresAt: null,
        source: row.source,
        legacy: false,
      };
    }
    if (row.expiresAt && row.expiresAt.getTime() <= input.now.getTime()) {
      return {
        eligible: false,
        reason: "AUTHORIZATION_EXPIRED",
        expiresAt: row.expiresAt,
        source: row.source,
        legacy: false,
      };
    }
    return {
      eligible: true,
      reason: "ENROLLED",
      expiresAt: row.expiresAt,
      source: row.source,
      legacy: false,
    };
  }

  // Compatibilidad con un despliegue que ya tenía la lista configurada.
  if (input.legacyEligible) {
    return {
      eligible: true,
      reason: "ENROLLED_LEGACY_ENV",
      expiresAt: null,
      source: null,
      legacy: true,
    };
  }

  return {
    eligible: false,
    reason: "NO_AUTHORIZATION",
    expiresAt: null,
    source: null,
    legacy: false,
  };
}
