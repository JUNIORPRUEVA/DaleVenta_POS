CREATE TYPE "license_status" AS ENUM ('TRIAL', 'ACTIVE', 'BLOCKED', 'EXPIRED');

ALTER TABLE "companies"
  ADD COLUMN "license_status" "license_status" NOT NULL DEFAULT 'TRIAL',
  ADD COLUMN "license_key" TEXT,
  ADD COLUMN "trial_started_at" TIMESTAMP(3) DEFAULT CURRENT_TIMESTAMP,
  ADD COLUMN "trial_ends_at" TIMESTAMP(3),
  ADD COLUMN "license_activated_at" TIMESTAMP(3),
  ADD COLUMN "license_expires_at" TIMESTAMP(3),
  ADD COLUMN "license_blocked_at" TIMESTAMP(3),
  ADD COLUMN "license_notes" TEXT,
  ADD COLUMN "max_products" INTEGER NOT NULL DEFAULT 500;

UPDATE "companies"
SET
  "license_status" = 'TRIAL',
  "trial_started_at" = COALESCE("trial_started_at", "created_at", CURRENT_TIMESTAMP),
  "trial_ends_at" = COALESCE("trial_ends_at", "created_at" + INTERVAL '7 days', CURRENT_TIMESTAMP + INTERVAL '7 days'),
  "max_users" = CASE WHEN "max_users" IS NULL OR "max_users" >= 1000 THEN 2 ELSE "max_users" END,
  "max_products" = 500
WHERE "license_status" = 'TRIAL';

CREATE UNIQUE INDEX "companies_license_key_key" ON "companies"("license_key");
CREATE INDEX "companies_license_status_idx" ON "companies"("license_status");
CREATE INDEX "companies_license_expires_at_idx" ON "companies"("license_expires_at");

CREATE TABLE "company_license_audit_logs" (
  "id" UUID NOT NULL,
  "company_id" UUID NOT NULL,
  "actor_id" UUID,
  "actor_email" TEXT,
  "action" TEXT NOT NULL,
  "reason" TEXT,
  "before" JSONB,
  "after" JSONB,
  "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

  CONSTRAINT "company_license_audit_logs_pkey" PRIMARY KEY ("id"),
  CONSTRAINT "company_license_audit_logs_company_id_fkey"
    FOREIGN KEY ("company_id") REFERENCES "companies"("id") ON DELETE CASCADE ON UPDATE CASCADE
);

CREATE INDEX "company_license_audit_logs_company_id_created_at_idx"
  ON "company_license_audit_logs"("company_id", "created_at");
CREATE INDEX "company_license_audit_logs_action_idx"
  ON "company_license_audit_logs"("action");
