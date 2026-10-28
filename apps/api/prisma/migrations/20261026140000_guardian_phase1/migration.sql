-- APPYRA Guardian AI — Fase 1 (aditivo).
-- Solo crea objetos nuevos: enums guardian, tablas guardian_* e indices/FKs propios.
-- No modifica tablas existentes.

-- CreateEnum
CREATE TYPE "GuardianSeverity" AS ENUM ('SEV1', 'SEV2', 'SEV3', 'SEV4');

-- CreateEnum
CREATE TYPE "GuardianIncidentStatus" AS ENUM ('OPEN', 'ACKNOWLEDGED', 'INVESTIGATING', 'RESOLVED', 'CLOSED', 'WONT_FIX');

-- CreateEnum
CREATE TYPE "GuardianProcessingState" AS ENUM ('PENDING', 'DIAGNOSING', 'DIAGNOSED', 'FAILED', 'SKIPPED');

-- CreateEnum
CREATE TYPE "GuardianDiagnosisVerdict" AS ENUM ('CONFIRMED', 'PROBABLE', 'INSUFFICIENT');

-- CreateEnum
CREATE TYPE "GuardianDiagnosisStatus" AS ENUM ('PENDING', 'RUNNING', 'DONE', 'FAILED');

-- CreateTable
CREATE TABLE "guardian_incident_groups" (
    "id" UUID NOT NULL,
    "fingerprint" VARCHAR(80) NOT NULL,
    "module" VARCHAR(40) NOT NULL,
    "operation" VARCHAR(80) NOT NULL,
    "exception_type" VARCHAR(120),
    "severity" "GuardianSeverity" NOT NULL,
    "first_seen_at" TIMESTAMP(3) NOT NULL,
    "last_seen_at" TIMESTAMP(3) NOT NULL,
    "incident_count" INTEGER NOT NULL DEFAULT 0,
    "company_count" INTEGER NOT NULL DEFAULT 0,
    "companies" JSONB NOT NULL DEFAULT '[]',
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "guardian_incident_groups_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "guardian_incidents" (
    "id" UUID NOT NULL,
    "event_id" VARCHAR(120) NOT NULL,
    "company_id" UUID NOT NULL,
    "group_id" UUID,
    "fingerprint" VARCHAR(80) NOT NULL,
    "module" VARCHAR(40) NOT NULL,
    "operation" VARCHAR(80) NOT NULL,
    "platform" VARCHAR(24),
    "app_version" VARCHAR(40),
    "device_id" VARCHAR(120),
    "user_id" UUID,
    "severity" "GuardianSeverity" NOT NULL,
    "exception_type" VARCHAR(120),
    "status" "GuardianIncidentStatus" NOT NULL DEFAULT 'OPEN',
    "processing_state" "GuardianProcessingState" NOT NULL DEFAULT 'PENDING',
    "diagnosis_attempts" INTEGER NOT NULL DEFAULT 0,
    "next_diagnosis_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "correlation_id" VARCHAR(128),
    "stack" TEXT,
    "occurred_at" TIMESTAMP(3) NOT NULL,
    "received_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "offline_minutes" INTEGER,
    "schema_version" INTEGER NOT NULL DEFAULT 1,
    "payload" JSONB NOT NULL DEFAULT '{}',
    "impact_summary" VARCHAR(400),
    "acknowledged_at" TIMESTAMP(3),
    "acknowledged_by_user_id" UUID,
    "resolved_at" TIMESTAMP(3),
    "resolved_by_user_id" UUID,
    "resolution_note" VARCHAR(600),
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "guardian_incidents_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "guardian_evidences" (
    "id" UUID NOT NULL,
    "incident_id" UUID NOT NULL,
    "kind" VARCHAR(40) NOT NULL,
    "label" VARCHAR(120) NOT NULL,
    "size_bytes" INTEGER NOT NULL DEFAULT 0,
    "content" JSONB NOT NULL DEFAULT '{}',
    "redacted" BOOLEAN NOT NULL DEFAULT true,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "guardian_evidences_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "guardian_diagnoses" (
    "id" UUID NOT NULL,
    "incident_id" UUID NOT NULL,
    "status" "GuardianDiagnosisStatus" NOT NULL DEFAULT 'PENDING',
    "verdict" "GuardianDiagnosisVerdict",
    "confidence" DECIMAL(3,2),
    "summary" TEXT,
    "impact" VARCHAR(600),
    "cause_category" VARCHAR(60),
    "explanation" TEXT,
    "next_steps" JSONB NOT NULL DEFAULT '[]',
    "evidence_refs" JSONB NOT NULL DEFAULT '[]',
    "tool_calls" JSONB NOT NULL DEFAULT '[]',
    "model" VARCHAR(60),
    "prompt_hash" VARCHAR(80),
    "tokens_used" INTEGER NOT NULL DEFAULT 0,
    "duration_ms" INTEGER NOT NULL DEFAULT 0,
    "attempts" INTEGER NOT NULL DEFAULT 0,
    "error" VARCHAR(600),
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "guardian_diagnoses_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "guardian_incident_events" (
    "id" UUID NOT NULL,
    "incident_id" UUID NOT NULL,
    "from_status" VARCHAR(24),
    "to_status" VARCHAR(24) NOT NULL,
    "actor" VARCHAR(60) NOT NULL,
    "actor_user_id" UUID,
    "note" VARCHAR(600),
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "guardian_incident_events_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "guardian_access_logs" (
    "id" BIGSERIAL NOT NULL,
    "actor_user_id" UUID,
    "actor_role" VARCHAR(40),
    "action" VARCHAR(40) NOT NULL,
    "incident_id" UUID,
    "company_id" UUID,
    "ip" VARCHAR(64),
    "request_id" VARCHAR(128),
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "guardian_access_logs_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "guardian_company_quotas" (
    "company_id" UUID NOT NULL,
    "enabled" BOOLEAN NOT NULL DEFAULT true,
    "incidents_per_hour" INTEGER NOT NULL DEFAULT 60,
    "incidents_per_day" INTEGER NOT NULL DEFAULT 500,
    "bytes_per_day" INTEGER NOT NULL DEFAULT 5242880,
    "updated_at" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "guardian_company_quotas_pkey" PRIMARY KEY ("company_id")
);

-- CreateIndex
CREATE UNIQUE INDEX "guardian_incident_groups_fingerprint_key" ON "guardian_incident_groups"("fingerprint");

-- CreateIndex
CREATE INDEX "guardian_incident_groups_last_seen_at_idx" ON "guardian_incident_groups"("last_seen_at");

-- CreateIndex
CREATE INDEX "guardian_incidents_company_id_occurred_at_idx" ON "guardian_incidents"("company_id", "occurred_at");

-- CreateIndex
CREATE INDEX "guardian_incidents_fingerprint_occurred_at_idx" ON "guardian_incidents"("fingerprint", "occurred_at");

-- CreateIndex
CREATE INDEX "guardian_incidents_status_severity_occurred_at_idx" ON "guardian_incidents"("status", "severity", "occurred_at");

-- CreateIndex
CREATE INDEX "guardian_incidents_processing_state_next_diagnosis_at_idx" ON "guardian_incidents"("processing_state", "next_diagnosis_at");

-- CreateIndex
CREATE UNIQUE INDEX "guardian_incidents_company_id_event_id_key" ON "guardian_incidents"("company_id", "event_id");

-- CreateIndex
CREATE INDEX "guardian_evidences_incident_id_kind_idx" ON "guardian_evidences"("incident_id", "kind");

-- CreateIndex
CREATE INDEX "guardian_diagnoses_incident_id_created_at_idx" ON "guardian_diagnoses"("incident_id", "created_at");

-- CreateIndex
CREATE INDEX "guardian_diagnoses_status_idx" ON "guardian_diagnoses"("status");

-- CreateIndex
CREATE INDEX "guardian_incident_events_incident_id_created_at_idx" ON "guardian_incident_events"("incident_id", "created_at");

-- CreateIndex
CREATE INDEX "guardian_access_logs_created_at_idx" ON "guardian_access_logs"("created_at");

-- CreateIndex
CREATE INDEX "guardian_access_logs_incident_id_idx" ON "guardian_access_logs"("incident_id");

-- AddForeignKey
ALTER TABLE "guardian_incidents" ADD CONSTRAINT "guardian_incidents_company_id_fkey" FOREIGN KEY ("company_id") REFERENCES "companies"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "guardian_incidents" ADD CONSTRAINT "guardian_incidents_group_id_fkey" FOREIGN KEY ("group_id") REFERENCES "guardian_incident_groups"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "guardian_evidences" ADD CONSTRAINT "guardian_evidences_incident_id_fkey" FOREIGN KEY ("incident_id") REFERENCES "guardian_incidents"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "guardian_diagnoses" ADD CONSTRAINT "guardian_diagnoses_incident_id_fkey" FOREIGN KEY ("incident_id") REFERENCES "guardian_incidents"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "guardian_incident_events" ADD CONSTRAINT "guardian_incident_events_incident_id_fkey" FOREIGN KEY ("incident_id") REFERENCES "guardian_incidents"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "guardian_company_quotas" ADD CONSTRAINT "guardian_company_quotas_company_id_fkey" FOREIGN KEY ("company_id") REFERENCES "companies"("id") ON DELETE CASCADE ON UPDATE CASCADE;


-- CreateIndex
CREATE INDEX "guardian_incidents_company_id_received_at_idx" ON "guardian_incidents"("company_id", "received_at");
