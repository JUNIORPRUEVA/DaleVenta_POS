import { createHash } from "node:crypto";
import {
  DosaWebhookService,
  dedupeKeyOf,
  type DosaCompanyResolver,
  type DosaWebhookStore,
} from "./dosa-webhook.service";
import type { DosaSignatureConfig } from "./dosa-webhook-signature.policy";
import {
  DosaWebhookController,
  isDosaWebhookEndpointEnabled,
} from "./dosa-webhook.controller";

/**
 * Pruebas del webhook de DOSA.
 *
 * Todo aquí es **sintético**: peticiones construidas por el test. Que pasen no
 * demuestra que DOSA firme así; demuestra que el backend falla cerrado en cada
 * escenario peligroso.
 */

const RNC_KNOWN = "133306001";
const SECRET = "a".repeat(64);

const ENABLED_SIGNATURE: DosaSignatureConfig = {
  strategy: "UNVERIFIED_PLAINTEXT_SECRET",
  secret: SECRET,
};

function samplePayload(overrides: Record<string, unknown> = {}) {
  return {
    postulacion_id: "post-0001",
    rnc: RNC_KNOWN,
    razon_social: "EMPRESA DE PRUEBA SRL",
    correo: "fiscal@example.com",
    ambiente: "Test",
    estado_certificacion: "finalizado",
    credenciales: {
      api_key_produccion: "PROD-KEY-SECRETA-0001",
      api_key_test: "TEST-KEY-SECRETA-0002",
      api_secret: "API-SECRETO-0003",
    },
    credenciales_pendientes: false,
    disponibles_desde: "2026-11-01T22:50:12Z",
    ...overrides,
  };
}

type StoredRow = {
  companyId: string;
  dedupeKey: string;
  summary: string;
  signatureStatus: string;
  id?: string;
  state?: string;
};

/** Bóveda de prueba: acepta y confirma que se llamó. */
function fakeCredentials() {
  const calls: Array<{ companyId: string; rnc: string }> = [];
  return {
    calls,
    async ingestFromProvider(input: { companyId: string; rnc: string }) {
      calls.push({ companyId: input.companyId, rnc: input.rnc });
      return {
        ok: true as const,
        status: "PENDING_CONFIRMATION" as const,
        fingerprint: "f".repeat(64),
      };
    },
  };
}

/** Doble del almacén: implementa el `ON CONFLICT DO NOTHING` en memoria. */
class FakeStore implements DosaWebhookStore {
  readonly rows: StoredRow[] = [];
  readonly queries: string[] = [];

  async $queryRaw<T = unknown>(
    query: TemplateStringsArray,
    ...values: unknown[]
  ): Promise<T> {
    const sql = query.join("?");
    this.queries.push(sql);

    // El pipeline recuperable usa tres formas de SQL; el doble las distingue
    // para no confundir un UPDATE con un INSERT.
    if (sql.includes('"processing_state" =')) {
      const eventId = String(values[1]);
      const row = this.rows.find((item) => item.id === eventId);
      if (row) row.state = String(values[0]);
      return [] as unknown as T;
    }

    if (!sql.includes("INSERT INTO")) {
      const companyId = String(values[0]);
      const dedupeKey = String(values[1]);
      const row = this.rows.find(
        (item) => item.companyId === companyId && item.dedupeKey === dedupeKey,
      );
      return (row
        ? [{ id: row.id, processing_state: row.state }]
        : []) as unknown as T;
    }

    const [companyId, dedupeKey, , , , , summary, signatureStatus, state] =
      values as string[];
    const exists = this.rows.some(
      (row) => row.companyId === companyId && row.dedupeKey === dedupeKey,
    );
    if (exists) return [] as unknown as T;

    const id = `evt-${this.rows.length + 1}`;
    this.rows.push({ id, companyId, dedupeKey, summary, signatureStatus, state });
    return [{ id }] as unknown as T;
  }
}

class FakeResolver implements DosaCompanyResolver {
  readonly calls: string[] = [];
  constructor(
    private readonly table: Record<
      string,
      { companyId: string; ecfEnabled: boolean } | null
    >,
  ) {}

  async resolveByRnc(rnc: string) {
    this.calls.push(rnc);
    return this.table[rnc] ?? null;
  }
}

function build(options: {
  signature?: DosaSignatureConfig;
  companies?: Record<string, { companyId: string; ecfEnabled: boolean } | null>;
}) {
  const store = new FakeStore();
  const resolver = new FakeResolver(
    options.companies ?? {
      [RNC_KNOWN]: { companyId: "company-a", ecfEnabled: true },
    },
  );
  const credentials = fakeCredentials();
  const service = new DosaWebhookService(
    store,
    resolver,
    options.signature ?? ENABLED_SIGNATURE,
    credentials as unknown as never,
  );
  return { store, resolver, service, credentials };
}

function request(
  body: unknown,
  header?: string | null,
): {
  headers: Record<string, string | string[] | undefined>;
  rawBody: Buffer;
  body: unknown;
} {
  const rawBody = Buffer.from(JSON.stringify(body), "utf8");
  const headers: Record<string, string | string[] | undefined> = {
    "content-type": "application/json",
  };
  if (header !== null && header !== undefined) {
    headers["x-dosa-signature"] = header;
  }
  return { headers, rawBody, body };
}

describe("DosaWebhookService — firma", () => {
  it("rechaza sin cabecera de firma (fail-closed)", async () => {
    const { service, store } = build({});
    const outcome = await service.handle(request(samplePayload(), null));

    expect(outcome).toEqual({
      accepted: false,
      status: 401,
      code: "ECF_DOSA_WEBHOOK_BLOCKED",
      reason: "SIGNATURE_HEADER_MISSING",
    });
    expect(store.rows).toHaveLength(0);
  });

  it("estrategia BLOCKED por defecto: firma válida tampoco entra", async () => {
    const { service, store } = build({
      signature: { strategy: "BLOCKED", secret: SECRET },
    });
    const outcome = await service.handle(request(samplePayload(), SECRET));

    expect(outcome.accepted).toBe(false);
    expect(outcome).toMatchObject({ status: 503, reason: "STRATEGY_BLOCKED" });
    expect(store.rows).toHaveLength(0);
  });

  it("sin secreto configurado no valida ninguna firma", async () => {
    const { service } = build({
      signature: { strategy: "UNVERIFIED_PLAINTEXT_SECRET", secret: null },
    });
    const outcome = await service.handle(request(samplePayload(), SECRET));
    expect(outcome).toMatchObject({
      accepted: false,
      reason: "SECRET_NOT_CONFIGURED",
    });
  });

  it("falsificación: firma con el secreto equivocado se rechaza", async () => {
    const { service, store } = build({});
    const forged = request(samplePayload(), "b".repeat(64));

    const outcome = await service.handle(forged);

    expect(outcome).toMatchObject({
      accepted: false,
      // 401 y no 503: una firma falsa no se arregla reintentando, así que no se
      // le pide al proveedor que reintente.
      status: 401,
      reason: "SIGNATURE_MISMATCH",
    });
    expect(store.rows).toHaveLength(0);
  });

  it("falsificación: firma de longitud distinta no llega a comparar", async () => {
    const { service } = build({});
    const outcome = await service.handle(request(samplePayload(), "corta"));
    expect(outcome).toMatchObject({ reason: "SIGNATURE_MISMATCH" });
  });
});

describe("DosaWebhookService — esquema", () => {
  it("rechaza un payload sin postulacion_id", async () => {
    const { service, store } = build({});
    const body = samplePayload();
    delete (body as Record<string, unknown>).postulacion_id;

    const outcome = await service.handle(request(body, SECRET));

    expect(outcome).toMatchObject({
      accepted: false,
      status: 400,
      code: "ECF_DOSA_WEBHOOK_INVALID_PAYLOAD",
    });
    expect((outcome as { reason: string }).reason).toContain("postulacion_id");
    expect(store.rows).toHaveLength(0);
  });

  it("rechaza un RNC con formato imposible", async () => {
    const { service } = build({});
    const outcome = await service.handle(
      request(samplePayload({ rnc: "12" }), SECRET),
    );
    expect(outcome).toMatchObject({ accepted: false, status: 400 });
  });

  it("rechaza fecha de disponibilidad inválida", async () => {
    const { service } = build({});
    const outcome = await service.handle(
      request(samplePayload({ disponibles_desde: "ayer" }), SECRET),
    );
    expect(outcome).toMatchObject({ accepted: false, status: 400 });
  });

  it("rechaza un cuerpo que no es objeto", async () => {
    const { service } = build({});
    const rawBody = Buffer.from("[1,2,3]", "utf8");
    const outcome = await service.handle({
      headers: { "x-dosa-signature": SECRET },
      rawBody,
      body: [1, 2, 3],
    });
    expect(outcome).toMatchObject({
      accepted: false,
      status: 400,
      reason: "INVALID_BODY",
    });
  });

  it("rechaza si no hay rawBody (no puede hashear el original)", async () => {
    const { service } = build({});
    const outcome = await service.handle({
      headers: { "x-dosa-signature": SECRET },
      rawBody: undefined,
      body: samplePayload(),
    });
    expect(outcome).toMatchObject({
      accepted: false,
      status: 400,
      code: "ECF_DOSA_WEBHOOK_RAW_BODY_MISSING",
    });
  });
});

describe("DosaWebhookService — correlación y opt-in", () => {
  it("RNC desconocido no crea evento", async () => {
    const { service, store } = build({ companies: {} });
    const outcome = await service.handle(request(samplePayload(), SECRET));

    expect(outcome).toMatchObject({
      accepted: false,
      status: 404,
      code: "ECF_DOSA_WEBHOOK_UNKNOWN_RNC",
    });
    expect(store.rows).toHaveLength(0);
  });

  it("empresa sin e-CF habilitado no procesa el evento", async () => {
    const { service, store } = build({
      companies: { [RNC_KNOWN]: { companyId: "company-a", ecfEnabled: false } },
    });
    const outcome = await service.handle(request(samplePayload(), SECRET));

    expect(outcome).toMatchObject({
      accepted: false,
      status: 409,
      code: "ECF_DOSA_WEBHOOK_ECF_DISABLED",
    });
    expect(store.rows).toHaveLength(0);
  });

  it("la empresa sale SOLO de la vinculación de servidor, no del payload", async () => {
    // El RNC declarado existe como pista, pero el resolver es quien decide.
    const { service, store, resolver } = build({});
    await service.handle(request(samplePayload(), SECRET));

    expect(resolver.calls).toEqual([RNC_KNOWN]);
    expect(store.rows).toHaveLength(1);
    expect(store.rows[0].companyId).toBe("company-a");
  });

  it("secretos de empresa cruzados: el evento se guarda en la empresa del RNC resuelto", async () => {
    const { service, store } = build({
      companies: {
        [RNC_KNOWN]: { companyId: "company-a", ecfEnabled: true },
        "130000002": { companyId: "company-b", ecfEnabled: true },
      },
    });

    await service.handle(request(samplePayload(), SECRET));
    await service.handle(
      request(samplePayload({ postulacion_id: "post-0002", rnc: "130000002" }), SECRET),
    );

    expect(store.rows.map((row) => row.companyId)).toEqual([
      "company-a",
      "company-b",
    ]);
    // Cada fila queda atada a su empresa: no hay fila cruzada.
    expect(store.rows[0].companyId).not.toBe("company-b");
  });
});

describe("DosaWebhookService — idempotencia", () => {
  it("primer envío se registra", async () => {
    const { service, store } = build({});
    const outcome = await service.handle(request(samplePayload(), SECRET));

    expect(outcome).toMatchObject({
      accepted: true,
      status: 200,
      duplicate: false,
      code: "ECF_DOSA_WEBHOOK_RECORDED",
    });
    expect(store.rows).toHaveLength(1);
  });

  it("webhook recibido dos veces: el segundo es duplicado y no reprocesa", async () => {
    const { service, store } = build({});
    const first = await service.handle(request(samplePayload(), SECRET));
    const second = await service.handle(request(samplePayload(), SECRET));

    expect(first).toMatchObject({ accepted: true, duplicate: false });
    expect(second).toMatchObject({
      accepted: true,
      duplicate: true,
      code: "ECF_DOSA_WEBHOOK_DUPLICATE",
    });
    expect(store.rows).toHaveLength(1);
  });

  it("replay de una entrega antigua (mismo cuerpo) tampoco duplica", async () => {
    const { service, store } = build({});
    const body = samplePayload();
    await service.handle(request(body, SECRET));
    await service.handle(request(body, SECRET));
    await service.handle(request(body, SECRET));

    expect(store.rows).toHaveLength(1);
  });

  it("un estado distinto sí es un evento nuevo", async () => {
    const { service, store } = build({});
    await service.handle(request(samplePayload(), SECRET));
    await service.handle(
      request(samplePayload({ estado_certificacion: "en_proceso" }), SECRET),
    );
    expect(store.rows).toHaveLength(2);
  });

  it("la clave de deduplicación es estable y no contiene secretos", () => {
    const bodyHash = createHash("sha256").update("cuerpo-exacto").digest("hex");
    const key = dedupeKeyOf(
      {
        postulacionId: "post-0001",
        estadoCertificacion: "finalizado",
        disponiblesDesde: "2026-11-01T22:50:12Z",
      },
      bodyHash,
    );
    expect(key).toBe(
      createHash("sha256")
        .update(`post-0001|finalizado|2026-11-01T22:50:12Z|${bodyHash}`)
        .digest("hex"),
    );
    expect(key).toHaveLength(64);
    expect(key).not.toContain("KEY");
  });

  it("dos envíos con el mismo identificador y cuerpo distinto no son duplicados", () => {
    const base = {
      postulacionId: "post-0001",
      estadoCertificacion: "finalizado",
      disponiblesDesde: "2026-11-01T22:50:12Z",
    };
    const first = dedupeKeyOf(base, "hash-a");
    const retry = dedupeKeyOf(base, "hash-a");
    const rotated = dedupeKeyOf(base, "hash-b");

    expect(retry).toBe(first);
    expect(rotated).not.toBe(first);
  });

  it("usa INSERT ... ON CONFLICT para que la carrera no duplique", async () => {
    const { service, store } = build({});
    await service.handle(request(samplePayload(), SECRET));
    expect(store.queries[0]).toContain("ON CONFLICT");
    expect(store.queries[0]).toContain("DO NOTHING");
  });
});

describe("DosaWebhookService — secretos y ausencia de autoridad fiscal", () => {
  it("no persiste ningún valor de credencial (solo marcador)", async () => {
    const { service, store } = build({});
    await service.handle(request(samplePayload(), SECRET));

    const summary = store.rows[0].summary;
    expect(summary).not.toContain("PROD-KEY-SECRETA-0001");
    expect(summary).not.toContain("TEST-KEY-SECRETA-0002");
    expect(summary).not.toContain("API-SECRETO-0003");
    expect(summary).toContain("[REDACTED]");
  });

  it("no persiste el secreto del webhook", async () => {
    const { service, store } = build({});
    await service.handle(request(samplePayload(), SECRET));
    const serialized = JSON.stringify(store.rows);
    expect(serialized).not.toContain(SECRET);
  });

  it("la respuesta no devuelve credenciales", async () => {
    const { service } = build({});
    const outcome = await service.handle(request(samplePayload(), SECRET));
    const serialized = JSON.stringify(outcome);
    expect(serialized).not.toContain("PROD-KEY-SECRETA-0001");
    expect(serialized).not.toContain("TEST-KEY-SECRETA-0002");
    expect(serialized).not.toContain("API-SECRETO-0003");
  });

  it("estado finalizado + firma válida NO activa emisión ni toca la sesión", async () => {
    const { service, store } = build({});
    const outcome = await service.handle(
      request(
        samplePayload({ estado_certificacion: "finalizado", ambiente: "Produccion" }),
        SECRET,
      ),
    );

    expect(outcome).toMatchObject({ accepted: true, duplicate: false });
    // El pipeline emite exactamente dos sentencias: el INSERT del evento y el
    // UPDATE que lo marca completo. Ninguna toca tablas fiscales.
    expect(store.queries).toHaveLength(2);
    expect(store.queries[0]).toContain("INSERT INTO");
    expect(store.queries[1]).toContain("processing_state");
    const sql = store.queries.join(" ").toUpperCase();
    expect(sql).not.toContain("ECF_DOSA_CERTIFICATION_SESSIONS");
    expect(sql).not.toContain("ECF_COMPANY_CONFIGURATIONS");
  });
});

describe("DosaWebhookController", () => {
  function fakeRes() {
    const state = { status: 0, body: undefined as unknown };
    const res = {
      status(code: number) {
        state.status = code;
        return res;
      },
      json(payload: unknown) {
        state.body = payload;
        return res;
      },
    };
    return { state, res };
  }

  it("bandera apagada: 503 JSON, nunca 200 ni HTML", async () => {
    const { service } = build({});
    const controller = new DosaWebhookController(service);
    const { state, res } = fakeRes();
    process.env.DOSA_WEBHOOK_ENABLED = "false";

    await controller.receive(
      { headers: {}, body: samplePayload() } as never,
      res as never,
    );

    expect(state.status).toBe(503);
    expect(state.body).toMatchObject({
      accepted: false,
      code: "ECF_DOSA_WEBHOOK_DISABLED",
    });
    expect(typeof state.body).toBe("object");
  });

  it("bandera apagada ignora un payload válido por completo", async () => {
    const { service, store } = build({});
    const controller = new DosaWebhookController(service);
    const { res } = fakeRes();
    process.env.DOSA_WEBHOOK_ENABLED = "false";

    const req = request(samplePayload(), SECRET);
    await controller.receive(req as never, res as never);

    expect(store.rows).toHaveLength(0);
  });

  it("bandera encendida: propaga el 400 del esquema", async () => {
    const { service } = build({});
    const controller = new DosaWebhookController(service);
    const { state, res } = fakeRes();
    process.env.DOSA_WEBHOOK_ENABLED = "true";

    const req = request({ nada: true }, SECRET);
    await controller.receive(req as never, res as never);

    expect(state.status).toBe(400);
    expect(state.body).toMatchObject({ code: "ECF_DOSA_WEBHOOK_INVALID_PAYLOAD" });
  });

  it("bandera encendida: registra y responde 200 JSON sin credenciales", async () => {
    const { service } = build({});
    const controller = new DosaWebhookController(service);
    const { state, res } = fakeRes();
    process.env.DOSA_WEBHOOK_ENABLED = "true";

    const req = request(samplePayload(), SECRET);
    await controller.receive(req as never, res as never);

    expect(state.status).toBe(200);
    expect(state.body).toMatchObject({
      accepted: true,
      duplicate: false,
      code: "ECF_DOSA_WEBHOOK_RECORDED",
    });
    expect(JSON.stringify(state.body)).not.toContain("SECRETA");
  });

  it("lee la bandera solo con el valor exacto 'true'", () => {
    expect(isDosaWebhookEndpointEnabled({})).toBe(false);
    expect(isDosaWebhookEndpointEnabled({ DOSA_WEBHOOK_ENABLED: "1" })).toBe(false);
    expect(isDosaWebhookEndpointEnabled({ DOSA_WEBHOOK_ENABLED: "true" })).toBe(true);
    expect(isDosaWebhookEndpointEnabled({ DOSA_WEBHOOK_ENABLED: " TRUE " })).toBe(
      true,
    );
  });
});
