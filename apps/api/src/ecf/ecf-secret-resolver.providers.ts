import { access, constants, readFile } from "node:fs/promises";
import { execFile } from "node:child_process";
import { promisify } from "node:util";
import { ConfigService } from "@nestjs/config";
import { EcfSecretResolverError } from "./ecf-secret-resolver.error";
import type {
  EcfResolvedSecret,
  EcfSecretInspection,
  EcfSecretProvider,
  EcfSecretProviderKind,
} from "./ecf-secret-resolver.types";

const execFileAsync = promisify(execFile);

function configured(provider: EcfSecretProviderKind): EcfSecretInspection {
  return {
    referenceConfigured: true,
    provider,
    credentialFound: false,
    credentialAccessibleByProcess: false,
    resolutionSupported: false,
  };
}

export class EcfEnvSecretProvider implements EcfSecretProvider {
  readonly kind = "env" as const;

  constructor(private readonly config: ConfigService) {}

  supports(reference: string) {
    return reference.startsWith("env://");
  }

  async inspect(reference: string): Promise<EcfSecretInspection> {
    const value = this.read(reference);
    return {
      ...configured(this.kind),
      credentialFound: Boolean(value),
      credentialAccessibleByProcess: Boolean(value),
      resolutionSupported: true,
    };
  }

  async resolve(reference: string): Promise<EcfResolvedSecret> {
    const value = this.read(reference);
    if (!value) {
      throw new EcfSecretResolverError(
        "SECRET_NOT_FOUND",
        "La credencial solicitada no está disponible.",
        this.kind,
      );
    }
    return { provider: this.kind, value };
  }

  private read(reference: string) {
    const name = reference.slice("env://".length);
    if (!/^[A-Z][A-Z0-9_]{2,128}$/.test(name)) {
      throw new EcfSecretResolverError(
        "INVALID_REFERENCE",
        "La referencia de secreto es inválida.",
        this.kind,
      );
    }
    return (this.config.get<string>(name) ?? process.env[name] ?? "").trim();
  }
}

export class EcfDockerSecretFileProvider implements EcfSecretProvider {
  readonly kind = "docker-secret" as const;

  constructor(private readonly baseDir = process.env.ECF_DOCKER_SECRETS_DIR ?? "/run/secrets") {}

  supports(reference: string) {
    return reference.startsWith("secret://docker/");
  }

  async inspect(reference: string): Promise<EcfSecretInspection> {
    const path = this.pathFrom(reference);
    try {
      await access(path, constants.R_OK);
      return {
        ...configured(this.kind),
        credentialFound: true,
        credentialAccessibleByProcess: true,
        resolutionSupported: true,
      };
    } catch {
      return configured(this.kind);
    }
  }

  async resolve(reference: string): Promise<EcfResolvedSecret> {
    const path = this.pathFrom(reference);
    try {
      const value = (await readFile(path, "utf8")).trim();
      if (!value) {
        throw new EcfSecretResolverError(
          "SECRET_NOT_FOUND",
          "La credencial solicitada no está disponible.",
          this.kind,
        );
      }
      return { provider: this.kind, value };
    } catch (error) {
      if (error instanceof EcfSecretResolverError) throw error;
      throw new EcfSecretResolverError(
        "ACCESS_DENIED",
        "La credencial solicitada no pudo leerse.",
        this.kind,
      );
    }
  }

  private pathFrom(reference: string) {
    const name = reference.slice("secret://docker/".length);
    if (!/^[A-Za-z0-9._-]{3,128}$/.test(name)) {
      throw new EcfSecretResolverError(
        "INVALID_REFERENCE",
        "La referencia de secreto es inválida.",
        this.kind,
      );
    }
    return `${this.baseDir.replace(/[\\/]+$/, "")}/${name}`;
  }
}

export class EcfWindowsCredentialManagerProvider implements EcfSecretProvider {
  readonly kind = "windows-credential-manager" as const;

  supports(reference: string) {
    return reference.startsWith("secret://windows/");
  }

  async inspect(reference: string): Promise<EcfSecretInspection> {
    const target = this.targetFrom(reference);
    if (process.platform !== "win32") {
      return configured(this.kind);
    }
    try {
      await execFileAsync("cmdkey.exe", [`/list:${target}`], {
        windowsHide: true,
        timeout: 5000,
      });
      return {
        ...configured(this.kind),
        credentialFound: true,
        credentialAccessibleByProcess: true,
      };
    } catch {
      return configured(this.kind);
    }
  }

  async resolve(reference: string): Promise<EcfResolvedSecret> {
    this.targetFrom(reference);
    throw new EcfSecretResolverError(
      "RESOLUTION_UNSUPPORTED",
      "Windows Credential Manager requiere integración nativa segura antes de resolver secretos.",
      this.kind,
    );
  }

  private targetFrom(reference: string) {
    const target = reference.slice("secret://windows/".length);
    if (!/^[A-Za-z0-9._:@/-]{3,160}$/.test(target)) {
      throw new EcfSecretResolverError(
        "INVALID_REFERENCE",
        "La referencia de secreto es inválida.",
        this.kind,
      );
    }
    return target;
  }
}
