import { ConfigService } from "@nestjs/config";
import { AlanubeSafeHttpClient } from "./alanube-safe-http.client";
import { AlanubeSimulatedTransport } from "./alanube-simulated.transport";
import type { AlanubeDomMapping } from "../fiscal-core/alanube-dom.contract";
import { ALANUBE_CONTRACT_FIXTURES } from "./alanube-contract.fixtures";
import { mapEcfToAlanubeDom } from "../fiscal-core/alanube-dom.mapper";

function config(values: Record<string, string | undefined>) {
  return {
    get: jest.fn((key: string) => values[key]),
  } as unknown as ConfigService;
}

const mapping: AlanubeDomMapping = mapEcfToAlanubeDom(ALANUBE_CONTRACT_FIXTURES[0].document);

describe("AlanubeSafeHttpClient", () => {
  it("builds a Sandbox request but keeps real calls disabled by default", async () => {
    const transport = new AlanubeSimulatedTransport();
    const client = new AlanubeSafeHttpClient(
      config({
        ALANUBE_ENV: "sandbox",
        ALANUBE_BASE_URL: "https://sandbox.alanube.co/dom/v1",
        ALANUBE_ENABLE_REAL_CALLS: "false",
        ALANUBE_TOKEN_SECRET_REF: "env://ALANUBE_SANDBOX_TOKEN",
      }),
      {
        resolve: jest.fn().mockResolvedValue({ provider: "env", value: "fake-token" }),
      } as any,
      transport,
    );

    await expect(client.prepareFiscalPost(mapping)).resolves.toEqual(
      expect.objectContaining({
        ok: false,
        errorCode: "REAL_CALLS_DISABLED",
      }),
    );
    expect(transport.calls).toHaveLength(0);
  });

  it("rejects production-like runtime configuration", async () => {
    const client = new AlanubeSafeHttpClient(
      config({ ALANUBE_ENV: "production" }),
      { resolve: jest.fn() } as any,
    );

    await expect(client.prepareFiscalPost(mapping)).resolves.toEqual(
      expect.objectContaining({
        ok: false,
        errorCode: "PRODUCTION_BLOCKED",
      }),
    );
  });

  it("redacts Authorization headers in simulated transport calls", async () => {
    const transport = new AlanubeSimulatedTransport({
      ok: true,
      response: {
        statusCode: 202,
        headers: {},
        body: { accepted: true },
        requestId: "simulated",
      },
    });
    const client = new AlanubeSafeHttpClient(
      config({
        ALANUBE_ENV: "sandbox",
        ALANUBE_BASE_URL: "https://sandbox.alanube.co/dom/v1",
        ALANUBE_ENABLE_REAL_CALLS: "true",
        ALANUBE_TOKEN_SECRET_REF: "env://ALANUBE_SANDBOX_TOKEN",
      }),
      {
        resolve: jest.fn().mockResolvedValue({ provider: "env", value: "fake-token" }),
      } as any,
      transport,
    );

    const result = await client.prepareFiscalPost(mapping);
    expect(result).toMatchObject({ ok: false, errorCode: "CONFIGURATION_ERROR" });
    expect(transport.calls).toHaveLength(0);
    // Verify the simulated transport's independent redaction using a local request.
    await transport.execute(client.buildRequest(mapping, "fake-token"));

    expect(JSON.stringify(transport.calls)).not.toContain("fake-token");
    expect(transport.calls[0].headers.Authorization).toBe("[REDACTED]");
  });

  it("never resolves credentials or sends with incomplete contracts", async () => {
    const secrets = { resolve: jest.fn() };
    const transport = { execute: jest.fn() };
    const client = new AlanubeSafeHttpClient(config({ ALANUBE_ENV: "sandbox", ALANUBE_ENABLE_REAL_CALLS: "true" }), secrets as any, transport);
    await expect(client.prepareFiscalPost(mapping)).resolves.toMatchObject({ ok: false });
    expect(secrets.resolve).not.toHaveBeenCalled();
    expect(transport.execute).not.toHaveBeenCalled();
  });

  it("rejects URLs outside the documented Sandbox host", () => {
    const client = new AlanubeSafeHttpClient(
      config({
        ALANUBE_BASE_URL: "https://api.alanube.co/dom/v1",
      }),
      {} as any,
    );

    expect(() => client.buildRequest(mapping, "fake-token")).toThrow(
      "URL Alanube Sandbox no permitida.",
    );
  });

  it.each(ALANUBE_CONTRACT_FIXTURES)("invalid $name never reaches transport or secret resolution", async ({ document, metadata }) => {
    const mapping = mapEcfToAlanubeDom(document, metadata);
    (mapping.payload.totals as any).totalAmount = "invalid";
    const transport = { execute: jest.fn() };
    const secrets = { resolve: jest.fn() };
    const client = new AlanubeSafeHttpClient(config({ ALANUBE_ENV: "sandbox", ALANUBE_ENABLE_REAL_CALLS: "true" }), secrets as any, transport);
    await expect(client.prepareFiscalPost(mapping)).resolves.toMatchObject({ ok: false, safeMessage: "Payload DOM inválido; transporte no invocado." });
    expect(transport.execute).not.toHaveBeenCalled();
    expect(secrets.resolve).not.toHaveBeenCalled();
  });
});
