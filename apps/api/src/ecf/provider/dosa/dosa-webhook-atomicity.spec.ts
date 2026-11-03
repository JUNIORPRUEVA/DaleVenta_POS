import {
  COMPLETE_STATE,
  DosaWebhookService,
  PENDING_STATE,
  type DosaCompanyResolver,
} from "./dosa-webhook.service";
import type { DosaSignatureConfig } from "./dosa-webhook-signature.policy";
import type { DosaCredentialService } from "./dosa-credential.service";

/**
 * Atomicidad del webhook.
 *
 * El defecto que se corrige: el evento se insertaba primero y las credenciales
 * se guardaban después con un `catch {}` vacío. Si el guardado fallaba, el
 * webhook respondía 200 igualmente y el evento quedaba para siempre incompleto:
 * el proveedor, al ver 200, no reintentaba.
 *
 * Ahora el evento nace en `PENDING_CREDENTIALS`, solo pasa a `COMPLETE` cuando las
 * credenciales están cifradas, y un fallo responde 5xx para que el reenvío lo
 * reanude.
 */

const SECRET = "f".repeat(64);
const SIGNATURE: DosaSignatureConfig = {
  strategy: "UNVERIFIED_PLAINTEXT_SECRET",
  secret: SECRET,
};
const COMPANY = "14141414-0000-4000-8000-000000000014";
const RNC = "133306001";

type Row = { id: string; state: string; credentialsStoredAt: string | null };

/** Almacén con el `ON CONFLICT DO NOTHING` y el estado persistido. */
class FakeEvents {
  readonly rows = new Map<string, Row>();
  readonly sqlLog: string[] = [];
  private seq = 0;

  private key(companyId: string, dedupeKey: string) {
    return `${companyId}|${dedupeKey}`;
  }

  async $queryRaw<T = unknown>(
    query: TemplateStringsArray,
    ...values: unknown[]
  ): Promise<T> {
    const sql = query.join("?");
    this.sqlLog.push(sql);

    if (sql.includes("INSERT INTO")) {
      const companyId = String(values[0]);
      const dedupeKey = String(values[1]);
      const state = String(values[8]);
      const key = this.key(companyId, dedupeKey);
      if (this.rows.has(key)) return [] as unknown as T;
      this.seq += 1;
      const row: Row = { id: `evt-${this.seq}`, state, credentialsStoredAt: null };
      this.rows.set(key, row);
      return [{ id: row.id }] as unknown as T;
    }

    if (sql.includes('"processing_state" =')) {
      const state = String(values[0]);
      const eventId = String(values[1]);
      const companyId = String(values[2]);
      for (const [key, row] of this.rows) {
        if (row.id === eventId && key.startsWith(`${companyId}|`)) {
          row.state = state;
          row.credentialsStoredAt = new Date().toISOString();
        }
      }
      return [] as unknown as T;
    }

    const companyId = String(values[0]);
    const dedupeKey = String(values[1]);
    const row = this.rows.get(this.key(companyId, dedupeKey));
    return (row
      ? [{ id: row.id, processing_state: row.state }]
      : []) as unknown as T;
  }
}

function payload(overrides: Record<string, unknown> = {}) {
  const body = {
    postulacion_id: "post-atomicidad",
    rnc: RNC,
    razon_social: "EMPRESA ATOMICA SRL",
    correo: "fiscal@example.com",
    ambiente: "Test",
    estado_certificacion: "finalizado",
    credenciales: { api_key_test: "CLAVE-TEST-SECRETA" },
    credenciales_pendientes: false,
    disponibles_desde: "2026-11-03T10:00:00Z",
    ...overrides,
  };
  return {
    headers: { "x-dosa-signature": SECRET },
    rawBody: Buffer.from(JSON.stringify(body), "utf8"),
    body,
  };
}

function resolver(): DosaCompanyResolver {
  return {
    async resolveByRnc() {
      return { companyId: COMPANY, ecfEnabled: true };
    },
  };
}

/** Bóveda controlable: puede fallar a voluntad. */
class FlakyCredentials {
  calls = 0;
  constructor(private readonly behaviour: "ok" | "fail-soft" | "throw") {}
  async ingestFromProvider() {
    this.calls += 1;
    if (this.behaviour === "throw") throw new Error("vault unavailable");
    if (this.behaviour === "fail-soft") {
      return { ok: false as const, blockedReason: "DOSA_CREDENTIALS_KEY_MISSING" };
    }
    return { ok: true as const, status: "PENDING_CONFIRMATION" as const, fingerprint: "x" };
  }
}

function build(credentials?: unknown) {
  const events = new FakeEvents();
  const service = new DosaWebhookService(
    events,
    resolver(),
    SIGNATURE,
    credentials as DosaCredentialService | undefined,
  );
  return { events, service };
}

describe("Webhook — evento completo solo con las credenciales guardadas", () => {
  it("un guardado fallido NO responde 2xx y deja el evento reanudable", async () => {
    const credentials = new FlakyCredentials("fail-soft");
    const { events, service } = build(credentials);

    const outcome = await service.handle(payload());

    expect(outcome).toMatchObject({
      accepted: false,
      status: 500,
      code: "ECF_DOSA_WEBHOOK_CREDENTIALS_FAILED",
    });
    const row = [...events.rows.values()][0];
    expect(row.state).toBe(PENDING_STATE);
    expect(row.credentialsStoredAt).toBeNull();
  });

  it("si la bóveda lanza, el error tampoco se silencia", async () => {
    const credentials = new FlakyCredentials("throw");
    const { events, service } = build(credentials);

    await expect(service.handle(payload())).rejects.toThrow(/vault unavailable/);
    const row = [...events.rows.values()][0];
    expect(row.state).toBe(PENDING_STATE);
  });

  it("el reenvío REANUDA el evento incompleto en vez de darlo por duplicado", async () => {
    const failing = new FlakyCredentials("fail-soft");
    const { events, service } = build(failing);
    const first = await service.handle(payload());
    expect(first).toMatchObject({ accepted: false, status: 500 });

    // El proveedor reintenta; ahora la bóveda funciona.
    const healthy = new DosaWebhookService(
      events,
      resolver(),
      SIGNATURE,
      new FlakyCredentials("ok") as unknown as DosaCredentialService,
    );
    const second = await healthy.handle(payload());

    expect(second).toMatchObject({
      accepted: true,
      status: 200,
      duplicate: false,
      code: "ECF_DOSA_WEBHOOK_RESUMED",
    });
    const row = [...events.rows.values()][0];
    expect(row.state).toBe(COMPLETE_STATE);
    expect(row.credentialsStoredAt).not.toBeNull();
    // Y sigue habiendo UNA sola fila: reanudar no duplica.
    expect(events.rows.size).toBe(1);
  });

  it("tras completarse, la siguiente entrega sí es duplicado", async () => {
    const { service } = build(new FlakyCredentials("ok"));
    const first = await service.handle(payload());
    const second = await service.handle(payload());

    expect(first).toMatchObject({ code: "ECF_DOSA_WEBHOOK_RECORDED" });
    expect(second).toMatchObject({
      accepted: true,
      duplicate: true,
      code: "ECF_DOSA_WEBHOOK_DUPLICATE",
    });
  });

  it("sin credenciales en el payload no hay obligación pendiente: COMPLETE directo", async () => {
    const { events, service } = build(new FlakyCredentials("ok"));

    const outcome = await service.handle(payload({ credenciales: {} }));

    expect(outcome).toMatchObject({ accepted: true, status: 200 });
    expect([...events.rows.values()][0].state).toBe(COMPLETE_STATE);
  });

  it("si no hay bóveda configurada y llegan credenciales, se falla", async () => {
    const { events, service } = build(undefined);

    const outcome = await service.handle(payload());

    expect(outcome).toMatchObject({
      accepted: false,
      status: 500,
      code: "ECF_DOSA_WEBHOOK_CREDENTIALS_UNAVAILABLE",
    });
    expect([...events.rows.values()][0].state).toBe(PENDING_STATE);
  });

  it("el pipeline no toca la configuración fiscal de ninguna empresa", async () => {
    const { events, service } = build(new FlakyCredentials("ok"));
    await service.handle(payload());

    const serialized = events.sqlLog.join(" ").toLowerCase();
    expect(serialized).not.toContain("update ecf_company_configurations");
    expect(serialized).not.toContain("production_enabled");
    expect(serialized).not.toContain("certification_status");
  });
});
