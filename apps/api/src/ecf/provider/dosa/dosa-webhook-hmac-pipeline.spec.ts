import { createHmac } from "node:crypto";
import {
  DosaWebhookService,
  type DosaCompanyResolver,
  type DosaSessionHintRecorder,
  type DosaWebhookStore,
} from "./dosa-webhook.service";
import type { DosaSignatureConfig } from "./dosa-webhook-signature.policy";

/**
 * Pipeline del webhook con **firma HMAC real**.
 *
 * Lo que fija esta suite, y que un doble de la firma no podría fijar:
 *
 * 1. Un evento sin firma válida **no llega a la base**: ni inserta, ni
 *    actualiza, ni cambia ningún estado de certificación.
 * 2. Un evento autenticado sí se procesa y queda ligado a la empresa que
 *    resuelve el servidor por RNC.
 * 3. La idempotencia responde `duplicate` sin reprocesar.
 * 4. Un RNC de otra empresa no escribe en la empresa equivocada.
 */

const SECRET = "secreto-hmac-de-pipeline-no-real";
// El servicio usa su propio reloj, así que las firmas de estas pruebas se
// generan con la hora REAL de la ejecución; solo el caso de replay usa una
// hora desplazada a propósito.
const NOW_SECONDS = Math.floor(Date.now() / 1000);
const COMPANY_A = "aaaaaaaa-0000-4000-8000-00000000000a";
const COMPANY_B = "bbbbbbbb-0000-4000-8000-00000000000b";

const config: DosaSignatureConfig = {
  strategy: "HMAC_SHA256_TIMESTAMPED",
  secret: SECRET,
  timestampUnit: "seconds",
  toleranceSeconds: 300,
};

function rawBody(overrides: Record<string, unknown> = {}): Buffer {
  return Buffer.from(
    JSON.stringify({
      postulacion_id: "post-1",
      rnc: "13199988001",
      razon_social: "EMPRESA DE PRUEBA",
      correo: "fiscal@example.test",
      ambiente: "Test",
      estado_certificacion: "finalizado",
      credenciales_pendientes: false,
      disponibles_desde: "2026-11-01T22:50:12Z",
      ...overrides,
    }),
    "utf8",
  );
}

function signatureHeader(body: Buffer, t = String(NOW_SECONDS)): string {
  const digest = createHmac("sha256", SECRET)
    .update(`${t}.`, "utf8")
    .update(body)
    .digest("hex");
  return `t=${t},v1=${digest}`;
}

type Recorded = { sql: string; values: unknown[] };

/** Almacén falso que registra CADA consulta ejecutada. */
function fakeStore(responses: {
  insert?: Array<{ id: string }>;
  select?: Array<{ id: string; processing_state: string | null }>;
}) {
  const calls: Recorded[] = [];
  const store: DosaWebhookStore = {
    async $queryRaw<T>(query: TemplateStringsArray, ...values: unknown[]) {
      const sql = query.join("?");
      calls.push({ sql, values });
      if (/INSERT INTO/i.test(sql)) return (responses.insert ?? []) as T;
      if (/SELECT "id", "processing_state"/i.test(sql)) {
        return (responses.select ?? []) as T;
      }
      return [] as unknown as T;
    },
  };
  return { store, calls };
}

const resolverOf =
  (mapping: Record<string, { companyId: string; ecfEnabled: boolean }>): DosaCompanyResolver =>
  ({
    async resolveByRnc(rnc: string) {
      return mapping[rnc] ?? null;
    },
  });

function build(options: {
  insert?: Array<{ id: string }>;
  select?: Array<{ id: string; processing_state: string | null }>;
  companies?: Record<string, { companyId: string; ecfEnabled: boolean }>;
  signature?: DosaSignatureConfig;
  hints?: DosaSessionHintRecorder;
}) {
  const { store, calls } = fakeStore(options);
  const service = new DosaWebhookService(
    store,
    resolverOf(
      options.companies ?? {
        "13199988001": { companyId: COMPANY_A, ecfEnabled: true },
      },
    ),
    options.signature ?? config,
    undefined,
    options.hints,
  );
  return { service, calls };
}

function request(headers: Record<string, string>, body: Buffer) {
  return { headers, rawBody: body, body: JSON.parse(body.toString()) };
}

describe("webhook DOSA con firma HMAC", () => {
  it("un evento autenticado se registra para la empresa resuelta", async () => {
    const { service, calls } = build({ insert: [{ id: "evt-1" }] });
    const body = rawBody();

    const outcome = await service.handle(
      request({ "x-dosa-signature": signatureHeader(body) }, body),
    );

    expect(outcome).toMatchObject({ accepted: true, status: 200, duplicate: false });
    expect(calls.some((c) => /INSERT INTO/i.test(c.sql))).toBe(true);
    // La empresa la decide el servidor por RNC, no el cuerpo.
    expect(calls[0].values).toContain(COMPANY_A);
  });

  it("sin firma válida NO se ejecuta ninguna consulta", async () => {
    const { service, calls } = build({ insert: [{ id: "evt-1" }] });
    const body = rawBody();

    const outcome = await service.handle(request({}, body));

    expect(outcome).toMatchObject({ accepted: false, status: 503 });
    expect((outcome as { reason: string }).reason).toBe("SIGNATURE_HEADER_MISSING");
    // Nada de INSERT, nada de UPDATE: el estado no puede cambiar.
    expect(calls).toHaveLength(0);
  });

  it("una firma alterada no llega a la base", async () => {
    const { service, calls } = build({ insert: [{ id: "evt-1" }] });
    const body = rawBody();
    const tampered = Buffer.from(body);
    const index = tampered.indexOf("post-1");
    tampered[index] = "X".charCodeAt(0);

    const outcome = await service.handle(
      request({ "x-dosa-signature": signatureHeader(body) }, tampered),
    );

    expect(outcome).toMatchObject({ accepted: false, status: 503 });
    expect((outcome as { reason: string }).reason).toBe("SIGNATURE_MISMATCH");
    expect(calls).toHaveLength(0);
  });

  it("un replay fuera de ventana no llega a la base", async () => {
    const { service, calls } = build({ insert: [{ id: "evt-1" }] });
    const body = rawBody();
    const oldT = String(Math.floor(Date.now() / 1000) - 5_000);

    const outcome = await service.handle(
      request({ "x-dosa-signature": signatureHeader(body, oldT) }, body),
    );

    expect((outcome as { reason: string }).reason).toBe(
      "SIGNATURE_TIMESTAMP_OUT_OF_TOLERANCE",
    );
    expect(calls).toHaveLength(0);
  });

  it("repetir un evento autenticado responde duplicate sin reprocesar", async () => {
    const { service, calls } = build({
      insert: [],
      select: [{ id: "evt-1", processing_state: "COMPLETE" }],
    });
    const body = rawBody();

    const outcome = await service.handle(
      request({ "x-dosa-signature": signatureHeader(body) }, body),
    );

    expect(outcome).toMatchObject({
      accepted: true,
      status: 200,
      duplicate: true,
      code: "ECF_DOSA_WEBHOOK_DUPLICATE",
    });
    // No hay UPDATE: no se reprocesó nada.
    expect(calls.some((c) => /UPDATE/i.test(c.sql))).toBe(false);
  });

  it("un RNC de otra empresa escribe en ESA empresa y en ninguna otra", async () => {
    const { service, calls } = build({
      insert: [{ id: "evt-2" }],
      companies: {
        "13199988001": { companyId: COMPANY_A, ecfEnabled: true },
        "130000002": { companyId: COMPANY_B, ecfEnabled: true },
      },
    });
    const body = rawBody({ rnc: "130000002" });

    await service.handle(
      request({ "x-dosa-signature": signatureHeader(body) }, body),
    );

    expect(calls[0].values).toContain(COMPANY_B);
    expect(calls[0].values).not.toContain(COMPANY_A);
  });

  it("un RNC desconocido no se atribuye a ninguna empresa", async () => {
    const { service, calls } = build({ insert: [{ id: "evt-3" }] });
    const body = rawBody({ rnc: "130000999" });

    const outcome = await service.handle(
      request({ "x-dosa-signature": signatureHeader(body) }, body),
    );

    expect(outcome).toMatchObject({ accepted: false, status: 404 });
    expect(calls).toHaveLength(0);
  });

  it("una empresa sin e-CF habilitado no procesa el evento", async () => {
    const { service, calls } = build({
      insert: [{ id: "evt-4" }],
      companies: {
        "13199988001": { companyId: COMPANY_A, ecfEnabled: false },
      },
    });
    const body = rawBody();

    const outcome = await service.handle(
      request({ "x-dosa-signature": signatureHeader(body) }, body),
    );

    expect(outcome).toMatchObject({ accepted: false, status: 409 });
    expect(calls).toHaveLength(0);
  });

  it("un evento autenticado deja la pista de correlación en su empresa y RNC", async () => {
    const hints: Array<{ companyId: string; rnc: string; eventType: string }> = [];
    const { service } = build({
      insert: [{ id: "evt-5" }],
      hints: {
        async recordEventHint(input) {
          hints.push(input);
          return { updated: true };
        },
      },
    });
    const body = rawBody();

    const outcome = await service.handle(
      request({ "x-dosa-signature": signatureHeader(body) }, body),
    );

    expect(outcome.accepted).toBe(true);
    expect(hints).toHaveLength(1);
    expect(hints[0]).toEqual({
      companyId: COMPANY_A,
      rnc: "13199988001",
      eventType: "empresa.conectada",
    });
  });

  it("la pista NO se registra si la firma no es válida", async () => {
    const hints: unknown[] = [];
    const { service } = build({
      insert: [{ id: "evt-6" }],
      hints: {
        async recordEventHint(input) {
          hints.push(input);
          return { updated: true };
        },
      },
    });
    const body = rawBody();

    await service.handle(request({}, body));

    expect(hints).toHaveLength(0);
  });

  it("si la pista falla, el evento ya persistido sigue siendo un éxito", async () => {
    const { service } = build({
      insert: [{ id: "evt-7" }],
      hints: {
        async recordEventHint() {
          throw new Error("sesion no disponible");
        },
      },
    });
    const body = rawBody();

    const outcome = await service.handle(
      request({ "x-dosa-signature": signatureHeader(body) }, body),
    );

    // El hecho fiscal quedó registrado; la pista es un extra.
    expect(outcome.accepted).toBe(true);
  });
});
