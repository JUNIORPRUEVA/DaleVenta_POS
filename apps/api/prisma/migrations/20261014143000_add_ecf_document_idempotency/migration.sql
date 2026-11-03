CREATE TYPE "ecf_electronic_document_type" AS ENUM ('E31', 'E32', 'E34');

CREATE TYPE "ecf_electronic_document_status" AS ENUM (
  'LOCAL_DRAFT',
  'LOCAL_VALIDATION_PENDING',
  'LOCAL_VALIDATED',
  'READY_TO_SEND',
  'SEND_PENDING',
  'SEND_IN_PROGRESS',
  'UNKNOWN_RESULT',
  'PROVIDER_ACCEPTED',
  'PROVIDER_REJECTED',
  'DGII_STATUS_PENDING',
  'DGII_ACCEPTED',
  'DGII_REJECTED',
  'HUMAN_REVIEW_REQUIRED',
  'CANCELLED'
);

CREATE TYPE "ecf_electronic_document_operation" AS ENUM (
  'PREPARE',
  'VALIDATE_LOCAL',
  'SEND_TO_PROVIDER',
  'QUERY_PROVIDER',
  'QUERY_DGII_STATUS',
  'CANCEL_LOCAL',
  'MARK_HUMAN_REVIEW'
);

CREATE TABLE "ecf_electronic_documents" (
  "id" UUID NOT NULL DEFAULT gen_random_uuid(),
  "company_id" UUID NOT NULL,
  "document_type" "ecf_electronic_document_type" NOT NULL,
  "status" "ecf_electronic_document_status" NOT NULL DEFAULT 'LOCAL_DRAFT',
  "internal_document_number" VARCHAR(64),
  "source_type" VARCHAR(32),
  "source_id" UUID,
  "external_provider_id" VARCHAR(128),
  "external_document_number" VARCHAR(128),
  "original_document_id" UUID,
  "payload_fingerprint" VARCHAR(64) NOT NULL,
  "idempotency_key" VARCHAR(160) NOT NULL,
  "payload_summary" JSONB,
  "safe_error_code" VARCHAR(64),
  "safe_error_message" TEXT,
  "created_by_user_id" UUID,
  "updated_by_user_id" UUID,
  "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updated_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "ecf_electronic_documents_pkey" PRIMARY KEY ("id")
);

CREATE TABLE "ecf_electronic_document_attempts" (
  "id" UUID NOT NULL DEFAULT gen_random_uuid(),
  "company_id" UUID NOT NULL,
  "document_id" UUID NOT NULL,
  "operation" "ecf_electronic_document_operation" NOT NULL,
  "status_before" "ecf_electronic_document_status",
  "status_after" "ecf_electronic_document_status",
  "idempotency_key" VARCHAR(160) NOT NULL,
  "request_fingerprint" VARCHAR(64),
  "response_ref" VARCHAR(256),
  "provider_request_id" VARCHAR(128),
  "safe_error_code" VARCHAR(64),
  "safe_error_message" TEXT,
  "created_by_user_id" UUID,
  "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "ecf_electronic_document_attempts_pkey" PRIMARY KEY ("id")
);

CREATE TABLE "ecf_electronic_document_status_logs" (
  "id" UUID NOT NULL DEFAULT gen_random_uuid(),
  "company_id" UUID NOT NULL,
  "document_id" UUID NOT NULL,
  "status_before" "ecf_electronic_document_status",
  "status_after" "ecf_electronic_document_status" NOT NULL,
  "reason_code" VARCHAR(64),
  "safe_message" TEXT,
  "metadata" JSONB,
  "changed_by_user_id" UUID,
  "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "ecf_electronic_document_status_logs_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX "ecf_electronic_documents_company_id_idempotency_key_key" ON "ecf_electronic_documents"("company_id", "idempotency_key");
CREATE UNIQUE INDEX "ecf_electronic_documents_company_id_payload_fingerprint_key" ON "ecf_electronic_documents"("company_id", "payload_fingerprint");
CREATE INDEX "ecf_electronic_documents_company_id_status_idx" ON "ecf_electronic_documents"("company_id", "status");
CREATE INDEX "ecf_electronic_documents_company_id_document_type_created_at_idx" ON "ecf_electronic_documents"("company_id", "document_type", "created_at");
CREATE INDEX "ecf_electronic_documents_company_id_source_type_source_id_idx" ON "ecf_electronic_documents"("company_id", "source_type", "source_id");
CREATE INDEX "ecf_electronic_documents_company_id_external_provider_id_idx" ON "ecf_electronic_documents"("company_id", "external_provider_id");
CREATE INDEX "ecf_electronic_documents_original_document_id_idx" ON "ecf_electronic_documents"("original_document_id");

CREATE UNIQUE INDEX "ecf_electronic_document_attempts_company_id_operation_idempotency_key_key" ON "ecf_electronic_document_attempts"("company_id", "operation", "idempotency_key");
CREATE INDEX "ecf_electronic_document_attempts_company_id_document_id_created_at_idx" ON "ecf_electronic_document_attempts"("company_id", "document_id", "created_at");
CREATE INDEX "ecf_electronic_document_attempts_company_id_operation_created_at_idx" ON "ecf_electronic_document_attempts"("company_id", "operation", "created_at");

CREATE INDEX "ecf_electronic_document_status_logs_company_id_document_id_created_at_idx" ON "ecf_electronic_document_status_logs"("company_id", "document_id", "created_at");
CREATE INDEX "ecf_electronic_document_status_logs_company_id_status_after_created_at_idx" ON "ecf_electronic_document_status_logs"("company_id", "status_after", "created_at");

ALTER TABLE "ecf_electronic_documents" ADD CONSTRAINT "ecf_electronic_documents_company_id_fkey" FOREIGN KEY ("company_id") REFERENCES "companies"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "ecf_electronic_documents" ADD CONSTRAINT "ecf_electronic_documents_original_document_id_fkey" FOREIGN KEY ("original_document_id") REFERENCES "ecf_electronic_documents"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
ALTER TABLE "ecf_electronic_document_attempts" ADD CONSTRAINT "ecf_electronic_document_attempts_company_id_fkey" FOREIGN KEY ("company_id") REFERENCES "companies"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "ecf_electronic_document_attempts" ADD CONSTRAINT "ecf_electronic_document_attempts_document_id_fkey" FOREIGN KEY ("document_id") REFERENCES "ecf_electronic_documents"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "ecf_electronic_document_status_logs" ADD CONSTRAINT "ecf_electronic_document_status_logs_company_id_fkey" FOREIGN KEY ("company_id") REFERENCES "companies"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "ecf_electronic_document_status_logs" ADD CONSTRAINT "ecf_electronic_document_status_logs_document_id_fkey" FOREIGN KEY ("document_id") REFERENCES "ecf_electronic_documents"("id") ON DELETE CASCADE ON UPDATE CASCADE;
