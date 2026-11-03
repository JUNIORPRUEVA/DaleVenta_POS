-- Habilitación DGII POR EMPRESA (aditivo y compatible).
--
-- Alcance deliberadamente mínimo: solo los objetos del módulo de habilitación
-- DGII. El `prisma migrate diff` contra la base efímera reveló además deriva
-- PREEXISTENTE no relacionada con este cambio (renombrado de índices de
-- `ecf_electronic_document_*`, `DROP DEFAULT` de columnas UUID e índice único de
-- `telemetry_outbox.dedupe_key`). Esa deriva NO se corrige aquí: queda fuera del
-- alcance de esta tarea y se reporta por separado.

-- CreateEnum
CREATE TYPE "ecf_dgii_habilitation_state" AS ENUM ('NOT_STARTED', 'PREPARING_REQUIREMENTS', 'APPLICATION_PENDING', 'IN_PROGRESS', 'TESTS_PENDING', 'IN_CERTIFICATION', 'APPROVED', 'REJECTED', 'REQUIRES_CORRECTION');

-- CreateEnum
CREATE TYPE "ecf_evidence_source" AS ENUM ('MANUAL_DECLARATION', 'OFFICIAL_DOCUMENT', 'PROVIDER_ARTIFACT');

-- CreateEnum
CREATE TYPE "ecf_dgii_verification_source" AS ENUM ('NONE', 'MANUAL_OPERATOR_DECLARATION', 'PROVIDER_CONFIRMATION', 'DGII_OFFICIAL_RECORD');

-- AlterEnum
-- Los nuevos valores NO se usan dentro de esta misma migración: la tabla nueva
-- emplea enumerados distintos. Es lo que permite añadirlos en una transacción
-- (PostgreSQL >= 12).
ALTER TYPE "ecf_audit_action" ADD VALUE 'DGII_EVIDENCE_REGISTERED';
ALTER TYPE "ecf_audit_action" ADD VALUE 'DGII_HABILITATION_UPDATED';
ALTER TYPE "ecf_audit_action" ADD VALUE 'DGII_AUTHORIZATION_RECORDED';
ALTER TYPE "ecf_audit_action" ADD VALUE 'DGII_AUTHORIZATION_REVOKED';

-- AlterTable
ALTER TABLE "ecf_evidences" ADD COLUMN     "source" "ecf_evidence_source" NOT NULL DEFAULT 'MANUAL_DECLARATION';

-- CreateTable
CREATE TABLE "ecf_dgii_habilitations" (
    "id" UUID NOT NULL,
    "company_id" UUID NOT NULL,
    "state" "ecf_dgii_habilitation_state" NOT NULL DEFAULT 'NOT_STARTED',
    "review_state" VARCHAR(64),
    "requirements" JSONB,
    "external_id" VARCHAR(128),
    "observations" TEXT,
    "responsible_user_id" UUID,
    "started_at" TIMESTAMP(3),
    "authorized_at" TIMESTAMP(3),
    "authorization_source" "ecf_dgii_verification_source" NOT NULL DEFAULT 'NONE',
    "authorization_evidence_id" UUID,
    "created_by_user_id" UUID,
    "updated_by_user_id" UUID,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "ecf_dgii_habilitations_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "ecf_dgii_habilitations_company_id_key" ON "ecf_dgii_habilitations"("company_id");

-- CreateIndex
CREATE INDEX "ecf_dgii_habilitations_company_id_state_idx" ON "ecf_dgii_habilitations"("company_id", "state");

-- CreateIndex
CREATE INDEX "ecf_dgii_habilitations_company_id_updated_at_idx" ON "ecf_dgii_habilitations"("company_id", "updated_at");

-- CreateIndex
CREATE INDEX "ecf_evidences_company_id_source_idx" ON "ecf_evidences"("company_id", "source");

-- AddForeignKey
ALTER TABLE "ecf_dgii_habilitations" ADD CONSTRAINT "ecf_dgii_habilitations_company_id_fkey" FOREIGN KEY ("company_id") REFERENCES "companies"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "ecf_dgii_habilitations" ADD CONSTRAINT "ecf_dgii_habilitations_authorization_evidence_id_fkey" FOREIGN KEY ("authorization_evidence_id") REFERENCES "ecf_evidences"("id") ON DELETE SET NULL ON UPDATE CASCADE;
