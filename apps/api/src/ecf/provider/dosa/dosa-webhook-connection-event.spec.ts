import {
  DosaWebhookService,
  PENDING_CLASSIFICATION_EVENT_TYPE,
  type DosaCompanyResolver,
  type DosaSessionHintRecorder,
  type DosaWebhookStore,
} from "./dosa-webhook.service";
import type { DosaSignatureConfig } from "./dosa-webhook-signature.policy";
import type { DosaCredentialService } from "./dosa-credential.service";

/**
 * Primer evento de conexión: `empresa.conectada` / `webhook.prueba`.
 *
 * Lo pidió el proveedor el 06/11/2026:
 *
 * > «Solo les pedimos que su receptor acepte `postulacion_id` y
 * > `estado_certificacion` en `null` en el primer evento de conexión
 * > (`empresa.conectada`) y en el de prueba de firma (`webhook.prueba`), porque
 * > en ese momento todavía no existe el proceso de certificación.»
 *
 * Los dos errores reales del 06/11 fueron `MISSING_FIELD:postulacion_id` y
 * `MISSING_FIELD:estado_certificacion` (HTTP 400): el receptor rechazaba el
 * evento de conexión y la empresa quedaba sin poder continuar.
 *
 * Estas pruebas fijan el contrato completo: el evento se acepta, se vincula a
 * la empresa por RNC y **no** se pierde la seguridad (firma obligatoria,
 * correlación server-side, sin credenciales inventadas).
 */

const RNC_KNOWN = "133080206";
const SECRET = "b".repeat(64);
const COMPANY = "bbbbbbbb-0000-4000-8000-00000000000b";

const SIGNATURE: DosaSignatureConfig = {
  strategy: "UNVERIFIED_PLAINTEXT_SECRET",
  secret: SECRET,
};

type Inserted = {
  companyId: string;
  dedupeKey: string;
  eventType: string;
  postulacionId: string | null;
  estadoCertificacion: string | null;
  state: string;
};

/** Almacén en memoria con el `ON CONFLICT ("company_id","dedupe_key")`. */
class FakeStore implements DosaWebhookStore {
  readonly rows = new Map<string, Inserted & { id: string }>();
  private seq = 0;

  async $queryRaw<T = unknown>(
    query: TemplateStringsArray,
    ...values: unknown[]
  ): Promise<T> {
    const sql = query.join("?");

    if (sql.includes('"processing_state" =')) {
      const eventId = String(values[1]);
      for (const row of this.rows.values()) {
        if (row.id === eventId) row.state = String(values[0]);
      }
      return [] as unknown as T;
    }

    if (!sql.includes("INSERT INTO")) {
      const companyId = String(values[0]);
      const dedupeKey = String(values[1]);
      const row = this.rows.get(`${companyId}|${dedupeKey}`);
      return (row
        ? [{ id: row.id, processing_state: row.state }]
        : []) as unknown as T;
    }

    const [
      companyId,
      dedupeKey,
      eventType,
      postulacionId,
      estadoCertificacion,
      ,
      ,
      ,
      state,
    ] = values as Array<string | null>;

    const key = `${String(companyId)}|${String(dedupeKey)}`;
    if (this.rows.has(key)) return [] as unknown as T;

    this.seq += 1;
    const id = `evt-${this.seq}`;
    this.rows.set(key, {
      id,
      companyId: String(companyId),
      dedupeKey: String(dedupeKey),
      eventType: String(eventType),
      postulacionId: postulacionId ?? null,
      estadoCertificacion: estadoCertificacion ?? null,
      state: String(state),
    });
    return [{ id }] as unknown as T;
  }
}

class FakeResolver implements DosaCompanyResolver {
  readonly calls: string[] = [];
  constructor(
    private readonly entry: {
      companyId: string;
      ecfEnabled: boolean;
      portalEligible?: boolean;
    } | null,
  ) {}
  async resolveByRnc(rnc: string) {
    this.calls.push(rnc);
    return this.entry;
  }
}

class FakeHints implements DosaSessionHintRecorder {
  readonly hints: Array<{ rnc: string; eventType: string }> = [];
  readonly bindings: string[] = [];
  async recordEventHint(input: { rnc: string; eventType: string }) {
    this.hints.push({ rnc: input.rnc, eventType: input.eventType });
    return { updated: true };
  }
  async bindProviderPostulation(input: { providerPostulationId: string }) {
    this.bindings.push(input.providerPostulationId);
    return { bound: true };
  }
}

class FakeCredentials {
  readonly calls: Array<{
    companyId: string;
    rnc: string;
    environment: string;
  }> = [];
  async ingestFromProvider(input: {
    companyId: string;
    rnc: string;
    environment: string;
  }) {
    this.calls.push({
      companyId: input.companyId,
      rnc: input.rnc,
      environment: input.environment,
    });
    return {
      ok: true as const,
      status: "PENDING_CONFIRMATION" as const,
      fingerprint: "c".repeat(64),
    };
  }
}

/** `empresa.conectada` / `webhook.prueba`: sin postulación ni credenciales. */
function connectionEvent(overrides: Record<string, unknown> = {}) {
  return {
    postulacion_id: null,
    rnc: RNC_KNOWN,
    razon_social: "FULLTECH SRL",
    correo: "fiscal@fulltech.example",
    ambiente: "Produccion",
    estado_certificacion: null,
    credenciales_pendientes: false,
    ...overrides,
  };
}

/** Evento de llaves: aquí sí hay postulación, estado y fecha. */
function credentialsEvent(overrides: Record<string, unknown> = {}) {
  return {
    postulacion_id: "POST-133080206-0001",
    rnc: RNC_KNOWN,
    razon_social: "FULLTECH SRL",
    correo: "fiscal@fulltech.example",
    ambiente: "Produccion",
    estado_certificacion: "finalizado",
    credenciales: {
      api_key_produccion: "PROD-KEY-0001",
      api_key_test: "TEST-KEY-0002",
      api_secret: "API-SECRET-0003",
    },
    credenciales_pendientes: false,
    disponibles_desde: "2026-11-06T17:00:00Z",
    ...overrides,
  };
}

function build(
  options: {
    companies?: {
      companyId: string;
      ecfEnabled: boolean;
      portalEligible?: boolean;
    } | null;
  } = {},
) {
  const store = new FakeStore();
  const resolver = new FakeResolver(
    "companies" in options
      ? (options.companies ?? null)
      : { companyId: COMPANY, ecfEnabled: false, portalEligible: true },
  );
  const credentials = new FakeCredentials();
  const hints = new FakeHints();
  const service = new DosaWebhookService(
    store,
    resolver,
    SIGNATURE,
    credentials as unknown as DosaCredentialService,
    hints,
  );
  return { store, resolver, credentials, hints, service };
}

function request(
  body: unknown,
  header: string | null = SECRET,
): {
  headers: Record<string, string | string[] | undefined>;
  rawBody: Buffer;
  body: unknown;
} {
  const rawBody = Buffer.from(JSON.stringify(body), "utf8");
  const headers: Record<string, string | string[] | undefined> = {
    "content-type": "application/json",
  };
  if (header !== null) headers["x-dosa-signature"] = header;
  return { headers, rawBody, body };
}

describe("Webhook DOSA — primer evento de conexión", () => {
  it("ACEPTA empresa.conectada con postulacion_id y estado_certificacion en null", async () => {
    const { service, store } = build();

    const outcome = await service.handle(request(connectionEvent()));

    expect(outcome).toMatchObject({
      accepted: true,
      status: 200,
      duplicate: false,
      code: "ECF_DOSA_WEBHOOK_RECORDED",
    });
    expect(store.rows.size).toBe(1);
  });

  it("lo vincula a la empresa correcta por RNC, no por el cuerpo", async () => {
    const { service, store, resolver, hints } = build();

    await service.handle(request(connectionEvent()));

    expect(resolver.calls).toEqual([RNC_KNOWN]);
    const row = [...store.rows.values()][0];
    expect(row.companyId).toBe(COMPANY);
    // La pista llega a la sesión activa de esa empresa y ese RNC.
    expect(hints.hints).toEqual([
      { rnc: RNC_KNOWN, eventType: PENDING_CLASSIFICATION_EVENT_TYPE },
    ]);
  });

  it("persiste los null tal cual, sin inventar identificadores", async () => {
    const { service, store } = build();

    await service.handle(request(connectionEvent()));

    const row = [...store.rows.values()][0];
    expect(row.postulacionId).toBeNull();
    expect(row.estadoCertificacion).toBeNull();
  });

  it("no intenta vincular una postulación que todavía no existe", async () => {
    const { service, hints } = build();

    await service.handle(request(connectionEvent()));

    expect(hints.bindings).toEqual([]);
  });

  it("no ingiere credenciales: el evento de conexión no las trae", async () => {
    const { service, credentials } = build();

    await service.handle(request(connectionEvent()));

    expect(credentials.calls).toEqual([]);
  });

  it("acepta webhook.prueba (prueba de firma) con los mismos null", async () => {
    const { service, store } = build();

    const outcome = await service.handle(
      request(connectionEvent({ correo: "prueba@fulltech.example" })),
    );

    expect(outcome).toMatchObject({ accepted: true, status: 200 });
    expect(store.rows.size).toBe(1);
  });

  it("acepta la variante sin credenciales_pendientes ni disponibles_desde", async () => {
    const body = connectionEvent();
    delete (body as Record<string, unknown>).credenciales_pendientes;

    const { service } = build();
    const outcome = await service.handle(request(body));

    expect(outcome).toMatchObject({ accepted: true, status: 200 });
  });

  it("acepta cadenas vacías como ausencia, no como dato", async () => {
    const { service, store } = build();

    const outcome = await service.handle(
      request(connectionEvent({ postulacion_id: "   ", estado_certificacion: "" })),
    );

    expect(outcome).toMatchObject({ accepted: true, status: 200 });
    const row = [...store.rows.values()][0];
    expect(row.postulacionId).toBeNull();
    expect(row.estadoCertificacion).toBeNull();
  });

  it("un reintento idéntico sigue siendo duplicado", async () => {
    const { service, store } = build();

    await service.handle(request(connectionEvent()));
    const again = await service.handle(request(connectionEvent()));

    expect(again).toMatchObject({ accepted: true, duplicate: true });
    expect(store.rows.size).toBe(1);
  });

  it("se acepta aunque la empresa aún no tenga e-CF habilitado pero sí autorización", async () => {
    const { service } = build({
      companies: { companyId: COMPANY, ecfEnabled: false, portalEligible: true },
    });

    const outcome = await service.handle(request(connectionEvent()));

    expect(outcome).toMatchObject({ accepted: true, status: 200 });
  });

  it("rechaza el evento de conexión de una empresa sin e-CF ni autorización", async () => {
    const { service, store } = build({
      companies: { companyId: COMPANY, ecfEnabled: false, portalEligible: false },
    });

    const outcome = await service.handle(request(connectionEvent()));

    expect(outcome).toMatchObject({
      accepted: false,
      status: 409,
      code: "ECF_DOSA_WEBHOOK_ECF_DISABLED",
    });
    expect(store.rows.size).toBe(0);
  });
});

describe("Webhook DOSA — seguridad intacta con campos en null", () => {
  it("sin firma válida el evento de conexión no se procesa", async () => {
    const { service, store, resolver } = build();

    const outcome = await service.handle(request(connectionEvent(), null));

    expect(outcome).toMatchObject({ accepted: false, status: 401 });
    expect(store.rows.size).toBe(0);
    expect(resolver.calls).toEqual([]);
  });

  it("un RNC desconocido no se asocia a ninguna empresa", async () => {
    const { service, store } = build({ companies: null });

    const outcome = await service.handle(request(connectionEvent()));

    expect(outcome).toMatchObject({
      accepted: false,
      status: 404,
      code: "ECF_DOSA_WEBHOOK_UNKNOWN_RNC",
    });
    expect(store.rows.size).toBe(0);
  });

  it("sigue rechazando `estado_certificacion` de un tipo imposible", async () => {
    const { service, store } = build();

    const outcome = await service.handle(
      request(connectionEvent({ estado_certificacion: 42 })),
    );

    expect(outcome).toMatchObject({
      accepted: false,
      status: 400,
      code: "ECF_DOSA_WEBHOOK_INVALID_PAYLOAD",
    });
    expect((outcome as { reason: string }).reason).toContain(
      "estado_certificacion",
    );
    expect(store.rows.size).toBe(0);
  });

  it("sigue rechazando un `disponibles_desde` que no es fecha", async () => {
    const { service } = build();

    const outcome = await service.handle(
      request(connectionEvent({ disponibles_desde: "ayer" })),
    );

    expect(outcome).toMatchObject({ accepted: false, status: 400 });
  });

  it("sigue exigiendo la identidad del evento: sin rnc no hay nada que vincular", async () => {
    const { service } = build();

    const outcome = await service.handle(
      request(connectionEvent({ rnc: null })),
    );

    expect(outcome).toMatchObject({ accepted: false, status: 400 });
    expect((outcome as { reason: string }).reason).toContain("rnc");
  });
});

describe("Webhook DOSA — recorrido completo hasta las credenciales", () => {
  it("conexión → llaves: el proceso llega al final sin intervención manual", async () => {
    const { service, store, resolver, credentials, hints } = build();

    // 1. La empresa abre el asistente y DOSA avisa que se conectó.
    const connected = await service.handle(request(connectionEvent()));
    expect(connected).toMatchObject({
      accepted: true,
      status: 200,
      duplicate: false,
    });

    // 2. DOSA termina la postulación y manda las llaves.
    const withKeys = await service.handle(request(credentialsEvent()));
    expect(withKeys).toMatchObject({
      accepted: true,
      status: 200,
      duplicate: false,
      code: "ECF_DOSA_WEBHOOK_RECORDED",
    });

    // Una sola consulta de correlación por evento, siempre por RNC.
    expect(resolver.calls).toEqual([RNC_KNOWN, RNC_KNOWN]);
    // Las credenciales se guardan en la bóveda de ESA empresa y ESE RNC.
    expect(credentials.calls).toEqual([
      { companyId: COMPANY, rnc: RNC_KNOWN, environment: "production" },
    ]);
    // La postulación real queda vinculada al intento activo.
    expect(hints.bindings).toEqual(["POST-133080206-0001"]);
    // Dos eventos, dos evidencias.
    expect(store.rows.size).toBe(2);
  });

  it("reenviar las llaves con contenido nuevo no se descarta como duplicado", async () => {
    const { service, store, credentials } = build();

    await service.handle(request(credentialsEvent()));
    const resent = await service.handle(
      request(credentialsEvent({ credenciales: { api_key_test: "TEST-KEY-NUEVA" } })),
    );

    expect(resent).toMatchObject({ accepted: true, duplicate: false });
    expect(credentials.calls).toHaveLength(2);
    expect(store.rows.size).toBe(2);
  });
});
