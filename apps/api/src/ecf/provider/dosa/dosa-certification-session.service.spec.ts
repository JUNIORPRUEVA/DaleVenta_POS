import {
  DOSA_SESSION_DEFAULT_LEASE_MS,
  DosaCertificationSessionService,
  type DosaContactEmailReader,
  type DosaIdentityReader,
  type DosaSessionClientPort,
  type DosaSessionCoordinator,
} from "./dosa-certification-session.service";
import type {
  DosaActiveSession,
  DosaSessionClaim,
  DosaSessionClosedStatus,
} from "./ecf-dosa-session.service";
import type { DosaSessionResult } from "./dosa-certification-session.client";

// Relativo al reloj real: la política de expiración compara con `Date.now()`.
const NOW = Date.now();
const FUTURE = new Date(NOW + 60 * 60 * 1000).toISOString();
const PAST = new Date(NOW - 60 * 60 * 1000).toISOString();

class FakeIdentity implements DosaIdentityReader {
  constructor(private readonly rncs: Record<string, string | null>) {}
  async resolve(companyId: string) {
    return { taxId: this.rncs[companyId] ?? null };
  }
}

class FakeEmails implements DosaContactEmailReader {
  constructor(private readonly values: Record<string, string>) {}
  async read(companyId: string) {
    return this.values[companyId] ?? "";
  }
}

type Row = {
  id: string;
  companyId: string;
  rnc: string;
  status: string;
  attemptNo: number;
  sessionUrl: string | null;
  sessionExpiresAt: string | null;
  providerPostulationId: string | null;
  leaseUntil: number | null;
};

/** Persistencia en memoria con la MISMA semántica que el SQL real. */
class FakeSessions implements DosaSessionCoordinator {
  readonly rows = new Map<string, Row>();
  readonly claimed: string[] = [];
  readonly closed: string[] = [];
  readonly uncertain: string[] = [];
  /** Expedientes históricos reconciliados que la apertura no puede mutar. */
  readonly reconciled = new Set<string>();
  lastLeaseMs: number | null = null;
  /** Simula a otra petición publicando la URL mientras esperamos. */
  publishOnPoll: Row | null = null;

  private key(companyId: string, rnc: string) {
    return `${companyId}:${rnc}`;
  }

  async hasReconciledIntent(companyId: string, rnc: string) {
    return this.reconciled.has(this.key(companyId, rnc));
  }

  async findActiveSessionFor(
    companyId: string,
    rnc: string,
  ): Promise<DosaActiveSession | null> {
    if (this.publishOnPoll) {
      this.rows.set(this.key(companyId, rnc), this.publishOnPoll);
      this.publishOnPoll = null;
    }
    const row = this.rows.get(this.key(companyId, rnc));
    if (!row) return null;
    return {
      id: row.id,
      status: row.status as DosaActiveSession["status"],
      attemptNo: row.attemptNo,
      sessionUrl: row.sessionUrl,
      sessionExpiresAt: row.sessionExpiresAt,
      providerPostulationId: row.providerPostulationId,
    };
  }

  async claim(input: {
    companyId: string;
    rnc: string;
  }): Promise<DosaSessionClaim> {
    this.claimed.push(this.key(input.companyId, input.rnc));
    const existing = this.rows.get(this.key(input.companyId, input.rnc));
    if (existing) {
      return {
        ok: true,
        id: existing.id,
        status: existing.status as DosaActiveSession["status"],
        created: false,
        sessionUrl: existing.sessionUrl,
        attemptNo: existing.attemptNo,
      };
    }
    const row: Row = {
      id: `s-${this.rows.size + 1}`,
      companyId: input.companyId,
      rnc: input.rnc,
      status: "NOT_STARTED",
      attemptNo: 1,
      sessionUrl: null,
      sessionExpiresAt: null,
      providerPostulationId: null,
      leaseUntil: null,
    };
    this.rows.set(this.key(input.companyId, input.rnc), row);
    return {
      ok: true,
      id: row.id,
      status: "NOT_STARTED",
      created: true,
      sessionUrl: null,
      attemptNo: 1,
    };
  }

  async acquireRequestLease(input: {
    companyId: string;
    rnc: string;
    leaseMs: number;
  }) {
    const row = this.rows.get(this.key(input.companyId, input.rnc));
    if (!row) return { acquired: false, sessionUrl: null, sessionExpiresAt: null };
    if (row.leaseUntil !== null && row.leaseUntil > Date.now()) {
      return {
        acquired: false,
        sessionUrl: row.sessionUrl,
        sessionExpiresAt: row.sessionExpiresAt,
      };
    }
    this.lastLeaseMs = input.leaseMs;
    row.leaseUntil = Date.now() + input.leaseMs;
    return {
      acquired: true,
      sessionUrl: row.sessionUrl,
      sessionExpiresAt: row.sessionExpiresAt,
    };
  }

  async releaseRequestLease(input: { companyId: string; rnc: string }) {
    const row = this.rows.get(this.key(input.companyId, input.rnc));
    if (row) row.leaseUntil = null;
  }

  async recordIssuedSession(input: {
    companyId: string;
    rnc: string;
    sessionUrl: string;
    sessionExpiresAt: string;
    providerPostulationId: string;
  }) {
    const row = this.rows.get(this.key(input.companyId, input.rnc));
    if (!row) return { recorded: false };
    row.sessionUrl = input.sessionUrl;
    row.sessionExpiresAt = input.sessionExpiresAt;
    row.providerPostulationId = input.providerPostulationId;
    row.status = "RUNNING";
    row.leaseUntil = null;
    return { recorded: true };
  }

  async markSessionUncertain(input: {
    companyId: string;
    rnc: string;
    reasonCode: string;
  }) {
    const row = this.rows.get(this.key(input.companyId, input.rnc));
    if (!row) return { updated: false };
    row.status = "ATTENTION";
    row.leaseUntil = null;
    this.uncertain.push(input.reasonCode);
    return { updated: true };
  }

  async close(input: {
    companyId: string;
    rnc: string;
    status: DosaSessionClosedStatus;
  }) {
    const row = this.rows.get(this.key(input.companyId, input.rnc));
    if (!row) return { closed: false };
    row.status = input.status;
    row.sessionUrl = null;
    row.sessionExpiresAt = null;
    this.closed.push(input.status);
    return { closed: true };
  }
}

class FakeClient implements DosaSessionClientPort {
  calls = 0;
  constructor(
    private readonly result: DosaSessionResult = {
      ok: true,
      status: 201,
      session: {
        url: "https://dosasystem.com/sesion/abc",
        path: "/sesion/abc",
        token: "token-secreto-123",
        expiresAt: FUTURE,
        postulacionId: "post-1",
        prueba: true,
      },
    },
    private readonly ready = true,
    private readonly thrown = false,
  ) {}

  describeReadiness() {
    return {
      ready: this.ready,
      blockingReasons: this.ready ? [] : ["DOSA_SESSION_SECRET_MISSING"],
    };
  }

  async createSession(): Promise<DosaSessionResult> {
    this.calls += 1;
    if (this.thrown) throw new Error("timeout");
    return this.result;
  }
}

function build(options: {
  rncs?: Record<string, string | null>;
  emails?: Record<string, string>;
  client?: FakeClient;
  sessions?: FakeSessions;
}) {
  const sessions = options.sessions ?? new FakeSessions();
  const client = options.client ?? new FakeClient();
  const service = new DosaCertificationSessionService(
    new FakeIdentity(
      options.rncs ?? { "company-a": "101000001", "company-b": "202000002" },
    ),
    new FakeEmails(
      options.emails ?? {
        "company-a": "factura@a.com",
        "company-b": "factura@b.com",
      },
    ),
    sessions,
    client,
    { pollAttempts: 2, pollDelayMs: 0 },
  );
  return { service, sessions, client };
}

describe("DosaCertificationSessionService — apertura automática", () => {
  it("empresa con correo: crea la sesión una sola vez y devuelve la URL", async () => {
    const { service, client, sessions } = build({});
    const result = await service.open({ companyId: "company-a", userId: "u1" });

    expect(result).toMatchObject({
      ok: true,
      sessionUrl: "https://dosasystem.com/sesion/abc",
      attemptNo: 1,
      providerPostulationId: "post-1",
      reused: false,
    });
    expect(client.calls).toBe(1);
    expect(sessions.rows.get("company-a:101000001")?.status).toBe("RUNNING");
  });

  it("empresa sin correo: falla y NO llama al proveedor", async () => {
    const { service, client } = build({
      emails: { "company-a": "" },
    });
    const result = await service.open({ companyId: "company-a" });

    expect(result).toMatchObject({ ok: false, code: "ECF_DOSA_SESSION_EMAIL_REQUIRED" });
    expect(client.calls).toBe(0);
  });

  it("correo inválido: falla y NO llama al proveedor", async () => {
    const { service, client } = build({
      emails: { "company-a": "no-es-correo" },
    });
    const result = await service.open({ companyId: "company-a" });

    expect(result).toMatchObject({ ok: false, code: "ECF_DOSA_SESSION_EMAIL_INVALID" });
    expect(client.calls).toBe(0);
  });

  it("dos empresas distintas no comparten sesión ni RNC", async () => {
    const { service, sessions, client } = build({});
    const a = await service.open({ companyId: "company-a" });
    const b = await service.open({ companyId: "company-b" });

    expect(a.ok && b.ok).toBe(true);
    expect(client.calls).toBe(2);
    expect(sessions.rows.has("company-a:101000001")).toBe(true);
    expect(sessions.rows.has("company-b:202000002")).toBe(true);
  });

  it("reutiliza una sesión vigente sin volver a llamar al proveedor", async () => {
    const sessions = new FakeSessions();
    await sessions.claim({ companyId: "company-a", rnc: "101000001" });
    await sessions.recordIssuedSession({
      companyId: "company-a",
      rnc: "101000001",
      sessionUrl: "https://dosasystem.com/sesion/viva",
      sessionExpiresAt: FUTURE,
      providerPostulationId: "post-viva",
    });
    const { service, client } = build({ sessions });

    const result = await service.open({ companyId: "company-a" });

    expect(result).toMatchObject({
      ok: true,
      reused: true,
      sessionUrl: "https://dosasystem.com/sesion/viva",
    });
    expect(client.calls).toBe(0);
  });

  it("sesión caducada: se cierra y se emite una nueva", async () => {
    const sessions = new FakeSessions();
    await sessions.claim({ companyId: "company-a", rnc: "101000001" });
    await sessions.recordIssuedSession({
      companyId: "company-a",
      rnc: "101000001",
      sessionUrl: "https://dosasystem.com/sesion/vieja",
      sessionExpiresAt: PAST,
      providerPostulationId: "post-vieja",
    });
    const { service, client } = build({ sessions });

    const result = await service.open({ companyId: "company-a" });

    expect(result).toMatchObject({ ok: true, reused: false });
    expect(sessions.closed).toContain("EXPIRED");
    expect(client.calls).toBe(1);
  });

  it("doble clic: la segunda petición reutiliza lo que publica la primera", async () => {
    const sessions = new FakeSessions();
    const otherRow: Row = {
      id: "s-win",
      companyId: "company-a",
      rnc: "101000001",
      status: "RUNNING",
      attemptNo: 1,
      sessionUrl: "https://dosasystem.com/sesion/ganadora",
      sessionExpiresAt: FUTURE,
      providerPostulationId: "post-win",
      leaseUntil: Date.now() + 45_000,
    };
    await sessions.claim({ companyId: "company-a", rnc: "101000001" });
    const claimed = sessions.rows.get("company-a:101000001")!;
    claimed.leaseUntil = Date.now() + 45_000;
    sessions.publishOnPoll = otherRow;
    const { service, client } = build({ sessions });

    const result = await service.open({ companyId: "company-a" });

    expect(result).toMatchObject({
      ok: true,
      reused: true,
      sessionUrl: "https://dosasystem.com/sesion/ganadora",
    });
    expect(client.calls).toBe(0);
  });

  it("error 4xx del proveedor: falla sin dejar el candado tomado", async () => {
    const { service, sessions, client } = build({
      client: new FakeClient({
        ok: false,
        code: "DOSA_SESSION_BAD_STATUS",
        reason: "rechazado",
        status: 422,
      }),
    });

    const result = await service.open({ companyId: "company-a" });

    expect(result).toMatchObject({
      ok: false,
      code: "ECF_DOSA_SESSION_PROVIDER_ERROR",
    });
    expect(client.calls).toBe(1);
    expect(sessions.rows.get("company-a:101000001")?.leaseUntil).toBeNull();
  });

  it("timeout / respuesta incierta: marca ATTENTION y NO reintenta solo", async () => {
    const { service, sessions, client } = build({
      client: new FakeClient({
        ok: false,
        code: "DOSA_SESSION_NETWORK_UNCERTAIN",
        reason: "sin respuesta",
        uncertain: true,
      }),
    });

    const first = await service.open({ companyId: "company-a" });
    expect(first).toMatchObject({
      ok: false,
      code: "ECF_DOSA_SESSION_UNCERTAIN",
      uncertain: true,
    });
    expect(sessions.uncertain.length).toBe(1);

    // Recuperación: no se repite la llamada.
    const second = await service.open({ companyId: "company-a" });
    expect(second).toMatchObject({
      ok: false,
      code: "ECF_DOSA_SESSION_UNCERTAIN",
    });
    expect(client.calls).toBe(1);
  });

  it("excepción del transporte también es incierta y no duplica", async () => {
    const { service, sessions, client } = build({
      client: new FakeClient(undefined, true, true),
    });

    const result = await service.open({ companyId: "company-a" });

    expect(result).toMatchObject({
      ok: false,
      code: "ECF_DOSA_SESSION_UNCERTAIN",
    });
    expect(client.calls).toBe(1);
    expect(sessions.uncertain).toContain("TRANSPORT_EXCEPTION");
  });

  it("clave ausente / API deshabilitada: falla cerrado sin tocar la red", async () => {
    const { service, client } = build({
      client: new FakeClient(undefined, false),
    });

    const result = await service.open({ companyId: "company-a" });

    expect(result).toMatchObject({
      ok: false,
      code: "ECF_DOSA_SESSION_DISABLED",
    });
    expect(client.calls).toBe(0);
  });

  it("empresa sin RNC verificado: no crea nada", async () => {
    const { service, sessions, client } = build({
      rncs: { "company-a": null },
    });

    const result = await service.open({ companyId: "company-a" });

    expect(result).toMatchObject({
      ok: false,
      code: "ECF_DOSA_SESSION_RNC_REQUIRED",
    });
    expect(sessions.claimed).toHaveLength(0);
    expect(client.calls).toBe(0);
  });

  it("no depende de tener e-CF activado: abre la sesión igual", async () => {
    // El servicio no consulta `ecf_company_configurations`; este caso fija que
    // una empresa sin e-CF puede prepararse y no se bloquea por ello.
    const { service } = build({});
    const result = await service.open({ companyId: "company-a" });
    expect(result.ok).toBe(true);
  });

  it("expediente reconciliado: bloquea la apertura automática sin mutarlo", async () => {
    const { service, sessions, client } = build({});
    sessions.reconciled.add("company-a:101000001");

    const result = await service.open({ companyId: "company-a" });

    expect(result).toMatchObject({
      ok: false,
      code: "ECF_DOSA_SESSION_HISTORICAL_REVIEW_REQUIRED",
    });
    expect(sessions.claimed).toHaveLength(0);
    expect(client.calls).toBe(0);
  });

  it("sesión histórica con URL pero sin vencimiento: no la reutiliza ni abre otra", async () => {
    const sessions = new FakeSessions();
    await sessions.claim({ companyId: "company-a", rnc: "101000001" });
    const row = sessions.rows.get("company-a:101000001")!;
    row.sessionUrl = "https://dosasystem.com/sesion/sin-fecha";
    row.sessionExpiresAt = null;
    const { service, client } = build({ sessions });

    const result = await service.open({ companyId: "company-a" });

    expect(result).toMatchObject({
      ok: false,
      code: "ECF_DOSA_SESSION_EXPIRY_UNKNOWN",
    });
    expect(client.calls).toBe(0);
  });

  it("el lease por defecto cubre el timeout máximo del cliente", async () => {
    const { service, sessions } = build({});

    const result = await service.open({ companyId: "company-a" });

    expect(result.ok).toBe(true);
    expect(sessions.lastLeaseMs).toBe(DOSA_SESSION_DEFAULT_LEASE_MS);
    expect(DOSA_SESSION_DEFAULT_LEASE_MS).toBeGreaterThan(120_000);
  });

  it("concurrencia: dos aperturas de la misma empresa producen un solo POST", async () => {
    const { service, client } = build({});
    const [a, b] = await Promise.all([
      service.open({ companyId: "company-a" }),
      service.open({ companyId: "company-a" }),
    ]);

    expect(client.calls).toBe(1);
    expect([a.ok, b.ok].filter(Boolean).length).toBeGreaterThanOrEqual(1);
  });

  it("concurrencia multiempresa: cada empresa mantiene su propio RNC y sesión", async () => {
    const { service, client, sessions } = build({});

    const [a, b] = await Promise.all([
      service.open({ companyId: "company-a" }),
      service.open({ companyId: "company-b" }),
    ]);

    expect(a.ok).toBe(true);
    expect(b.ok).toBe(true);
    expect(client.calls).toBe(2);
    expect(sessions.rows.has("company-a:101000001")).toBe(true);
    expect(sessions.rows.has("company-b:202000002")).toBe(true);
  });

  it("201 malformado: marca ATTENTION y no permite un segundo POST", async () => {
    const { service, sessions, client } = build({
      client: new FakeClient({
        ok: false,
        code: "DOSA_SESSION_MALFORMED_RESPONSE",
        reason: "respuesta inválida",
        status: 201,
        uncertain: true,
      }),
    });

    const first = await service.open({ companyId: "company-a" });
    expect(first).toMatchObject({
      ok: false,
      code: "ECF_DOSA_SESSION_UNCERTAIN",
      uncertain: true,
    });
    expect(sessions.uncertain).toContain("DOSA_SESSION_MALFORMED_RESPONSE");

    const second = await service.open({ companyId: "company-a" });
    expect(second).toMatchObject({
      ok: false,
      code: "ECF_DOSA_SESSION_UNCERTAIN",
    });
    expect(client.calls).toBe(1);
  });
});
