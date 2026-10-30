import {
  ALANUBE_AUTH_CONTRACT,
  ALANUBE_CONTRACT_BLOCKERS,
  ALANUBE_DOM_ENDPOINTS,
  ALANUBE_DOM_SANDBOX_BASE_URL,
} from "./alanube-contract-matrix";

describe("Alanube DOM contract matrix", () => {
  it("documents the confirmed public endpoints for E31, E32 and E34", () => {
    expect(ALANUBE_DOM_SANDBOX_BASE_URL).toBe(
      "https://sandbox.alanube.co/dom/v1",
    );
    expect(ALANUBE_AUTH_CONTRACT).toEqual(
      expect.objectContaining({
        scheme: "JWT_BEARER_TOKEN",
        header: "Authorization",
      }),
    );
    expect(ALANUBE_DOM_ENDPOINTS).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          documentType: "E31",
          alanubePath: "/fiscal-invoices",
        }),
        expect.objectContaining({
          documentType: "E32",
          alanubePath: "/invoices",
        }),
        expect.objectContaining({
          documentType: "E34",
          alanubePath: "/credit-notes",
        }),
      ]),
    );
  });

  it("keeps fiscal semantics and provider idempotency blocked despite available schemas", () => {
    expect(ALANUBE_CONTRACT_BLOCKERS).toEqual(
      expect.arrayContaining([
        expect.stringContaining("OpenAPI/JSON Schema"),
        expect.stringContaining("idempotencia"),
      ]),
    );
  });
});
