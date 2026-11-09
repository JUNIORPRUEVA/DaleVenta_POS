import {
  ECF_DGII_DECLARATION_ERRORS,
  checkDeclaredRangeWithinAuthorization,
  validateAuthorizationDeclaration,
  type AuthorizedRange,
} from "./ecf-dgii-authorized-sequences.policy";

const NOW = new Date("2026-11-08T00:00:00.000Z");

function declaration(overrides: Record<string, unknown> = {}) {
  return {
    documentType: "E31",
    authorizationNumber: "6005190128",
    rangeFrom: 1,
    rangeTo: 150,
    approvedQuantity: 150,
    expiresAt: "2027-12-31T00:00:00.000Z",
    declarationAccepted: true,
    ...overrides,
  };
}

const AUTHORIZED: AuthorizedRange = {
  authorizationNumber: "6005190128",
  rangeFrom: 1,
  rangeTo: 150,
  approvedQuantity: 150,
  expiresAt: new Date("2027-12-31T00:00:00.000Z"),
};

describe("validateAuthorizationDeclaration", () => {
  it("acepta una declaración coherente", () => {
    const result = validateAuthorizationDeclaration(declaration(), NOW);
    expect(result.ok).toBe(true);
    if (!result.ok) return;
    expect(result.documentType).toBe("E31");
    expect(result.rangeFrom).toBe(1);
    expect(result.rangeTo).toBe(150);
    expect(result.expiresAt?.toISOString()).toBe("2027-12-31T00:00:00.000Z");
  });

  it("normaliza el tipo a mayúsculas", () => {
    const result = validateAuthorizationDeclaration(
      declaration({ documentType: " e31 " }),
      NOW,
    );
    expect(result.ok).toBe(true);
  });

  it("exige la declaración explícita", () => {
    const result = validateAuthorizationDeclaration(
      declaration({ declarationAccepted: false }),
      NOW,
    );
    expect(result).toEqual(
      expect.objectContaining({
        ok: false,
        code: ECF_DGII_DECLARATION_ERRORS.declarationRequired,
      }),
    );
  });

  it("acepta E32 como tipo declarable", () => {
    const result = validateAuthorizationDeclaration(
      declaration({
        documentType: " e32 ",
        authorizationNumber: "6005190129",
        rangeFrom: 1,
        rangeTo: 10000,
        approvedQuantity: 10000,
      }),
      NOW,
    );
    expect(result.ok).toBe(true);
    if (!result.ok) return;
    expect(result.documentType).toBe("E32");
  });

  it("rechaza tipos que el motor no puede numerar", () => {
    for (const documentType of ["E43", "E46", "B01", ""]) {
      const result = validateAuthorizationDeclaration(
        declaration({ documentType }),
        NOW,
      );
      expect(result).toEqual(
        expect.objectContaining({
          ok: false,
          code: ECF_DGII_DECLARATION_ERRORS.typeUnsupported,
        }),
      );
    }
  });

  it("exige un número de autorización con forma válida", () => {
    for (const authorizationNumber of ["", "ab", "!!", null]) {
      const result = validateAuthorizationDeclaration(
        declaration({ authorizationNumber }),
        NOW,
      );
      expect(result.ok).toBe(false);
    }
  });

  it("rechaza un rango invertido", () => {
    const result = validateAuthorizationDeclaration(
      declaration({ rangeFrom: 150, rangeTo: 1, approvedQuantity: 150 }),
      NOW,
    );
    expect(result).toEqual(
      expect.objectContaining({
        ok: false,
        code: ECF_DGII_DECLARATION_ERRORS.rangeInvalid,
      }),
    );
  });

  it("rechaza declarar más de lo que la DGII aprobó", () => {
    const result = validateAuthorizationDeclaration(
      declaration({ rangeFrom: 1, rangeTo: 1000, approvedQuantity: 150 }),
      NOW,
    );
    expect(result.ok).toBe(false);
    if (result.ok) return;
    expect(result.code).toBe(ECF_DGII_DECLARATION_ERRORS.quantityMismatch);
    expect(result.message).toContain("150");
    expect(result.message).toContain("1000");
  });

  it("rechaza una autorización vencida", () => {
    const result = validateAuthorizationDeclaration(
      declaration({ expiresAt: "2026-01-01T00:00:00.000Z" }),
      NOW,
    );
    expect(result).toEqual(
      expect.objectContaining({
        ok: false,
        code: ECF_DGII_DECLARATION_ERRORS.expired,
      }),
    );
  });

  it("acepta sin vencimiento cuando la DGII muestra N/A", () => {
    const result = validateAuthorizationDeclaration(
      declaration({ expiresAt: null }),
      NOW,
    );
    expect(result.ok).toBe(true);
    if (!result.ok) return;
    expect(result.expiresAt).toBeNull();
  });

  it("una fecha sin hora vale hasta el FIN de ese día", () => {
    const result = validateAuthorizationDeclaration(
      declaration({ expiresAt: "2027-12-31" }),
      NOW,
    );
    expect(result.ok).toBe(true);
    if (!result.ok) return;
    expect(result.expiresAt?.toISOString()).toBe("2027-12-31T23:59:59.999Z");
  });

  it("el último día autorizado todavía permite declarar", () => {
    const lastDay = new Date("2027-12-31T12:00:00.000Z");
    const result = validateAuthorizationDeclaration(
      declaration({ expiresAt: "2027-12-31" }),
      lastDay,
    );
    expect(result.ok).toBe(true);
  });

  it("el día siguiente al vencimiento ya no permite declarar", () => {
    const nextDay = new Date("2028-01-01T00:00:00.001Z");
    const result = validateAuthorizationDeclaration(
      declaration({ expiresAt: "2027-12-31" }),
      nextDay,
    );
    expect(result.ok).toBe(false);
  });
});

describe("checkDeclaredRangeWithinAuthorization", () => {
  it("bloquea cuando no hay autorización declarada", () => {
    const result = checkDeclaredRangeWithinAuthorization(
      { startNumber: 1, endNumber: 150 },
      null,
      NOW,
    );
    expect(result).toEqual(
      expect.objectContaining({
        ok: false,
        code: ECF_DGII_DECLARATION_ERRORS.notAuthorized,
      }),
    );
  });

  it("acepta un rango dentro de lo autorizado", () => {
    expect(
      checkDeclaredRangeWithinAuthorization(
        { startNumber: 1, endNumber: 150 },
        AUTHORIZED,
        NOW,
      ),
    ).toEqual({ ok: true });
  });

  it("acepta un rango parcial", () => {
    expect(
      checkDeclaredRangeWithinAuthorization(
        { startNumber: 10, endNumber: 20 },
        AUTHORIZED,
        NOW,
      ),
    ).toEqual({ ok: true });
  });

  it("rechaza salirse por arriba", () => {
    const result = checkDeclaredRangeWithinAuthorization(
      { startNumber: 1, endNumber: 151 },
      AUTHORIZED,
      NOW,
    );
    expect(result.ok).toBe(false);
    if (result.ok) return;
    expect(result.code).toBe(ECF_DGII_DECLARATION_ERRORS.exceedsAuthorized);
  });

  it("rechaza salirse por abajo", () => {
    const result = checkDeclaredRangeWithinAuthorization(
      { startNumber: 0, endNumber: 10 },
      AUTHORIZED,
      NOW,
    );
    expect(result.ok).toBe(false);
  });

  it("rechaza cuando la autorización ya venció", () => {
    const result = checkDeclaredRangeWithinAuthorization(
      { startNumber: 1, endNumber: 10 },
      { ...AUTHORIZED, expiresAt: new Date("2026-01-01T00:00:00.000Z") },
      NOW,
    );
    expect(result).toEqual(
      expect.objectContaining({
        ok: false,
        code: ECF_DGII_DECLARATION_ERRORS.expired,
      }),
    );
  });
});
