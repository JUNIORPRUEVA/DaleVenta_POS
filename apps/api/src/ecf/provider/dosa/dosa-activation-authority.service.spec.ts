import {
  PrismaDosaAuthorizationReader,
  activationBlockers,
} from "./dosa-activation-authority.service";

/**
 * La aprobación de la DGII ya no exige un documento que el trámite de DOSA no
 * entrega: el cierre firmado del proveedor para el intento vigente también la
 * acredita. Estas pruebas fijan esa regla para que no vuelva a bloquearse una
 * empresa que la DGII ya aprobó.
 */
function readerWith(row: Record<string, unknown>) {
  const prisma = { $queryRaw: jest.fn().mockResolvedValue([row]) };
  return new PrismaDosaAuthorizationReader(prisma as never);
}

const baseRow = {
  attempt_no: 1,
  attempt_created_at: new Date("2026-11-04T01:33:58.000Z"),
  postulacion_id: "6aedef0ba08eaff1a8703d46",
  linked_sessions: 1,
  provider_events: 0,
  foreign_events: 0,
  dgii_state: null,
  dgii_source: null,
  dgii_authorized_at: null,
  last_decision: null,
  last_decision_at: null,
  last_recorded_at: null,
  authorizations_recorded: 0,
  authorizations_revoked: 0,
};

describe("evidencia de activación DOSA · aprobación de la DGII", () => {
  it("el cierre firmado de DOSA acredita la aprobación sin documento", async () => {
    const evidence = await readerWith({
      ...baseRow,
      provider_events: 2,
      dgii_state: "NOT_STARTED",
      dgii_source: "NONE",
    }).read({ companyId: "company-a", rnc: "133080206" });

    expect(evidence.providerConfirmed).toBe(true);
    expect(evidence.dgiiApproved).toBe(true);
  });

  it("sin evento del proveedor ni registro oficial sigue sin aprobar", async () => {
    const evidence = await readerWith({
      ...baseRow,
      provider_events: 0,
    }).read({ companyId: "company-a", rnc: "133080206" });

    expect(evidence.providerConfirmed).toBe(false);
    expect(evidence.dgiiApproved).toBe(false);
  });

  it("el registro oficial sigue acreditando la aprobación", async () => {
    const evidence = await readerWith({
      ...baseRow,
      dgii_state: "APPROVED",
      dgii_source: "DGII_OFFICIAL_RECORD",
      dgii_authorized_at: new Date("2026-11-09T12:00:00.000Z"),
    }).read({ companyId: "company-a", rnc: "133080206" });

    expect(evidence.dgiiApproved).toBe(true);
  });

  it("una aprobación anterior al intento vigente no cuenta", async () => {
    const evidence = await readerWith({
      ...baseRow,
      dgii_state: "APPROVED",
      dgii_source: "DGII_OFFICIAL_RECORD",
      dgii_authorized_at: new Date("2026-10-01T12:00:00.000Z"),
    }).read({ companyId: "company-a", rnc: "133080206" });

    expect(evidence.dgiiApproved).toBe(false);
  });

  it("con la DGII aprobada solo falta la autorización de la empresa", async () => {
    const evidence = await readerWith({
      ...baseRow,
      provider_events: 1,
    }).read({ companyId: "company-a", rnc: "133080206" });

    expect(
      activationBlockers({
        ...evidence,
        fiscalDataReady: true,
        applicationSubmitted: true,
      } as never),
    ).toEqual(["ECF_DOSA_ACTIVATION_ADMIN_NOT_AUTHORIZED"]);
  });
});
