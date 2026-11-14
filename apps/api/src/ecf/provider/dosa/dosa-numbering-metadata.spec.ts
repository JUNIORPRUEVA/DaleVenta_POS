import { extractDosaNumberingMetadata } from "./dosa-numbering-metadata";
import { parseDosaWebhookPayload, redactDosaWebhookEvent } from "./dosa-webhook.dto";

describe("DOSA numbering evidence (never fiscal authority)", () => {
  it("preserves separate provider TEST/production evidence while stripping credentials and arbitrary text", () => {
    const body = {
      rnc: "133306001", razon_social: "Synthetic", ambiente: "Produccion",
      credenciales: { api_key_test: "test-secret-do-not-log" },
      secuencias: {
        test: [{ tipo: "E31", desde: 113500, hasta: 115500, vencimiento: "31/12/2028", api_key: "never-store", nota: "arbitrary" }],
        produccion: [{ tipo: "E31", desde: 1, hasta: 1000, vencimiento: "31/12/2027" }],
      },
    };
    const parsed = parseDosaWebhookPayload(body);
    if (!parsed.ok) throw Error(parsed.reason);
    const saved = redactDosaWebhookEvent(parsed.value.payload);
    expect(saved.numberingMetadata).toEqual({ secuencias: {
      test: [{ tipo: "E31", desde: 113500, hasta: 115500, vencimiento: "31/12/2028" }],
      produccion: [{ tipo: "E31", desde: 1, hasta: 1000, vencimiento: "31/12/2027" }],
    } });
    expect(JSON.stringify(saved)).not.toMatch(/test-secret|never-store|arbitrary/);
  });
  it("does not infer a TEST range from a production event", () => {
    expect(extractDosaNumberingMetadata({ ambiente: "Produccion", credenciales: { api_key_test: "secret" } })).toBeUndefined();
  });
  it("rejects secret-like values even under a recognized fiscal field", () => {
    expect(extractDosaNumberingMetadata({ secuencias: [{ tipo: "api-key-secret", desde: "secret", hasta: -2, vencimiento: "not-a-date" }] }))
      .toEqual({ secuencias: [] });
  });
});
