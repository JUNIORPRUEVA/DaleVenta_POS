import { ConfigService } from "@nestjs/config";
import { EcfSecretResolverError } from "./ecf-secret-resolver.error";
import { EcfSecretResolverService } from "./ecf-secret-resolver.service";
import type {
  EcfResolvedSecret,
  EcfSecretInspection,
  EcfSecretProvider,
} from "./ecf-secret-resolver.types";

class FakeProvider implements EcfSecretProvider {
  readonly kind = "env" as const;

  constructor(
    private readonly values: Record<string, string>,
    private readonly accessDenied = false,
  ) {}

  supports(reference: string) {
    return reference.startsWith("env://");
  }

  async inspect(reference: string): Promise<EcfSecretInspection> {
    const found = Boolean(this.values[reference]);
    return {
      referenceConfigured: true,
      provider: this.kind,
      credentialFound: found,
      credentialAccessibleByProcess: found && !this.accessDenied,
      resolutionSupported: true,
    };
  }

  async resolve(reference: string): Promise<EcfResolvedSecret> {
    if (this.accessDenied) {
      throw new EcfSecretResolverError(
        "ACCESS_DENIED",
        "La credencial solicitada no pudo leerse.",
        this.kind,
      );
    }
    const value = this.values[reference];
    if (!value) {
      throw new EcfSecretResolverError(
        "SECRET_NOT_FOUND",
        "La credencial solicitada no está disponible.",
        this.kind,
      );
    }
    return { provider: this.kind, value };
  }
}

function resolver(provider: EcfSecretProvider) {
  return new EcfSecretResolverService({} as ConfigService, [provider]);
}

describe("EcfSecretResolverService", () => {
  const context = {
    companyId: "company-a",
    environment: "sandbox" as const,
    allowedReferences: ["env://ALANUBE_SANDBOX_TOKEN"],
  };

  it("resolves a fictitious secret through an authorized provider", async () => {
    const service = resolver(
      new FakeProvider({ "env://ALANUBE_SANDBOX_TOKEN": "fake-token" }),
    );

    await expect(
      service.resolve("env://ALANUBE_SANDBOX_TOKEN", context),
    ).resolves.toEqual({ provider: "env", value: "fake-token" });
  });

  it("reports configured, found and accessible states without exposing values", async () => {
    const service = resolver(
      new FakeProvider({ "env://ALANUBE_SANDBOX_TOKEN": "fake-token" }),
    );

    const inspection = await service.inspect(
      "env://ALANUBE_SANDBOX_TOKEN",
      context,
    );

    expect(inspection).toEqual({
      referenceConfigured: true,
      provider: "env",
      credentialFound: true,
      credentialAccessibleByProcess: true,
      resolutionSupported: true,
    });
    expect(JSON.stringify(inspection)).not.toContain("fake-token");
  });

  it("rejects empty references with a safe error", async () => {
    const service = resolver(new FakeProvider({}));

    await expect(service.resolve("", context)).rejects.toMatchObject({
      code: "EMPTY_REFERENCE",
      safeMessage: "La referencia de secreto es requerida.",
    });
  });

  it("rejects unsupported providers", async () => {
    const service = resolver(new FakeProvider({}));

    await expect(
      service.resolve("vault://missing-provider/token", {
        ...context,
        allowedReferences: ["vault://missing-provider/token"],
      }),
    ).rejects.toMatchObject({
      code: "UNSUPPORTED_PROVIDER",
      safeMessage: "El proveedor de secretos no está permitido.",
    });
  });

  it("rejects missing credentials without including the reference or token", async () => {
    const service = resolver(new FakeProvider({}));

    await expect(
      service.resolve("env://ALANUBE_SANDBOX_TOKEN", context),
    ).rejects.toMatchObject({
      code: "SECRET_NOT_FOUND",
      safeMessage: "La credencial solicitada no está disponible.",
    });
  });

  it("redacts access denied errors", async () => {
    const service = resolver(
      new FakeProvider({ "env://ALANUBE_SANDBOX_TOKEN": "fake-token" }, true),
    );

    await expect(
      service.resolve("env://ALANUBE_SANDBOX_TOKEN", context),
    ).rejects.toMatchObject({
      code: "ACCESS_DENIED",
      safeMessage: "La credencial solicitada no pudo leerse.",
    });
  });

  it("prevents cross-company references when an allow-list is provided", async () => {
    const service = resolver(
      new FakeProvider({ "env://OTHER_COMPANY_TOKEN": "fake-token" }),
    );

    await expect(
      service.resolve("env://OTHER_COMPANY_TOKEN", context),
    ).rejects.toMatchObject({
      code: "REFERENCE_NOT_ALLOWED",
      safeMessage: "La referencia de secreto no está autorizada para esta empresa.",
    });
  });

  it("blocks production resolution unless explicitly enabled", async () => {
    const service = resolver(
      new FakeProvider({ "env://ALANUBE_SANDBOX_TOKEN": "fake-token" }),
    );

    await expect(
      service.resolve("env://ALANUBE_SANDBOX_TOKEN", {
        ...context,
        environment: "production",
      }),
    ).rejects.toMatchObject({
      code: "PRODUCTION_BLOCKED",
      safeMessage: "La resolución de secretos productivos no está habilitada.",
    });
  });

  it("allows production resolution only when the caller opts in explicitly", async () => {
    const service = resolver(
      new FakeProvider({ "env://ALANUBE_SANDBOX_TOKEN": "fake-token" }),
    );

    await expect(
      service.resolve("env://ALANUBE_SANDBOX_TOKEN", {
        ...context,
        environment: "production",
        allowProductionResolution: true,
      }),
    ).resolves.toEqual({ provider: "env", value: "fake-token" });
  });
});
