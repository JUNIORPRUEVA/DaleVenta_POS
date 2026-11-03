import { Injectable } from "@nestjs/common";
import { ConfigService } from "@nestjs/config";
import { EcfSecretResolverError } from "./ecf-secret-resolver.error";
import {
  EcfDockerSecretFileProvider,
  EcfEnvSecretProvider,
  EcfWindowsCredentialManagerProvider,
} from "./ecf-secret-resolver.providers";
import type {
  EcfResolvedSecret,
  EcfSecretInspection,
  EcfSecretProvider,
  EcfSecretResolutionContext,
} from "./ecf-secret-resolver.types";

@Injectable()
export class EcfSecretResolverService {
  private readonly providers: EcfSecretProvider[];

  constructor(config: ConfigService, providers?: EcfSecretProvider[]) {
    this.providers =
      providers ??
      [
        new EcfEnvSecretProvider(config),
        new EcfDockerSecretFileProvider(),
        new EcfWindowsCredentialManagerProvider(),
      ];
  }

  async inspect(
    reference: string | null | undefined,
    context: EcfSecretResolutionContext,
  ): Promise<EcfSecretInspection> {
    const normalized = this.normalize(reference);
    this.assertContext(normalized, context);
    return this.providerFor(normalized).inspect(normalized);
  }

  async resolve(
    reference: string | null | undefined,
    context: EcfSecretResolutionContext,
  ): Promise<EcfResolvedSecret> {
    const normalized = this.normalize(reference);
    this.assertContext(normalized, context);
    return this.providerFor(normalized).resolve(normalized);
  }

  private normalize(reference: string | null | undefined) {
    const normalized = `${reference ?? ""}`.trim();
    if (!normalized) {
      throw new EcfSecretResolverError(
        "EMPTY_REFERENCE",
        "La referencia de secreto es requerida.",
      );
    }
    if (normalized.includes("\n") || normalized.includes("\r")) {
      throw new EcfSecretResolverError(
        "INVALID_REFERENCE",
        "La referencia de secreto es inválida.",
      );
    }
    return normalized;
  }

  private assertContext(reference: string, context: EcfSecretResolutionContext) {
    if (context.environment === "production" && !context.allowProductionResolution) {
      throw new EcfSecretResolverError(
        "PRODUCTION_BLOCKED",
        "La resolución de secretos productivos no está habilitada.",
      );
    }
    if (
      context.allowedReferences &&
      !context.allowedReferences.includes(reference)
    ) {
      throw new EcfSecretResolverError(
        "REFERENCE_NOT_ALLOWED",
        "La referencia de secreto no está autorizada para esta empresa.",
      );
    }
  }

  private providerFor(reference: string) {
    const provider = this.providers.find((candidate) =>
      candidate.supports(reference),
    );
    if (!provider) {
      throw new EcfSecretResolverError(
        "UNSUPPORTED_PROVIDER",
        "El proveedor de secretos no está permitido.",
      );
    }
    return provider;
  }
}
