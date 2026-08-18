DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'company_member_role') THEN
    CREATE TYPE "company_member_role" AS ENUM (
      'OWNER',
      'ADMIN',
      'MANAGER',
      'CASHIER',
      'SELLER',
      'WAREHOUSE',
      'ACCOUNTANT',
      'VIEWER'
    );
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'company_member_status') THEN
    CREATE TYPE "company_member_status" AS ENUM (
      'ACTIVE',
      'INVITED',
      'DISABLED',
      'REMOVED'
    );
  END IF;
END $$;

CREATE TABLE IF NOT EXISTS "company_members" (
  "id" UUID NOT NULL DEFAULT gen_random_uuid(),
  "user_id" UUID NOT NULL,
  "company_id" UUID NOT NULL,
  "role" "company_member_role" NOT NULL DEFAULT 'VIEWER',
  "status" "company_member_status" NOT NULL DEFAULT 'ACTIVE',
  "invited_by" UUID,
  "joined_at" TIMESTAMP(3) DEFAULT CURRENT_TIMESTAMP,
  "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updated_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

  CONSTRAINT "company_members_pkey" PRIMARY KEY ("id")
);

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'company_members_user_id_company_id_key') THEN
    ALTER TABLE "company_members"
      ADD CONSTRAINT "company_members_user_id_company_id_key" UNIQUE ("user_id", "company_id");
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'company_members_user_id_fkey') THEN
    ALTER TABLE "company_members"
      ADD CONSTRAINT "company_members_user_id_fkey"
      FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'company_members_company_id_fkey') THEN
    ALTER TABLE "company_members"
      ADD CONSTRAINT "company_members_company_id_fkey"
      FOREIGN KEY ("company_id") REFERENCES "companies"("id") ON DELETE CASCADE ON UPDATE CASCADE;
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'company_members_invited_by_fkey') THEN
    ALTER TABLE "company_members"
      ADD CONSTRAINT "company_members_invited_by_fkey"
      FOREIGN KEY ("invited_by") REFERENCES "users"("id") ON DELETE SET NULL ON UPDATE CASCADE;
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS "company_members_company_id_status_idx"
  ON "company_members"("company_id", "status");

CREATE INDEX IF NOT EXISTS "company_members_user_id_status_idx"
  ON "company_members"("user_id", "status");

CREATE INDEX IF NOT EXISTS "company_members_company_id_role_idx"
  ON "company_members"("company_id", "role");

INSERT INTO "company_members" ("user_id", "company_id", "role", "status", "joined_at")
SELECT
  u."id",
  u."company_id",
  CASE
    WHEN u."role"::text = 'ADMIN' THEN 'OWNER'::"company_member_role"
    WHEN u."role"::text = 'ASISTENTE' THEN 'ADMIN'::"company_member_role"
    WHEN u."role"::text = 'CAJERO' THEN 'CASHIER'::"company_member_role"
    WHEN u."role"::text = 'VENDEDOR' THEN 'SELLER'::"company_member_role"
    ELSE 'VIEWER'::"company_member_role"
  END,
  'ACTIVE'::"company_member_status",
  CURRENT_TIMESTAMP
FROM "users" u
WHERE u."company_id" IS NOT NULL
ON CONFLICT ("user_id", "company_id") DO UPDATE
SET
  "role" = EXCLUDED."role",
  "status" = 'ACTIVE'::"company_member_status",
  "updated_at" = CURRENT_TIMESTAMP;

ALTER TABLE "work_employee_configs"
  ADD COLUMN IF NOT EXISTS "company_id" UUID;

ALTER TABLE "work_schedule_exceptions"
  ADD COLUMN IF NOT EXISTS "company_id" UUID;

UPDATE "work_employee_configs" cfg
SET "company_id" = COALESCE(
  u."company_id",
  (
    SELECT cm."company_id"
    FROM "company_members" cm
    WHERE cm."user_id" = cfg."user_id"
      AND cm."status" = 'ACTIVE'
    ORDER BY cm."created_at" ASC
    LIMIT 1
  )
)
FROM "users" u
WHERE u."id" = cfg."user_id"
  AND cfg."company_id" IS NULL;

UPDATE "work_schedule_exceptions" e
SET "company_id" = cfg."company_id"
FROM "work_employee_configs" cfg
WHERE cfg."user_id" = e."user_id"
  AND e."company_id" IS NULL;

UPDATE "work_schedule_exceptions" e
SET "company_id" = COALESCE(
  u."company_id",
  (
    SELECT cm."company_id"
    FROM "company_members" cm
    WHERE cm."user_id" = e."created_by_id"
      AND cm."status" = 'ACTIVE'
    ORDER BY cm."created_at" ASC
    LIMIT 1
  )
)
FROM "users" u
WHERE u."id" = e."created_by_id"
  AND e."company_id" IS NULL;

DO $$
DECLARE
  missing_configs INTEGER;
  missing_exceptions INTEGER;
BEGIN
  SELECT COUNT(*) INTO missing_configs FROM "work_employee_configs" WHERE "company_id" IS NULL;
  SELECT COUNT(*) INTO missing_exceptions FROM "work_schedule_exceptions" WHERE "company_id" IS NULL;

  IF missing_configs > 0 THEN
    RAISE EXCEPTION 'Tenant hardening blocked: % work_employee_configs rows have no company_id', missing_configs;
  END IF;

  IF missing_exceptions > 0 THEN
    RAISE EXCEPTION 'Tenant hardening blocked: % work_schedule_exceptions rows have no company_id', missing_exceptions;
  END IF;
END $$;

ALTER TABLE "work_employee_configs"
  ALTER COLUMN "company_id" SET NOT NULL;

ALTER TABLE "work_schedule_exceptions"
  ALTER COLUMN "company_id" SET NOT NULL;

CREATE INDEX IF NOT EXISTS "work_employee_configs_company_id_enabled_idx"
  ON "work_employee_configs"("company_id", "enabled");

CREATE INDEX IF NOT EXISTS "work_schedule_exceptions_company_id_date_from_date_to_idx"
  ON "work_schedule_exceptions"("company_id", "date_from", "date_to");

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'work_employee_configs_company_id_fkey'
  ) THEN
    ALTER TABLE "work_employee_configs"
      ADD CONSTRAINT "work_employee_configs_company_id_fkey"
      FOREIGN KEY ("company_id") REFERENCES "companies"("id")
      ON DELETE CASCADE ON UPDATE CASCADE;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'work_schedule_exceptions_company_id_fkey'
  ) THEN
    ALTER TABLE "work_schedule_exceptions"
      ADD CONSTRAINT "work_schedule_exceptions_company_id_fkey"
      FOREIGN KEY ("company_id") REFERENCES "companies"("id")
      ON DELETE CASCADE ON UPDATE CASCADE;
  END IF;
END $$;
