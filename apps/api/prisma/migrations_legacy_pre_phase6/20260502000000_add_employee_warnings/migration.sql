-- CreateEnum (skip if already exists)
DO $$ BEGIN
  CREATE TYPE "employee_warning_severity" AS ENUM ('low', 'medium', 'high', 'critical');
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  CREATE TYPE "employee_warning_status" AS ENUM ('draft', 'pending_signature', 'signed', 'refused_to_sign', 'annulled', 'archived');
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  CREATE TYPE "employee_warning_category" AS ENUM ('tardiness', 'absence', 'misconduct', 'negligence', 'policy_violation', 'insubordination', 'other');
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  CREATE TYPE "employee_warning_signature_type" AS ENUM ('signed', 'refused');
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

-- CreateTable
CREATE TABLE IF NOT EXISTS "employee_warnings" (
    "id" UUID NOT NULL,
    "company_id" UUID NOT NULL,
    "employee_user_id" UUID NOT NULL,
    "created_by_user_id" UUID NOT NULL,
    "warning_number" TEXT NOT NULL,
    "warning_date" TIMESTAMP(3) NOT NULL,
    "incident_date" TIMESTAMP(3) NOT NULL,
    "title" TEXT NOT NULL,
    "category" "employee_warning_category" NOT NULL,
    "severity" "employee_warning_severity" NOT NULL,
    "legal_basis" TEXT,
    "internal_rule_reference" TEXT,
    "description" TEXT NOT NULL,
    "employee_explanation" TEXT,
    "corrective_action" TEXT,
    "consequence_note" TEXT,
    "evidence_notes" TEXT,
    "status" "employee_warning_status" NOT NULL DEFAULT 'draft',
    "pdf_url" TEXT,
    "signed_pdf_url" TEXT,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMP(3) NOT NULL,
    "submitted_at" TIMESTAMP(3),
    "signed_at" TIMESTAMP(3),
    "refused_at" TIMESTAMP(3),
    "annulled_at" TIMESTAMP(3),
    "annulled_by_user_id" UUID,
    "annulment_reason" TEXT,

    CONSTRAINT "employee_warnings_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE IF NOT EXISTS "employee_warning_evidences" (
    "id" UUID NOT NULL,
    "warning_id" UUID NOT NULL,
    "file_url" TEXT NOT NULL,
    "file_name" TEXT NOT NULL,
    "file_type" TEXT NOT NULL,
    "storage_key" TEXT,
    "uploaded_by_user_id" UUID NOT NULL,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "employee_warning_evidences_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE IF NOT EXISTS "employee_warning_signatures" (
    "id" UUID NOT NULL,
    "warning_id" UUID NOT NULL,
    "employee_user_id" UUID NOT NULL,
    "signature_type" "employee_warning_signature_type" NOT NULL,
    "signature_image_url" TEXT,
    "typed_name" TEXT NOT NULL,
    "comment" TEXT,
    "ip_address" TEXT,
    "device_info" TEXT,
    "signed_at" TIMESTAMP(3) NOT NULL,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "employee_warning_signatures_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE IF NOT EXISTS "employee_warning_audit_logs" (
    "id" UUID NOT NULL,
    "warning_id" UUID NOT NULL,
    "action" TEXT NOT NULL,
    "actor_user_id" UUID,
    "old_status" "employee_warning_status",
    "new_status" "employee_warning_status",
    "metadata_json" JSONB,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "employee_warning_audit_logs_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX IF NOT EXISTS "employee_warnings_company_id_employee_user_id_idx" ON "employee_warnings"("company_id", "employee_user_id");
CREATE INDEX IF NOT EXISTS "employee_warnings_company_id_status_idx" ON "employee_warnings"("company_id", "status");
CREATE INDEX IF NOT EXISTS "employee_warnings_company_id_created_at_idx" ON "employee_warnings"("company_id", "created_at");
CREATE UNIQUE INDEX IF NOT EXISTS "employee_warnings_company_id_warning_number_key" ON "employee_warnings"("company_id", "warning_number");

CREATE INDEX IF NOT EXISTS "employee_warning_evidences_warning_id_created_at_idx" ON "employee_warning_evidences"("warning_id", "created_at");
CREATE INDEX IF NOT EXISTS "employee_warning_signatures_warning_id_signed_at_idx" ON "employee_warning_signatures"("warning_id", "signed_at");
CREATE INDEX IF NOT EXISTS "employee_warning_audit_logs_warning_id_created_at_idx" ON "employee_warning_audit_logs"("warning_id", "created_at");

-- AddForeignKey
DO $$ BEGIN
  ALTER TABLE "employee_warnings" ADD CONSTRAINT "employee_warnings_employee_user_id_fkey" FOREIGN KEY ("employee_user_id") REFERENCES "users"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;
DO $$ BEGIN
  ALTER TABLE "employee_warnings" ADD CONSTRAINT "employee_warnings_created_by_user_id_fkey" FOREIGN KEY ("created_by_user_id") REFERENCES "users"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;
DO $$ BEGIN
  ALTER TABLE "employee_warnings" ADD CONSTRAINT "employee_warnings_annulled_by_user_id_fkey" FOREIGN KEY ("annulled_by_user_id") REFERENCES "users"("id") ON DELETE SET NULL ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;
DO $$ BEGIN
  ALTER TABLE "employee_warning_evidences" ADD CONSTRAINT "employee_warning_evidences_warning_id_fkey" FOREIGN KEY ("warning_id") REFERENCES "employee_warnings"("id") ON DELETE CASCADE ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;
DO $$ BEGIN
  ALTER TABLE "employee_warning_evidences" ADD CONSTRAINT "employee_warning_evidences_uploaded_by_user_id_fkey" FOREIGN KEY ("uploaded_by_user_id") REFERENCES "users"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;
DO $$ BEGIN
  ALTER TABLE "employee_warning_signatures" ADD CONSTRAINT "employee_warning_signatures_warning_id_fkey" FOREIGN KEY ("warning_id") REFERENCES "employee_warnings"("id") ON DELETE CASCADE ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;
DO $$ BEGIN
  ALTER TABLE "employee_warning_signatures" ADD CONSTRAINT "employee_warning_signatures_employee_user_id_fkey" FOREIGN KEY ("employee_user_id") REFERENCES "users"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;
DO $$ BEGIN
  ALTER TABLE "employee_warning_audit_logs" ADD CONSTRAINT "employee_warning_audit_logs_warning_id_fkey" FOREIGN KEY ("warning_id") REFERENCES "employee_warnings"("id") ON DELETE CASCADE ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;
DO $$ BEGIN
  ALTER TABLE "employee_warning_audit_logs" ADD CONSTRAINT "employee_warning_audit_logs_actor_user_id_fkey" FOREIGN KEY ("actor_user_id") REFERENCES "users"("id") ON DELETE SET NULL ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;
