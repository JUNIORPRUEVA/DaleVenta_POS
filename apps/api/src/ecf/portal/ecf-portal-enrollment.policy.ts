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
    | "AUTO_ELIGIBLE"
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
 * @param autoEligible la empresa cumple la regla de autoservicio y la
 *   inscripción automática está habilitada. Es la única forma de entrar sin que
 *   nadie de Fulltech intervenga.
 *
 * Orden de precedencia, que es lo que impide que la regla automática se salte un
 * control administrativo:
 *
 * 1. Si existe fila y está **revocada o caducada**, se rechaza aunque la regla
 *    automática diga que sí. Revocar debe ganar siempre; si no, la revocación no
 *    serviría para nada.
 * 2. Fila `ACTIVE` vigente → elegible.
 * 3. Lista heredada → elegible (compatibilidad de despliegue).
 * 4. Regla de autoservicio → elegible con motivo `AUTO_ELIGIBLE`.
 * 5. Nada de lo anterior → no elegible.
 */
export function decidePortalEligibility(input: {
  enrollment: PortalEnrollmentSnapshot;
  legacyEligible: boolean;
  now: Date;
  autoEligible?: boolean;
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

  // Autoservicio: la empresa cumple las condiciones y puede abrir el asistente
  // sin que nadie la inscriba a mano. Se llega aquí SOLO cuando no hay fila: una
  // revocación existente se rechazó arriba.
  if (input.autoEligible === true) {
    return {
      eligible: true,
      reason: "AUTO_ELIGIBLE",
      expiresAt: null,
      source: "AUTO_ELIGIBLE",
      legacy: false,
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
