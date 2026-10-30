import { decideAlanubeRetry } from "./alanube-retry.policy";

describe("decideAlanubeRetry", () => {
  it("does not retry non-idempotent emissions", () => {
    expect(
      decideAlanubeRetry({
        operation: "EMISSION",
        errorClass: "TIMEOUT",
        attempt: 0,
        idempotent: false,
      }),
    ).toEqual({ retry: false, reason: "NON_IDEMPOTENT_EMISSION" });
  });

  it("retries safe transient reads with backoff", () => {
    expect(
      decideAlanubeRetry({
        operation: "READ",
        errorClass: "NETWORK",
        attempt: 1,
        idempotent: true,
      }),
    ).toEqual({ retry: true, delayMs: 2000, reason: "NETWORK" });
  });

  it("does not equate local idempotence with provider guarantees", () => {
    for (const errorClass of ["TIMEOUT", "NETWORK", "RATE_LIMIT", "UNKNOWN_OUTCOME"] as const) {
      expect(decideAlanubeRetry({ operation: "EMISSION", errorClass, attempt: 0, idempotent: true }))
        .toEqual({ retry: false, reason: "PROVIDER_IDEMPOTENCY_UNVERIFIED" });
    }
  });
});
