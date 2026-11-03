import type { EcfSecretProviderKind, EcfSecretResolverErrorCode } from "./ecf-secret-resolver.types";

export class EcfSecretResolverError extends Error {
  constructor(
    readonly code: EcfSecretResolverErrorCode,
    readonly safeMessage: string,
    readonly provider: EcfSecretProviderKind = "unsupported",
  ) {
    super(safeMessage);
    this.name = "EcfSecretResolverError";
  }
}
