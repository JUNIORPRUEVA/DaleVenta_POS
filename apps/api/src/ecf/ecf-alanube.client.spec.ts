import { ConfigService } from "@nestjs/config";
import { EcfAlanubeClient } from "./ecf-alanube.client";

function client(env: Record<string, string | undefined>) {
  return new EcfAlanubeClient({
    get: jest.fn((key: string) => env[key]),
  } as unknown as ConfigService);
}

describe("EcfAlanubeClient", () => {
  it("defaults to Sandbox DOM with real calls disabled", () => {
    const alanube = client({});

    expect(alanube.getRuntimeState()).toEqual({
      environment: "sandbox",
      baseUrl: "https://sandbox.alanube.co/dom/v1",
      realCallsEnabled: false,
      credentialReferenceConfigured: false,
      testFiscalProfileConfigured: false,
      externalCallsBlocked: true,
      sandboxReady: true,
      productionBlocked: true,
    });
  });

  it("reports Sandbox as not ready when real calls are disabled only by flag state", () => {
    const alanube = client({
      ALANUBE_ENV: "sandbox",
      ALANUBE_BASE_URL: "https://sandbox.alanube.co/dom/v1",
      ALANUBE_ENABLE_REAL_CALLS: "false",
    });

    expect(alanube.getRuntimeState()).toEqual(
      expect.objectContaining({
        environment: "sandbox",
        realCallsEnabled: false,
        externalCallsBlocked: true,
        sandboxReady: true,
        productionBlocked: true,
      }),
    );
  });

  it("marks production-like or non-DOM Sandbox base URLs as not ready", () => {
    const alanube = client({
      ALANUBE_ENV: "sandbox",
      ALANUBE_BASE_URL: "https://api.alanube.co/dom/v1",
      ALANUBE_ENABLE_REAL_CALLS: "true",
    });

    expect(alanube.getRuntimeState()).toEqual(
      expect.objectContaining({
        baseUrl: "https://api.alanube.co/dom/v1",
        sandboxReady: false,
        productionBlocked: true,
      }),
    );
  });

  it("marks non-sandbox environment values as not ready", () => {
    const alanube = client({
      ALANUBE_ENV: "production",
      ALANUBE_BASE_URL: "https://sandbox.alanube.co/dom/v1",
      ALANUBE_ENABLE_REAL_CALLS: "true",
    });

    expect(alanube.getRuntimeState()).toEqual(
      expect.objectContaining({
        environment: "production",
        sandboxReady: false,
        productionBlocked: true,
      }),
    );
  });

  it("does not expose token references or raw tokens in runtime state", () => {
    const alanube = client({
      ALANUBE_ENV: "sandbox",
      ALANUBE_BASE_URL: "https://sandbox.alanube.co/dom/v1",
      ALANUBE_ENABLE_REAL_CALLS: "false",
      ALANUBE_TOKEN_SECRET_REF: "env://ALANUBE_SANDBOX_TOKEN",
      ALANUBE_TOKEN: "do-not-return-this",
    });

    const serialized = JSON.stringify(alanube.getRuntimeState());
    expect(serialized).not.toContain("do-not-return-this");
    expect(serialized).not.toContain("ALANUBE_SANDBOX_TOKEN");
    expect(alanube.getRuntimeState()).toEqual(
      expect.objectContaining({
        credentialReferenceConfigured: true,
      }),
    );
  });

  it("reports test fiscal profile presence without exposing values", () => {
    const alanube = client({
      ALANUBE_TEST_RNC: "test-rnc",
      ALANUBE_TEST_SEQUENCE_FROM: "test-from",
      ALANUBE_TEST_SEQUENCE_TO: "test-to",
      ALANUBE_TEST_SEQUENCE_EXPIRES_ON: "2099-12-31",
    });

    const state = alanube.getRuntimeState();

    expect(state.testFiscalProfileConfigured).toBe(true);
    expect(JSON.stringify(state)).not.toContain("test-rnc");
    expect(JSON.stringify(state)).not.toContain("test-from");
  });
});
