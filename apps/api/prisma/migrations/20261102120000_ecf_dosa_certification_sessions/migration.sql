-- Sesión de certificación automática del asistente DOSA.
--
-- Una fila por empresa y RNC. El índice único es lo que hace TRANSACCIONAL el
-- control de duplicados: dos pestañas, dos dispositivos o un reintento del
-- navegador no pueden crear dos sesiones para la misma identidad fiscal.
--
-- NO aplicada: esta fase prepara el modelo. La migración se ejecuta cuando se
-- autorice (`prisma migrate deploy`) y, antes, contra una base desechable.

-- CreateEnum
CREATE TYPE "EcfDosaSessionStatus" AS ENUM ('NOT_STARTED', 'RUNNING', 'ATTENTION', 'COMPLETED', 'FAILED');

-- CreateTable
CREATE TABLE "ecf_dosa_certification_sessions" (
    "id" UUID NOT NULL,
    "company_id" UUID NOT NULL,
    "rnc" VARCHAR(32) NOT NULL,
    "session_url" TEXT,
    "provider_postulation_id" VARCHAR(128),
    "status" "EcfDosaSessionStatus" NOT NULL DEFAULT 'NOT_STARTED',
    "last_event_type" VARCHAR(64),
    "last_event_at" TIMESTAMP(3),
    "provider_confirmed_at" TIMESTAMP(3),
    "created_by_user_id" UUID,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "ecf_dosa_certification_sessions_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "ecf_dosa_certification_sessions_company_id_status_idx" ON "ecf_dosa_certification_sessions"("company_id", "status");

-- CreateIndex
CREATE UNIQUE INDEX "ecf_dosa_certification_sessions_company_id_rnc_key" ON "ecf_dosa_certification_sessions"("company_id", "rnc");

-- AddForeignKey
ALTER TABLE "ecf_dosa_certification_sessions" ADD CONSTRAINT "ecf_dosa_certification_sessions_company_id_fkey" FOREIGN KEY ("company_id") REFERENCES "companies"("id") ON DELETE CASCADE ON UPDATE CASCADE;
