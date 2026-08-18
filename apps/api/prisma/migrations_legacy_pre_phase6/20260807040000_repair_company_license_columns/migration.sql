DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'license_status') THEN
    CREATE TYPE "license_status" AS ENUM ('TRIAL', 'ACTIVE', 'BLOCKED', 'EXPIRED');
  END IF;
END $$;

ALTER TABLE "companies"
  ADD COLUMN IF NOT EXISTS "license_status" "license_status" NOT NULL DEFAULT 'TRIAL',
  ADD COLUMN IF NOT EXISTS "license_key" TEXT,
  ADD COLUMN IF NOT EXISTS "trial_started_at" TIMESTAMP(3) DEFAULT CURRENT_TIMESTAMP,
  ADD COLUMN IF NOT EXISTS "trial_ends_at" TIMESTAMP(3),
  ADD COLUMN IF NOT EXISTS "license_activated_at" TIMESTAMP(3),
  ADD COLUMN IF NOT EXISTS "license_expires_at" TIMESTAMP(3),
  ADD COLUMN IF NOT EXISTS "license_blocked_at" TIMESTAMP(3),
  ADD COLUMN IF NOT EXISTS "license_notes" TEXT,
  ADD COLUMN IF NOT EXISTS "max_products" INTEGER NOT NULL DEFAULT 100;

ALTER TABLE "companies"
  ALTER COLUMN "max_users" SET DEFAULT 2,
  ALTER COLUMN "max_products" SET DEFAULT 100;

UPDATE "companies"
SET
  "trial_started_at" = COALESCE("trial_started_at", "created_at", CURRENT_TIMESTAMP),
  "trial_ends_at" = COALESCE("trial_ends_at", "created_at" + INTERVAL '7 days', CURRENT_TIMESTAMP + INTERVAL '7 days'),
  "max_users" = CASE WHEN "max_users" IS NULL OR "max_users" >= 1000 THEN 2 ELSE "max_users" END,
  "max_products" = CASE WHEN "max_products" IS NULL OR "max_products" >= 1000 THEN 100 ELSE "max_products" END
WHERE "license_status" = 'TRIAL';

CREATE UNIQUE INDEX IF NOT EXISTS "companies_license_key_key" ON "companies"("license_key");
CREATE INDEX IF NOT EXISTS "companies_license_status_idx" ON "companies"("license_status");
CREATE INDEX IF NOT EXISTS "companies_license_expires_at_idx" ON "companies"("license_expires_at");

CREATE TABLE IF NOT EXISTS "company_license_audit_logs" (
  "id" UUID NOT NULL DEFAULT gen_random_uuid(),
  "company_id" UUID NOT NULL,
  "actor_id" UUID,
  "actor_email" TEXT,
  "action" TEXT NOT NULL,
  "reason" TEXT,
  "before" JSONB,
  "after" JSONB,
  "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

  CONSTRAINT "company_license_audit_logs_pkey" PRIMARY KEY ("id")
);

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'company_license_audit_logs_company_id_fkey') THEN
    ALTER TABLE "company_license_audit_logs"
      ADD CONSTRAINT "company_license_audit_logs_company_id_fkey"
      FOREIGN KEY ("company_id") REFERENCES "companies"("id") ON DELETE CASCADE ON UPDATE CASCADE;
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS "company_license_audit_logs_company_id_created_at_idx"
  ON "company_license_audit_logs"("company_id", "created_at");
CREATE INDEX IF NOT EXISTS "company_license_audit_logs_action_idx"
  ON "company_license_audit_logs"("action");
