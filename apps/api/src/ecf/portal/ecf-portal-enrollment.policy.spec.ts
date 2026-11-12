import { decidePortalEligibility } from "./ecf-portal-enrollment.policy";

/**
 * La regla de elegibilidad del asistente e-CF, aislada de la base y del entorno.
 *
 * Estas pruebas fijan el CONTRATO de la decision: que una autorizacion ausente
 * cierre el acceso, que caducar y revocar corten el acceso, y que la lista
 * heredada del entorno solo actue cuando no hay fila. Si alguien cambia el orden
 * de las comprobaciones, aqui se ve.
 */
const NOW = new Date("2026-06-01T12:00:00.000Z");

const ACTIVE = {
  status: "ACTIVE",
  source: "ADMIN_AUTHORIZATION",
  expiresAt: null as Date | null,
  revokedAt: null as Date | null,
};

describe("decidePortalEligibility", () => {
  it("sin autorizacion y sin lista heredada, no es elegible y lo dice", () => {
    const result = decidePortalEligibility({
      enrollment: null,
      legacyEligible: false,
      now: NOW,
    });

    expect(result).toEqual({
      eligible: false,
      reason: "NO_AUTHORIZATION",
      expiresAt: null,
      source: null,
      legacy: false,
    });
  });

  it("una autorizacion vigente es elegible y conserva su origen", () => {
    const result = decidePortalEligibility({
      enrollment: { ...ACTIVE, source: "CONTRACT_REFERENCE" },
      legacyEligible: false,
      now: NOW,
    });

    expect(result.eligible).toBe(true);
    expect(result.reason).toBe("ENROLLED");
    expect(result.source).toBe("CONTRACT_REFERENCE");
    expect(result.legacy).toBe(false);
  });

  it("una autorizacion sin caducidad nunca expira", () => {
    const result = decidePortalEligibility({
      enrollment: { ...ACTIVE, expiresAt: null },
      legacyEligible: false,
      now: new Date("2099-01-01T00:00:00.000Z"),
    });

    expect(result.eligible).toBe(true);
  });

  it("una autorizacion caducada no es elegible y devuelve la fecha", () => {
    const expiresAt = new Date("2026-05-31T23:59:59.000Z");
    const result = decidePortalEligibility({
      enrollment: { ...ACTIVE, expiresAt },
      legacyEligible: false,
      now: NOW,
    });

    expect(result.eligible).toBe(false);
    expect(result.reason).toBe("AUTHORIZATION_EXPIRED");
    expect(result.expiresAt).toEqual(expiresAt);
  });

  it("el instante exacto de caducidad ya no sirve (borde cerrado)", () => {
    const result = decidePortalEligibility({
      enrollment: { ...ACTIVE, expiresAt: NOW },
      legacyEligible: false,
      now: NOW,
    });

    expect(result.eligible).toBe(false);
    expect(result.reason).toBe("AUTHORIZATION_EXPIRED");
  });

  it("una autorizacion revocada no es elegible aunque no tenga caducidad", () => {
    const result = decidePortalEligibility({
      enrollment: { ...ACTIVE, status: "REVOKED", revokedAt: new Date("2026-05-01T00:00:00Z") },
      legacyEligible: false,
      now: NOW,
    });

    expect(result.eligible).toBe(false);
    expect(result.reason).toBe("AUTHORIZATION_REVOKED");
  });

  it("una fila con estado distinto de ACTIVE se trata como revocada", () => {
    const result = decidePortalEligibility({
      enrollment: { ...ACTIVE, status: "SUSPENDED", revokedAt: null },
      legacyEligible: false,
      now: NOW,
    });

    expect(result.eligible).toBe(false);
    expect(result.reason).toBe("AUTHORIZATION_REVOKED");
  });

  it("la lista heredada habilita solo cuando NO hay fila", () => {
    const legacy = decidePortalEligibility({
      enrollment: null,
      legacyEligible: true,
      now: NOW,
    });
    expect(legacy.eligible).toBe(true);
    expect(legacy.reason).toBe("ENROLLED_LEGACY_ENV");
    expect(legacy.legacy).toBe(true);
  });

  it("una fila revocada gana sobre la lista heredada", () => {
    const result = decidePortalEligibility({
      enrollment: { ...ACTIVE, revokedAt: new Date("2026-05-01T00:00:00Z") },
      legacyEligible: true,
      now: NOW,
    });

    // Revocar debe servir incluso si el despliegue conserva la lista vieja.
    expect(result.eligible).toBe(false);
    expect(result.reason).toBe("AUTHORIZATION_REVOKED");
  });

  it("una fila caducada gana sobre la lista heredada", () => {
    const result = decidePortalEligibility({
      enrollment: { ...ACTIVE, expiresAt: new Date("2020-01-01T00:00:00Z") },
      legacyEligible: true,
      now: NOW,
    });

    expect(result.eligible).toBe(false);
    expect(result.reason).toBe("AUTHORIZATION_EXPIRED");
  });

  it("es determinista: la misma entrada da la misma decision", () => {
    const input = { enrollment: { ...ACTIVE }, legacyEligible: false, now: NOW };
    expect(decidePortalEligibility(input)).toEqual(decidePortalEligibility(input));
  });
});
