export type EcfSecretProviderKind =
  | "env"
  | "windows-credential-manager"
  | "docker-secret"
  | "unsupported";

export type EcfSecretResolverErrorCode =
  | "EMPTY_REFERENCE"
  | "INVALID_REFERENCE"
  | "UNSUPPORTED_PROVIDER"
  | "REFERENCE_NOT_ALLOWED"
  | "PRODUCTION_BLOCKED"
  | "SECRET_NOT_FOUND"
  | "ACCESS_DENIED"
  | "RESOLUTION_UNSUPPORTED"
  | "INCONSISTENT_CONFIGURATION";

export type EcfSecretResolutionContext = {
  companyId?: string;
  environment: "sandbox" | "uat" | "production";
  allowedReferences?: readonly string[];
  allowProductionResolution?: boolean;
};

export type EcfSecretInspection = {
  referenceConfigured: boolean;
  provider: EcfSecretProviderKind;
  credentialFound: boolean;
  credentialAccessibleByProcess: boolean;
  resolutionSupported: boolean;
};

export type EcfResolvedSecret = {
  provider: EcfSecretProviderKind;
  value: string;
};

export interface EcfSecretProvider {
  readonly kind: EcfSecretProviderKind;
  supports(reference: string): boolean;
  inspect(reference: string): Promise<EcfSecretInspection>;
  resolve(reference: string): Promise<EcfResolvedSecret>;
}
