import {
  DOSA_OUTBOUND_BLOCKED,
  outboundAuthViolation,
} from "./dosa-outbound-auth.policy";

/**
 * La autenticación SALIENTE no es la firma del webhook ENTRANTE.
 *
 * Este archivo fija esa separación con código: una petición de emisión lleva
 * exactamente `Content-Type` + API Key de la empresa. Si alguien añade la
 * cabecera de firma o usa el secreto del webhook como clave, se bloquea antes
 * de la red.
 */
describe("outboundAuthViolation", () => {
  const ok = { "Content-Type": "application/json", "X-API-KEY": "sk_test_FICTICIA" };

  it("acepta la petición canónica", () => {
    expect(outboundAuthViolation(ok, { apiKey: "sk_test_FICTICIA" })).toBeNull();
  });

  it("acepta la cabecera de API Key en cualquier capitalización", () => {
    expect(
      outboundAuthViolation(
        { "content-type": "application/json", "x-api-key": "sk_test_FICTICIA" },
        { apiKey: "sk_test_FICTICIA" },
      ),
    ).toBeNull();
  });

  it("bloquea la cabecera de firma del webhook", () => {
    expect(
      outboundAuthViolation(
        { ...ok, "X-Dosa-Signature": "t=1,v1=abc" },
        { apiKey: "sk_test_FICTICIA" },
      ),
    ).toContain(DOSA_OUTBOUND_BLOCKED.signatureHeader);
  });

  it("bloquea cualquier cabecera no prevista", () => {
    expect(
      outboundAuthViolation({ ...ok, Authorization: "Bearer x" }, { apiKey: "sk_test_FICTICIA" }),
    ).toContain(DOSA_OUTBOUND_BLOCKED.unexpectedHeader);
  });

  it("exige la cabecera de API Key", () => {
    expect(outboundAuthViolation({ "Content-Type": "application/json" })).toBe(
      DOSA_OUTBOUND_BLOCKED.apiKeyMissing,
    );
  });

  it("rechaza un secreto de webhook enviado como API Key", () => {
    expect(
      outboundAuthViolation(
        { "Content-Type": "application/json", "X-API-KEY": "t=1730000000,v1=deadbeef" },
        { apiKey: "t=1730000000,v1=deadbeef" },
      ),
    ).toBe(DOSA_OUTBOUND_BLOCKED.apiKeyLooksLikeSignature);
  });

  it("una API Key normal con guiones no se confunde con una firma", () => {
    expect(
      outboundAuthViolation(ok, { apiKey: "sk-test-1234-abcd" }),
    ).toBeNull();
  });
});
