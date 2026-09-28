export const ONBOARDING_STATUS = {
  NOT_REQUIRED: "NOT_REQUIRED",
  WELCOME_PENDING: "WELCOME_PENDING",
  IN_PROGRESS: "IN_PROGRESS",
  COMPLETED: "COMPLETED",
  SKIPPED: "SKIPPED",
} as const;

export const ONBOARDING_STEP_STATUS = {
  PENDING: "PENDING",
  COMPLETED: "COMPLETED",
  SKIPPED: "SKIPPED",
} as const;

export const TUTORIAL_STATUS = {
  NOT_REQUIRED: "NOT_REQUIRED",
  PENDING: "PENDING",
  STARTED: "STARTED",
  COMPLETED: "COMPLETED",
  SKIPPED: "SKIPPED",
} as const;

export type OnboardingStepKey = "company" | "billing" | "product" | "ready";

export function shouldRequireOnboarding(company: {
  onboardingRequired?: boolean | null;
  onboardingStatus?: string | null;
}) {
  if (company.onboardingRequired !== true) return false;
  return (
    company.onboardingStatus === ONBOARDING_STATUS.WELCOME_PENDING ||
    company.onboardingStatus === ONBOARDING_STATUS.IN_PROGRESS
  );
}
