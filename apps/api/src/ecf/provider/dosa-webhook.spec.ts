import {
  DOSA_SIGNATURE_CONTRACT_PENDING,
  DOSA_WEBHOOK_CONTRACT_STATUS,
  readDosaWebhookEnvelope,
} from "./dosa-webhook.contract";
import {
  assertEnvironmentIsolation,
  eventDedupeKey,
  normalizeRnc,
  resolveLinkedCompany,
  type DosaCompanyBinding,
} from "./dosa-company-linking.policy";
import { DosaWebhookReceiverService } from "./dosa-webhook-receiver.service";
import { dosaSignatureContractPending, verifyDosaSignature } from "./dosa-webhook.verification";

const binding = (overrides: Partial<DosaCompanyBinding> = {}): DosaCompanyBinding => ({
  companyId: "company-a",
  companyTaxId: "133020232",
  providerRnc: "133020232",
  environment: "test",
  ...overrides,
});

describe("DOSA webhook — firma bloqueada por contrato", () => {
  it("el contrato sigue sin resolver", () => {
    // Si esto cambia, la verificación de abajo debe reescribirse con la fórmula
    // EXACTA de DOSA, no antes.
    expect(DOSA_WEBHOOK_CONTRACT_STATUS).toBe("BLOCKED_PENDING_OFFICIAL_SIGNATURE_CONTRACT");
  });

  it("sin cabecera X-Dosa-Signature rechaza", () => {
    expect(verifyDosaSignature({ headers: {}, rawBody: "{}" })).toEqual({
      ok: false,
      reason: "SIGNATURE_HEADER_MISSING",
    });
  });

  it("reconoce la cabecera sin importar mayúsculas", () => {
    expect(
      verifyDosaSignature({ headers: { "X-Dosa-Signature": "abc" }, rawBody: "{}" }),
    ).toEqual({ ok: false, reason: "SIGNATURE_CONTRACT_UNRESOLVED" });
  });

  it("con cabecera pero sin cuerpo crudo rechaza", () => {
    expect(
      verifyDosaSignature({ headers: { "x-dosa-signature": "abc" }, rawBody: undefined }),
    ).toEqual({ ok: false, reason: "RAW_BODY_UNAVAILABLE" });
  });

  it("NUNCA acepta: ningún valor de cabecera produce ok", () => {
    const values = ["", " ", "abc", "sha256=abc", "v1=abc", "0".repeat(64), "🙂"];
    for (const value of values) {
      const verdict = verifyDosaSignature({
        headers: { "x-dosa-signature": value },
        rawBody: Buffer.from("{}"),
      });
      expect(verdict.ok).toBe(false);
    }
  });

  it("declara explícitamente lo que falta del proveedor", () => {
    const pending = dosaSignatureContractPending();
    expect(pending.length).toBeGreaterThan(0);
    expect([...pending]).toEqual([...DOSA_SIGNATURE_CONTRACT_PENDING]);
    expect(pending.join(" ")).toMatch(/algoritmo/i);
  });
});

describe("DOSA webhook — sobre y receptor", () => {
  it("rechaza cuerpos que no son objetos", () => {
    expect(readDosaWebhookEnvelope(null).ok).toBe(false);
    expect(readDosaWebhookEnvelope([]).ok).toBe(false);
    expect(readDosaWebhookEnvelope("texto").ok).toBe(false);
  });

  it("lee identificadores si vienen, y no inventa los que faltan", () => {
    const withIds = readDosaWebhookEnvelope({ eventId: "evt-1", eventType: "cert.done" });
    expect(withIds).toMatchObject({
      ok: true,
      envelope: { eventId: "evt-1", eventType: "cert.done" },
    });

    const withoutIds = readDosaWebhookEnvelope({ data: 1 });
    expect(withoutIds).toMatchObject({
      ok: true,
      envelope: { eventId: null, eventType: null },
    });
  });

  it("el receptor rechaza SIEMPRE, incluso con cuerpo válido y firma plausible", () => {
    const receiver = new DosaWebhookReceiverService();
    const outcome = receiver.receive({
      headers: { "x-dosa-signature": "a".repeat(64) },
      rawBody: Buffer.from('{"eventId":"evt-1"}'),
      body: { eventId: "evt-1", eventType: "cert.done" },
    });

    expect(outcome.accepted).toBe(false);
    expect(outcome).toMatchObject({
      accepted: false,
      status: 503,
      code: "ECF_DOSA_WEBHOOK_BLOCKED",
      reason: "SIGNATURE_CONTRACT_UNRESOLVED",
    });
  });

  it("no filtra el valor de la firma ni el cuerpo en la respuesta", () => {
    const receiver = new DosaWebhookReceiverService();
    const secretValue = "SUPER-SECRETO-QUE-NO-DEBE-SALIR";
    const outcome = receiver.receive({
      headers: { "x-dosa-signature": secretValue },
      rawBody: Buffer.from(`{"token":"${secretValue}"}`),
      body: { token: secretValue },
    });

    expect(JSON.stringify(outcome)).not.toContain(secretValue);
  });
});

describe("DOSA — vinculación multiempresa", () => {
  it("normaliza separadores del RNC sin inventar formato", () => {
    expect(normalizeRnc(" 1-33-02023-2 ")).toBe("133020232");
    expect(normalizeRnc("")).toBeNull();
    expect(normalizeRnc(null)).toBeNull();
  });

  it("un RNC desconocido NO cae en ninguna empresa por defecto", () => {
    expect(resolveLinkedCompany([binding()], "999999999", "test")).toEqual({
      ok: false,
      reason: "UNKNOWN_RNC",
    });
  });

  it("un evento sin RNC se rechaza", () => {
    expect(resolveLinkedCompany([binding()], null, "test")).toEqual({
      ok: false,
      reason: "MISSING_RNC",
    });
  });

  it("dos vinculaciones con el mismo RNC son ambiguas, no 'la primera'", () => {
    expect(
      resolveLinkedCompany(
        [binding(), binding({ companyId: "company-b" })],
        "133020232",
        "test",
      ),
    ).toEqual({ ok: false, reason: "AMBIGUOUS_RNC" });
  });

  it("bloquea una vinculación cuyo RNC no es el fiscal de la empresa", () => {
    // La cuenta Partner (FULLTECH) no puede sustituir la identidad del cliente.
    expect(
      resolveLinkedCompany(
        [binding({ providerRnc: "130000000" })],
        "130000000",
        "test",
      ),
    ).toEqual({ ok: false, reason: "IDENTITY_MISMATCH" });
  });

  it("resuelve la empresa correcta cuando la identidad coincide", () => {
    expect(resolveLinkedCompany([binding()], "1-33-02023-2", "test")).toEqual({
      ok: true,
      companyId: "company-a",
    });
  });

  it("una vinculación de TEST no resuelve en producción", () => {
    expect(resolveLinkedCompany([binding()], "133020232", "production")).toEqual({
      ok: false,
      reason: "UNKNOWN_RNC",
    });
  });

  it("separa credenciales de prueba y de producción", () => {
    expect(assertEnvironmentIsolation(binding(), "test")).toEqual({ ok: true });
    expect(assertEnvironmentIsolation(binding(), "production")).toEqual({
      ok: false,
      reason: "ENVIRONMENT_MISMATCH",
    });
    expect(
      assertEnvironmentIsolation(binding({ environment: "production" }), "test"),
    ).toEqual({ ok: false, reason: "ENVIRONMENT_MISMATCH" });
  });

  it("la deduplicación se aísla por empresa", () => {
    expect(eventDedupeKey("company-a", "evt-1")).not.toBe(
      eventDedupeKey("company-b", "evt-1"),
    );
  });
});
