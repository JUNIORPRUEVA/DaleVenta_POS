import { interpretAlanubeResponse, interpretAlanubeResult } from "./alanube-response-interpreter";

describe("interpretAlanubeResponse", () => {
  it("does not treat HTTP success as DGII acceptance", () => {
    expect(
      interpretAlanubeResponse({
        statusCode: 200,
        headers: {},
        body: { id: "provider-id" },
        requestId: "req",
      }),
    ).toEqual(
      expect.objectContaining({
        kind: "UNKNOWN_RESULT",
        safeCode: "ALANUBE_RESPONSE_SCHEMA_UNVERIFIED",
        safeMessage: expect.stringContaining("no equivale"),
      }),
    );
  });

  it("classifies common HTTP errors safely", () => {
    expect(interpretAlanubeResponse({ statusCode: 401, headers: {}, body: {}, requestId: "r" }).kind).toBe("AUTHENTICATION_ERROR");
    expect(interpretAlanubeResponse({ statusCode: 403, headers: {}, body: {}, requestId: "r" }).kind).toBe("AUTHORIZATION_ERROR");
    expect(interpretAlanubeResponse({ statusCode: 422, headers: {}, body: {}, requestId: "r" }).kind).toBe("VALIDATION_ERROR");
    expect(interpretAlanubeResponse({ statusCode: 429, headers: {}, body: {}, requestId: "r" }).kind).toBe("RATE_LIMIT");
  });

  it("marks network failures as unknown outcomes without provider assumptions", () => {
    expect(
      interpretAlanubeResult({
        ok: false,
        errorCode: "TIMEOUT",
        safeMessage: "timeout",
        requestId: "r",
      }),
    ).toEqual(
      expect.objectContaining({
        kind: "UNKNOWN_RESULT",
      }),
    );
  });

  it.each(["E31", "E32", "E34"] as const)("observes official %s processing without creating accepted states", (documentType) => {
    const result = interpretAlanubeResponse({ statusCode: 201, headers: {}, requestId: "synthetic",
      body: { id: "01FVJ1528AQRBC7D6K2TGVE5S5", status: "REGISTERED" } }, documentType);
    expect(result).toMatchObject({ kind: "UNKNOWN_RESULT", safeCode: "ALANUBE_PROCESSING_OBSERVED", providerStatus: "REGISTERED" });
  });

  it("records E32 legalStatus as an observation only, never fiscal acceptance", () => {
    const result = interpretAlanubeResponse({ statusCode: 201, headers: {}, requestId: "synthetic",
      body: { id: "01FVJ1528AQRBC7D6K2TGVE5S5", status: "FINISHED", legalStatus: "ACCEPTED" } }, "E32");
    expect(result).toMatchObject({ kind: "UNKNOWN_RESULT", observedLegalStatus: "ACCEPTED" });
  });

  it.each([{}, { id: "not-a-ulid", status: "FINISHED" }, { id: "01FVJ1528AQRBC7D6K2TGVE5S5", status: "FAKE_ACCEPTED" }, "unexpected"])("rejects incomplete/unverified response evidence %#", (body) => {
    const result = interpretAlanubeResponse({ statusCode: 201, headers: {}, requestId: "synthetic", body }, "E31");
    expect(result.kind).toBe("UNKNOWN_RESULT");
    expect(result).not.toHaveProperty("providerDocumentId");
  });

  it.each([[401, "AUTHENTICATION_ERROR"], [403, "AUTHORIZATION_ERROR"], [400, "VALIDATION_ERROR"],
    [429, "RATE_LIMIT"], [503, "UNKNOWN_RESULT"], [302, "UNEXPECTED_RESPONSE"]])("classifies HTTP %s without invented fiscal codes", (statusCode, kind) => {
    expect(interpretAlanubeResponse({ statusCode: statusCode as number, headers: {}, requestId: "synthetic", body: {} }, "E31").kind).toBe(kind);
  });

  it.each(["TIMEOUT", "NETWORK_ERROR"] as const)("keeps %s unknown and does not leak provider messages", (errorCode) => {
    const result = interpretAlanubeResult({ ok: false, errorCode, requestId: "synthetic", safeMessage: "raw-sensitive-message" }, "E31");
    expect(result.kind).toBe("UNKNOWN_RESULT");
    expect(JSON.stringify(result)).not.toContain("raw-sensitive-message");
  });
});
