-- Enable monitoring by default without overriding an administrator's decision.
-- Global Guardian switches, enrollment eligibility and quotas remain enforced.
ALTER TABLE "companies" ALTER COLUMN "guardian_enabled" SET DEFAULT true;

UPDATE "companies"
SET "guardian_enabled" = true,
    "guardian_enabled_at" = CURRENT_TIMESTAMP,
    "guardian_enabled_by" = 'DEFAULT_ENABLED_20261127'
WHERE "guardian_enabled" = false
  AND "guardian_enabled_by" IS NULL
  AND "status" <> 'ARCHIVED';
