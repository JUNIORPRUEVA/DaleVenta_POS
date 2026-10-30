import { ConfigService } from "@nestjs/config";
import {
  EcfEnvSecretProvider,
  EcfWindowsCredentialManagerProvider,
} from "./ecf-secret-resolver.providers";

describe("Ecf secret providers", () => {
  it("resolves env:// references without exposing values in inspection", async () => {
    const provider = new EcfEnvSecretProvider({
      get: jest.fn((key: string) =>
        key === "ALANUBE_SANDBOX_TOKEN" ? "fake-token" : undefined,
      ),
    } as unknown as ConfigService);

    await expect(provider.inspect("env://ALANUBE_SANDBOX_TOKEN")).resolves.toEqual({
      referenceConfigured: true,
      provider: "env",
      credentialFound: true,
      credentialAccessibleByProcess: true,
      resolutionSupported: true,
    });
    await expect(provider.resolve("env://ALANUBE_SANDBOX_TOKEN")).resolves.toEqual(
      { provider: "env", value: "fake-token" },
    );
  });

  it("rejects invalid env variable names safely", async () => {
    const provider = new EcfEnvSecretProvider({} as ConfigService);

    await expect(provider.resolve("env://bad-name")).rejects.toMatchObject({
      code: "INVALID_REFERENCE",
      safeMessage: "La referencia de secreto es inválida.",
    });
  });

  it("does not resolve Windows Credential Manager references in this phase", async () => {
    const provider = new EcfWindowsCredentialManagerProvider();

    await expect(
      provider.resolve("secret://windows/FullPOS-Alanube-SandboxToken"),
    ).rejects.toMatchObject({
      code: "RESOLUTION_UNSUPPORTED",
      safeMessage:
        "Windows Credential Manager requiere integración nativa segura antes de resolver secretos.",
    });
  });
});
