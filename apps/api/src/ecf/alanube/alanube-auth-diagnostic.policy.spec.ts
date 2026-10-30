import {
  ALANUBE_AUTH_DIAGNOSTIC_ENDPOINT,
  assertAlanubeAuthDiagnosticPolicy,
} from "./alanube-auth-diagnostic.policy";

const allowed = {
  method: "GET",
  url: ALANUBE_AUTH_DIAGNOSTIC_ENDPOINT,
  environment: "sandbox",
  realCallsEnabled: false,
  emissionEnabled: false,
  authTestsEnabled: false,
};

describe("assertAlanubeAuthDiagnosticPolicy", () => {
  it("allows only the documented self-company Sandbox GET endpoint", () => {
    expect(assertAlanubeAuthDiagnosticPolicy(allowed)).toEqual({ ok: true });
  });

  it("blocks unsafe methods and endpoints", () => {
    expect(assertAlanubeAuthDiagnosticPolicy({ ...allowed, method: "POST" })).toEqual(
      expect.objectContaining({ ok: false, code: "METHOD_NOT_ALLOWED" }),
    );
    expect(
      assertAlanubeAuthDiagnosticPolicy({
        ...allowed,
        url: "https://sandbox.alanube.co/dom/v1/invoices",
      }),
    ).toEqual(expect.objectContaining({ ok: false, code: "ENDPOINT_NOT_ALLOWED" }));
  });

  it("blocks production and global auth flags", () => {
    expect(
      assertAlanubeAuthDiagnosticPolicy({ ...allowed, environment: "production" }),
    ).toEqual(expect.objectContaining({ ok: false, code: "PRODUCTION_BLOCKED" }));
    expect(
      assertAlanubeAuthDiagnosticPolicy({ ...allowed, realCallsEnabled: true }),
    ).toEqual(expect.objectContaining({ ok: false, code: "GLOBAL_REAL_CALLS_BLOCKED" }));
    expect(
      assertAlanubeAuthDiagnosticPolicy({ ...allowed, authTestsEnabled: true }),
    ).toEqual(expect.objectContaining({ ok: false, code: "GLOBAL_AUTH_TESTS_BLOCKED" }));
  });
});
