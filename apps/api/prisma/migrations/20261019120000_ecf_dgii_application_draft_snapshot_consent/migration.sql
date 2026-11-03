-- Expediente DGII: borrador persistente, snapshot versionado inmutable y consentimiento.
--
-- Alcance deliberadamente mínimo: SOLO las columnas, la tabla y el enum que este
-- incremento necesita. No toca ninguna otra tabla existente.

-- AlterEnum
ALTER TYPE "ecf_audit_action" ADD VALUE 'DGII_APPLICATION_DRAFT_SAVED';
ALTER TYPE "ecf_audit_action" ADD VALUE 'DGII_APPLICATION_SUBMITTED';
ALTER TYPE "ecf_audit_action" ADD VALUE 'DGII_CONSENT_ACCEPTED';

-- AlterTable
ALTER TABLE "ecf_dgii_habilitations" ADD COLUMN     "consent_accepted_at" TIMESTAMP(3),
ADD COLUMN     "consent_accepted_by_user_id" UUID,
ADD COLUMN     "consent_version" VARCHAR(32),
ADD COLUMN     "current_snapshot_version" INTEGER NOT NULL DEFAULT 0,
ADD COLUMN     "draft_payload" JSONB,
ADD COLUMN     "draft_updated_at" TIMESTAMP(3),
ADD COLUMN     "draft_updated_by_user_id" UUID;

-- CreateTable
CREATE TABLE "ecf_dgii_application_snapshots" (
    "id" UUID NOT NULL,
    "company_id" UUID NOT NULL,
    "version" INTEGER NOT NULL,
    "payload" JSONB NOT NULL,
    "payload_hash" VARCHAR(64) NOT NULL,
    "documents" JSONB NOT NULL,
    "documents_hash" VARCHAR(64) NOT NULL,
    "consent_version" VARCHAR(32) NOT NULL,
    "consent_accepted_at" TIMESTAMP(3) NOT NULL,
    "submitted_by_user_id" UUID NOT NULL,
    "submitted_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "ecf_dgii_application_snapshots_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "ecf_dgii_application_snapshots_company_id_submitted_at_idx" ON "ecf_dgii_application_snapshots"("company_id", "submitted_at");

-- CreateIndex
CREATE UNIQUE INDEX "ecf_dgii_application_snapshots_company_id_version_key" ON "ecf_dgii_application_snapshots"("company_id", "version");

-- AddForeignKey
ALTER TABLE "ecf_dgii_application_snapshots" ADD CONSTRAINT "ecf_dgii_application_snapshots_company_id_fkey" FOREIGN KEY ("company_id") REFERENCES "companies"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- Inmutabilidad a nivel de base de datos: un snapshot histórico no se reescribe
-- ni se borra. Las correcciones crean una versión nueva, nunca modifican la
-- anterior. Mismo criterio que `ecf_protect_fiscal_document` y
-- `ecf_sequence_identity_immutable`.
CREATE OR REPLACE FUNCTION ecf_dgii_snapshot_immutable()
RETURNS trigger AS $$
BEGIN
  RAISE EXCEPTION 'ecf_dgii_application_snapshots es inmutable: % no permitido', TG_OP;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER ecf_dgii_snapshot_immutable_trigger
BEFORE UPDATE OR DELETE ON "ecf_dgii_application_snapshots"
FOR EACH ROW EXECUTE FUNCTION ecf_dgii_snapshot_immutable();
