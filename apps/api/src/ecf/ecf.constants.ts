import {
  EcfOnboardingStepKey,
  EcfOnboardingStepMode,
} from "@prisma/client";

export const ECF_ALLOWED_DOCUMENT_TYPES = ["E31", "E32", "E34"] as const;

export const ECF_DEFAULT_STEP_MODES: Record<
  EcfOnboardingStepKey,
  EcfOnboardingStepMode
> = {
  REQUIREMENTS: EcfOnboardingStepMode.MANUAL,
  FISCAL_CONFIG: EcfOnboardingStepMode.MANUAL,
  DIGITAL_CERTIFICATE: EcfOnboardingStepMode.ASSISTED,
  ALANUBE_REGISTRATION: EcfOnboardingStepMode.ASSISTED,
  DGII_POSTULATION: EcfOnboardingStepMode.MANUAL,
  XML_SIGNATURE: EcfOnboardingStepMode.ASSISTED,
  SET_TESTS: EcfOnboardingStepMode.ASSISTED,
  SIMULATIONS: EcfOnboardingStepMode.ASSISTED,
  PRINTED_REPRESENTATION: EcfOnboardingStepMode.MANUAL,
  SERVICE_URLS: EcfOnboardingStepMode.ASSISTED,
  SWORN_DECLARATION: EcfOnboardingStepMode.MANUAL,
  FINAL_AUTHORIZATION: EcfOnboardingStepMode.MANUAL,
  ENCF_REQUEST: EcfOnboardingStepMode.MANUAL,
  // Etapa V del instructivo de Alanube: aceptar el rol Administrador en la OFV
  // y delegar los demás roles. Sin esto la DGII rechaza los comprobantes por
  // proceso incompleto, así que es obligatorio y nunca automático.
  ROLE_ASSIGNMENT: EcfOnboardingStepMode.ASSISTED,
  PRODUCTION_ENABLEMENT: EcfOnboardingStepMode.PENDING_CONFIRMATION,
};

export const ECF_ONBOARDING_STEP_ORDER = Object.keys(
  ECF_DEFAULT_STEP_MODES,
) as EcfOnboardingStepKey[];

