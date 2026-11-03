CREATE TYPE "ecf_provider" AS ENUM ('ALANUBE');

CREATE TYPE "ecf_environment" AS ENUM ('SANDBOX', 'PRODUCTION');

CREATE TYPE "ecf_certification_status" AS ENUM (
  'NOT_STARTED',
  'IN_PROGRESS',
  'BLOCKED',
  'READY_FOR_REVIEW',
  'AUTHORIZED_SANDBOX',
  'PRODUCTION_READY',
  'SUSPENDED'
);

CREATE TYPE "ecf_onboarding_step_key" AS ENUM (
  'REQUIREMENTS',
  'FISCAL_CONFIG',
  'DIGITAL_CERTIFICATE',
  'ALANUBE_REGISTRATION',
  'DGII_POSTULATION',
  'XML_SIGNATURE',
  'SET_TESTS',
  'SIMULATIONS',
  'PRINTED_REPRESENTATION',
  'SERVICE_URLS',
  'SWORN_DECLARATION',
  'FINAL_AUTHORIZATION',
  'ENCF_REQUEST',
  'PRODUCTION_ENABLEMENT'
);

CREATE TYPE "ecf_onboarding_step_status" AS ENUM (
  'PENDING',
  'IN_PROGRESS',
  'BLOCKED',
  'COMPLETED',
  'CONFIRMED',
  'FAILED'
);

CREATE TYPE "ecf_onboarding_step_mode" AS ENUM (
  'AUTOMATIC',
  'ASSISTED',
  'MANUAL',
  'PENDING_CONFIRMATION'
);

CREATE TYPE "ecf_certification_attempt_status" AS ENUM (
  'REGISTERED',
  'IN_PROGRESS',
  'SUCCEEDED',
  'FAILED',
  'BLOCKED'
);

CREATE TYPE "ecf_audit_action" AS ENUM (
  'CONFIG_CREATED',
  'CONFIG_UPDATED',
  'ONBOARDING_STARTED',
  'STEP_CREATED',
  'STEP_UPDATED',
  'EVIDENCE_LINKED',
  'ATTEMPT_REGISTERED'
);

CREATE TABLE "ecf_company_configurations" (
  "id" UUID NOT NULL DEFAULT gen_random_uuid(),
  "company_id" UUID NOT NULL,
  "enabled" BOOLEAN NOT NULL DEFAULT false,
  "provider" "ecf_provider" NOT NULL DEFAULT 'ALANUBE',
  "environment" "ecf_environment" NOT NULL DEFAULT 'SANDBOX',
  "certification_status" "ecf_certification_status" NOT NULL DEFAULT 'NOT_STARTED',
  "production_enabled" BOOLEAN NOT NULL DEFAULT false,
  "alanube_company_id" VARCHAR(64),
  "credentials_secret_ref" VARCHAR(256),
  "certificate_secret_ref" VARCHAR(256),
  "webhook_secret_ref" VARCHAR(256),
  "allowed_types" JSONB,
  "notes" TEXT,
  "created_by_user_id" UUID,
  "updated_by_user_id" UUID,
  "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updated_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "ecf_company_configurations_pkey" PRIMARY KEY ("id")
);

CREATE TABLE "ecf_evidences" (
  "id" UUID NOT NULL DEFAULT gen_random_uuid(),
  "company_id" UUID NOT NULL,
  "kind" VARCHAR(64) NOT NULL,
  "storage_ref" VARCHAR(512) NOT NULL,
  "file_name" VARCHAR(255),
  "mime_type" VARCHAR(120),
  "sha256" VARCHAR(64),
  "description" TEXT,
  "uploaded_by_user_id" UUID,
  "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "ecf_evidences_pkey" PRIMARY KEY ("id")
);

CREATE TABLE "ecf_onboarding_steps" (
  "id" UUID NOT NULL DEFAULT gen_random_uuid(),
  "company_id" UUID NOT NULL,
  "step_key" "ecf_onboarding_step_key" NOT NULL,
  "status" "ecf_onboarding_step_status" NOT NULL DEFAULT 'PENDING',
  "mode" "ecf_onboarding_step_mode" NOT NULL DEFAULT 'MANUAL',
  "evidence_id" UUID,
  "result_summary" TEXT,
  "last_error_code" VARCHAR(64),
  "last_error" TEXT,
  "blocked_reason" TEXT,
  "started_at" TIMESTAMP(3),
  "completed_at" TIMESTAMP(3),
  "confirmed_at" TIMESTAMP(3),
  "updated_by_user_id" UUID,
  "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updated_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "ecf_onboarding_steps_pkey" PRIMARY KEY ("id")
);

CREATE TABLE "ecf_certification_attempts" (
  "id" UUID NOT NULL DEFAULT gen_random_uuid(),
  "company_id" UUID NOT NULL,
  "step_key" "ecf_onboarding_step_key",
  "provider" "ecf_provider" NOT NULL DEFAULT 'ALANUBE',
  "environment" "ecf_environment" NOT NULL DEFAULT 'SANDBOX',
  "operation" VARCHAR(64) NOT NULL,
  "status" "ecf_certification_attempt_status" NOT NULL DEFAULT 'REGISTERED',
  "idempotency_key" VARCHAR(128) NOT NULL,
  "request_ref" VARCHAR(256),
  "response_ref" VARCHAR(256),
  "external_id" VARCHAR(128),
  "error_code" VARCHAR(64),
  "error_message" TEXT,
  "created_by_user_id" UUID,
  "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updated_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "ecf_certification_attempts_pkey" PRIMARY KEY ("id")
);

CREATE TABLE "ecf_audit_logs" (
  "id" UUID NOT NULL DEFAULT gen_random_uuid(),
  "company_id" UUID NOT NULL,
  "actor_user_id" UUID,
  "action" "ecf_audit_action" NOT NULL,
  "target_type" VARCHAR(64),
  "target_id" UUID,
  "before" JSONB,
  "after" JSONB,
  "metadata" JSONB,
  "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "ecf_audit_logs_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX "ecf_company_configurations_company_id_key" ON "ecf_company_configurations"("company_id");
CREATE INDEX "ecf_company_configurations_company_id_enabled_idx" ON "ecf_company_configurations"("company_id", "enabled");
CREATE INDEX "ecf_company_configurations_company_id_certification_status_idx" ON "ecf_company_configurations"("company_id", "certification_status");
CREATE INDEX "ecf_evidences_company_id_kind_created_at_idx" ON "ecf_evidences"("company_id", "kind", "created_at");
CREATE INDEX "ecf_evidences_company_id_storage_ref_idx" ON "ecf_evidences"("company_id", "storage_ref");
CREATE UNIQUE INDEX "ecf_onboarding_steps_company_id_step_key_key" ON "ecf_onboarding_steps"("company_id", "step_key");
CREATE INDEX "ecf_onboarding_steps_company_id_status_idx" ON "ecf_onboarding_steps"("company_id", "status");
CREATE INDEX "ecf_onboarding_steps_company_id_updated_at_idx" ON "ecf_onboarding_steps"("company_id", "updated_at");
CREATE UNIQUE INDEX "ecf_certification_attempts_company_id_idempotency_key_key" ON "ecf_certification_attempts"("company_id", "idempotency_key");
CREATE INDEX "ecf_certification_attempts_company_id_step_key_status_idx" ON "ecf_certification_attempts"("company_id", "step_key", "status");
CREATE INDEX "ecf_certification_attempts_company_id_operation_created_at_idx" ON "ecf_certification_attempts"("company_id", "operation", "created_at");
CREATE INDEX "ecf_audit_logs_company_id_created_at_idx" ON "ecf_audit_logs"("company_id", "created_at");
CREATE INDEX "ecf_audit_logs_company_id_action_idx" ON "ecf_audit_logs"("company_id", "action");
CREATE INDEX "ecf_audit_logs_target_type_target_id_idx" ON "ecf_audit_logs"("target_type", "target_id");

ALTER TABLE "ecf_company_configurations" ADD CONSTRAINT "ecf_company_configurations_company_id_fkey" FOREIGN KEY ("company_id") REFERENCES "companies"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "ecf_evidences" ADD CONSTRAINT "ecf_evidences_company_id_fkey" FOREIGN KEY ("company_id") REFERENCES "companies"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "ecf_onboarding_steps" ADD CONSTRAINT "ecf_onboarding_steps_company_id_fkey" FOREIGN KEY ("company_id") REFERENCES "companies"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "ecf_onboarding_steps" ADD CONSTRAINT "ecf_onboarding_steps_evidence_id_fkey" FOREIGN KEY ("evidence_id") REFERENCES "ecf_evidences"("id") ON DELETE SET NULL ON UPDATE CASCADE;
ALTER TABLE "ecf_certification_attempts" ADD CONSTRAINT "ecf_certification_attempts_company_id_fkey" FOREIGN KEY ("company_id") REFERENCES "companies"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "ecf_audit_logs" ADD CONSTRAINT "ecf_audit_logs_company_id_fkey" FOREIGN KEY ("company_id") REFERENCES "companies"("id") ON DELETE CASCADE ON UPDATE CASCADE;
