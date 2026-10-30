-- Revisión interna de evidencias de habilitación DGII (aditivo y compatible).
--
-- Alcance deliberadamente mínimo: solo los objetos de esta mejora. El
-- `prisma migrate diff` contra la base efímera sigue mostrando deriva
-- PREEXISTENTE y ajena (DROP DEFAULT de columnas UUID e índice único parcial de
-- `telemetry_outbox`); no se corrige aquí.
--
-- La revisión interna es una dimensión SEPARADA del origen de la evidencia:
-- «quién la entregó» (`ecf_evidence_source`) y «si alguien la revisó»
-- (`ecf_evidence_review_status`) son dos hechos distintos, y ninguno de los dos
-- autoriza nada por sí solo.

-- CreateEnum
CREATE TYPE "ecf_evidence_review_status" AS ENUM ('PENDING', 'REVIEWED', 'REJECTED');

-- AlterEnum
-- El valor nuevo no se usa dentro de esta misma migración.
ALTER TYPE "ecf_audit_action" ADD VALUE 'DGII_EVIDENCE_REVIEWED';

-- AlterTable
ALTER TABLE "ecf_evidences" ADD COLUMN     "review_note" TEXT,
ADD COLUMN     "review_status" "ecf_evidence_review_status" NOT NULL DEFAULT 'PENDING',
ADD COLUMN     "reviewed_at" TIMESTAMP(3),
ADD COLUMN     "reviewed_by_user_id" UUID;

-- CreateIndex
CREATE INDEX "ecf_evidences_company_id_review_status_idx" ON "ecf_evidences"("company_id", "review_status");
