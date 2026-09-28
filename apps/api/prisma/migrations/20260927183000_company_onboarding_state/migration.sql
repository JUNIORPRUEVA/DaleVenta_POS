ALTER TABLE "companies"
  ADD COLUMN "onboarding_required" BOOLEAN NOT NULL DEFAULT false,
  ADD COLUMN "onboarding_status" VARCHAR(32) NOT NULL DEFAULT 'NOT_REQUIRED',
  ADD COLUMN "onboarding_company_step" VARCHAR(24) NOT NULL DEFAULT 'SKIPPED',
  ADD COLUMN "onboarding_billing_step" VARCHAR(24) NOT NULL DEFAULT 'SKIPPED',
  ADD COLUMN "onboarding_product_step" VARCHAR(24) NOT NULL DEFAULT 'SKIPPED',
  ADD COLUMN "onboarding_ready_step" VARCHAR(24) NOT NULL DEFAULT 'SKIPPED',
  ADD COLUMN "onboarding_started_at" TIMESTAMP(3),
  ADD COLUMN "onboarding_completed_at" TIMESTAMP(3),
  ADD COLUMN "onboarding_skipped_at" TIMESTAMP(3),
  ADD COLUMN "tutorial_status" VARCHAR(32) NOT NULL DEFAULT 'NOT_REQUIRED',
  ADD COLUMN "tutorial_completed_at" TIMESTAMP(3),
  ADD COLUMN "tutorial_skipped_at" TIMESTAMP(3);
