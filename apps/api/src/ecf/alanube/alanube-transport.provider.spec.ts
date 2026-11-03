import { ConfigService } from "@nestjs/config";
import { AlanubeRealHttpTransport } from "./alanube-real-http.transport";
import { AlanubeSimulatedTransport } from "./alanube-simulated.transport";
import { createAlanubeHttpTransport } from "./alanube-transport.provider";

function config(values: Record<string, string>) {
  return { get: jest.fn((key: string) => values[key]) } as any as ConfigService;
}

describe("createAlanubeHttpTransport", () => {
  it("uses simulated transport by default", () => {
    expect(createAlanubeHttpTransport(config({}))).toBeInstanceOf(AlanubeSimulatedTransport);
  });

  it("requires an independent Sandbox switch, real calls AND a complete sandbox config", () => {
    const complete = {
      ALANUBE_ENV: "sandbox",
      ALANUBE_HTTP_TRANSPORT_ENABLED: "true",
      ALANUBE_ENABLE_REAL_CALLS: "true",
      ALANUBE_BASE_URL: "https://sandbox.alanube.co/dom/v1",
      ALANUBE_TOKEN_SECRET_REF: "secret://alanube/sandbox-token",
    };
    expect(createAlanubeHttpTransport(config(complete))).toBeInstanceOf(
      AlanubeRealHttpTransport,
    );

    // Falla cerrado: con los interruptores puestos pero sin la credencial de
    // pruebas referenciada, NO se construye el transporte real.
    const { ALANUBE_TOKEN_SECRET_REF: _omit, ...withoutToken } = complete;
    expect(createAlanubeHttpTransport(config(withoutToken))).toBeInstanceOf(
      AlanubeSimulatedTransport,
    );

    // Y tampoco si la URL apunta a producción.
    expect(
      createAlanubeHttpTransport(
        config({ ...complete, ALANUBE_BASE_URL: "https://api.alanube.co/dom/v1" }),
      ),
    ).toBeInstanceOf(AlanubeSimulatedTransport);
  });

  it("blocks real transport outside Sandbox", () => {
    expect(
      createAlanubeHttpTransport(
        config({
          ALANUBE_ENV: "production",
          ALANUBE_HTTP_TRANSPORT_ENABLED: "true",
          ALANUBE_ENABLE_REAL_CALLS: "true",
          ALANUBE_BASE_URL: "https://sandbox.alanube.co/dom/v1",
          ALANUBE_TOKEN_SECRET_REF: "secret://alanube/sandbox-token",
        }),
      ),
    ).toBeInstanceOf(AlanubeSimulatedTransport);
  });
});
