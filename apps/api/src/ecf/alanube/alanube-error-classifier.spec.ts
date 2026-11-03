import { classifyAlanubeTransportResult } from "./alanube-error-classifier";

describe("classifyAlanubeTransportResult", () => {
  it("classifies auth, validation, rate limit and unknown outcomes safely", () => {
    expect(
      classifyAlanubeTransportResult({
        ok: true,
        response: { statusCode: 401, headers: {}, body: {}, requestId: "r1" },
      }),
    ).toEqual(expect.objectContaining({ class: "AUTHENTICATION", retryable: false }));
    expect(
      classifyAlanubeTransportResult({
        ok: true,
        response: { statusCode: 422, headers: {}, body: {}, requestId: "r2" },
      }),
    ).toEqual(expect.objectContaining({ class: "VALIDATION", retryable: false }));
    expect(
      classifyAlanubeTransportResult({
        ok: true,
        response: { statusCode: 429, headers: {}, body: {}, requestId: "r3" },
      }),
    ).toEqual(expect.objectContaining({ class: "RATE_LIMIT", retryable: false }));
    expect(
      classifyAlanubeTransportResult({
        ok: true,
        response: { statusCode: 503, headers: {}, body: {}, requestId: "r4" },
      }),
    ).toEqual(expect.objectContaining({ class: "UNKNOWN_OUTCOME", requiresHumanReview: true }));
  });

  it("only permits retry classification for explicitly read-only operations", () => {
    const result = { ok: false as const, errorCode: "TIMEOUT" as const, safeMessage: "timeout", requestId: "synthetic" };
    expect(classifyAlanubeTransportResult(result).retryable).toBe(false);
    expect(classifyAlanubeTransportResult(result, "READ").retryable).toBe(true);
    expect(classifyAlanubeTransportResult({ ok: true, response: { statusCode: 200, headers: {}, body: {}, requestId: "synthetic" } }).class).toBe("UNKNOWN_OUTCOME");
  });
});
