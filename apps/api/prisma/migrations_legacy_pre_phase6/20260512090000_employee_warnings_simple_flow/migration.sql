-- Add simplified no-signature warning flow fields while keeping legacy signature data.

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_type t
    JOIN pg_enum e ON t.oid = e.enumtypid
    WHERE t.typname = 'employee_warning_status'
      AND e.enumlabel = 'issued'
  ) THEN
    ALTER TYPE "employee_warning_status" ADD VALUE 'issued';
  END IF;
END
$$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'employee_warning_type') THEN
    CREATE TYPE "employee_warning_type" AS ENUM ('verbal_documented', 'written', 'reincidence', 'other');
  END IF;
END
$$;

ALTER TABLE "employee_warnings"
  ADD COLUMN IF NOT EXISTS "warning_type" "employee_warning_type" NOT NULL DEFAULT 'written',
  ADD COLUMN IF NOT EXISTS "reason" TEXT,
  ADD COLUMN IF NOT EXISTS "details" TEXT,
  ADD COLUMN IF NOT EXISTS "incident_time" TEXT,
  ADD COLUMN IF NOT EXISTS "incident_place" TEXT,
  ADD COLUMN IF NOT EXISTS "issued_by_user_id" UUID,
  ADD COLUMN IF NOT EXISTS "issued_by_name_snapshot" TEXT,
  ADD COLUMN IF NOT EXISTS "issued_by_position_snapshot" TEXT,
  ADD COLUMN IF NOT EXISTS "internal_notes" TEXT,
  ADD COLUMN IF NOT EXISTS "generated_text" TEXT,
  ADD COLUMN IF NOT EXISTS "employee_name_snapshot" TEXT,
  ADD COLUMN IF NOT EXISTS "employee_cedula_snapshot" TEXT,
  ADD COLUMN IF NOT EXISTS "employee_position_snapshot" TEXT,
  ADD COLUMN IF NOT EXISTS "employee_department_snapshot" TEXT,
  ADD COLUMN IF NOT EXISTS "employee_phone_snapshot" TEXT,
  ADD COLUMN IF NOT EXISTS "company_name_snapshot" TEXT,
  ADD COLUMN IF NOT EXISTS "company_rnc_snapshot" TEXT,
  ADD COLUMN IF NOT EXISTS "company_address_snapshot" TEXT,
  ADD COLUMN IF NOT EXISTS "deleted_at" TIMESTAMP(3);

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'employee_warnings_issued_by_user_id_fkey'
  ) THEN
    ALTER TABLE "employee_warnings"
      ADD CONSTRAINT "employee_warnings_issued_by_user_id_fkey"
      FOREIGN KEY ("issued_by_user_id") REFERENCES "users"("id") ON DELETE SET NULL ON UPDATE CASCADE;
  END IF;
END
$$;

CREATE INDEX IF NOT EXISTS "employee_warnings_company_id_warning_type_idx"
  ON "employee_warnings"("company_id", "warning_type");

CREATE INDEX IF NOT EXISTS "employee_warnings_issued_by_user_id_idx"
  ON "employee_warnings"("issued_by_user_id");
