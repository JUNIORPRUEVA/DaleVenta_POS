import {
  DosaCertificationIntentService,
  normalizeRnc,
  type DosaRncOwnersReader,
} from "./dosa-certification-intent.service";
import type { EcfCanonicalIdentityService } from "../../dgii/certificate/ecf-canonical-identity.service";
import type { EcfDosaSessionService } from "./ecf-dosa-session.service";

/**
 * Preasociación empresa ↔ RNC.
 *
 * La intención se registra antes de abrir el asistente y toma el RNC del
 * **servidor**, nunca del navegador. Con esto, un evento del proveedor tiene una
 * sesión a la que pertenecer y la correlación deja de depender de un dato que
 * aporta el cliente.
 */

const COMPANY_A = "15151515-0000-4000-8000-000000000015";
const COMPANY_B = "16161616-0000-4000-8000-000000000016";
const RNC_A = "133306001";
const RNC_B = "130000002";

function identityOf(taxId: string | null): EcfCanonicalIdentityService {
  return {
    async resolve() {
      return {
        taxId,
        legalName: taxId ? "EMPRESA" : null,
        representativeName: null,
        representativeId: null,
        source: taxId ? "FISCAL_CONFIG" : "NONE",
      };
    },
  } as unknown as EcfCanonicalIdentityService;
}

class FakeSessions {
  readonly claims: Array<{ companyId: string; rnc: string; userId?: string | null }> = [];
  constructor(private readonly behaviour: "ok" | "fail" = "ok") {}
  async claim(input: { companyId: string; rnc: string; createdByUserId?: string | null }) {
    this.claims.push({
      companyId: input.companyId,
      rnc: input.rnc,
      userId: input.createdByUserId,
    });
    if (this.behaviour === "fail") {
      return { ok: false as const, reason: "ECF_DOSA_SESSION_CLAIM_FAILED" };
    }
    return {
      ok: true as const,
      id: "session-1",
      attemptNo: 1,
      created: true,
      status: "NOT_STARTED",
      sessionUrl: null,
    };
  }
}

class FakeOwners implements DosaRncOwnersReader {
  constructor(private readonly others: number) {}
  async countOtherCompaniesWithRnc() {
    return this.others;
  }
}

function build(options: {
  taxId?: string | null;
  others?: number;
  sessions?: FakeSessions;
} = {}) {
  const sessions = options.sessions ?? new FakeSessions();
  const service = new DosaCertificationIntentService(
    identityOf(options.taxId === undefined ? RNC_A : options.taxId),
    sessions as unknown as EcfDosaSessionService,
    new FakeOwners(options.others ?? 0),
  );
  return { service, sessions };
}

describe("DosaCertificationIntentService", () => {
  it("registra la intención con el RNC verificado del servidor", async () => {
    const { service, sessions } = build();

    const result = await service.register({ companyId: COMPANY_A, userId: "user-1" });

    expect(result).toMatchObject({
      ok: true,
      companyId: COMPANY_A,
      rnc: RNC_A,
      sessionId: "session-1",
    });
    expect(sessions.claims).toEqual([
      { companyId: COMPANY_A, rnc: RNC_A, userId: "user-1" },
    ]);
  });

  it("registrar la intención NO concede autorización fiscal", async () => {
    const { service } = build();
    const result = await service.register({ companyId: COMPANY_A });
    expect(result.ok).toBe(true);
    if (result.ok) expect(result.fiscalAuthorizationGranted).toBe(false);
  });

  it("sin RNC verificado en el servidor no se registra nada", async () => {
    const { service, sessions } = build({ taxId: null });

    const result = await service.register({ companyId: COMPANY_A });

    expect(result).toMatchObject({ ok: false, reason: "COMPANY_RNC_NOT_VERIFIED" });
    expect(sessions.claims).toHaveLength(0);
  });

  it("un RNC del navegador que no coincide con la identidad de la empresa se rechaza", async () => {
    const { service, sessions } = build({ taxId: RNC_A });

    const result = await service.register({
      companyId: COMPANY_A,
      rncFromClient: RNC_B,
    });

    expect(result).toMatchObject({
      ok: false,
      reason: "RNC_DOES_NOT_MATCH_COMPANY_IDENTITY",
    });
    expect(sessions.claims).toHaveLength(0);
  });

  it("un RNC del navegador equivalente sí se acepta (solo compara)", async () => {
    const { service } = build({ taxId: RNC_A });

    const result = await service.register({
      companyId: COMPANY_A,
      rncFromClient: "1-33-306-001",
    });

    expect(result.ok).toBe(true);
    if (result.ok) expect(result.rnc).toBe(RNC_A);
  });

  it("si otra empresa comparte el RNC, se bloquea la asociación automática", async () => {
    const { service, sessions } = build({ taxId: RNC_A, others: 1 });

    const result = await service.register({ companyId: COMPANY_A });

    expect(result).toMatchObject({ ok: false, reason: "AMBIGUOUS_RNC" });
    expect(sessions.claims).toHaveLength(0);
  });

  it("un fallo del claim no se convierte en éxito", async () => {
    const { service } = build({ sessions: new FakeSessions("fail") });

    const result = await service.register({ companyId: COMPANY_A });

    expect(result).toMatchObject({ ok: false, reason: "SESSION_CLAIM_FAILED" });
  });

  it("dos empresas con RNC distintos registran cada una la suya", async () => {
    const sessions = new FakeSessions();
    const first = new DosaCertificationIntentService(
      identityOf(RNC_A),
      sessions as unknown as EcfDosaSessionService,
      new FakeOwners(0),
    );
    const second = new DosaCertificationIntentService(
      identityOf(RNC_B),
      sessions as unknown as EcfDosaSessionService,
      new FakeOwners(0),
    );

    const a = await first.register({ companyId: COMPANY_A });
    const b = await second.register({ companyId: COMPANY_B });

    expect(a.ok && a.rnc).toBe(RNC_A);
    expect(b.ok && b.rnc).toBe(RNC_B);
    expect(sessions.claims.map((c) => c.rnc)).toEqual([RNC_A, RNC_B]);
  });

  it("normaliza el RNC igual en todo el módulo", () => {
    expect(normalizeRnc("1-33-306-001")).toBe("133306001");
    expect(normalizeRnc(" 133306001 ")).toBe("133306001");
    expect(normalizeRnc("")).toBe("");
  });
});
