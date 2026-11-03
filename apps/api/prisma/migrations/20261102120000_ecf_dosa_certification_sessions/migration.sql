-- Sesión de certificación automática del asistente DOSA.
--
-- Modelo de INTENTOS: cada postulación es una fila, así que el historial se
-- conserva y una empresa puede repetir tras un intento fallido, cancelado o
-- vencido.
--
-- Los dos índices únicos son lo que hace TRANSACCIONAL el control:
--   * (company_id, rnc, attempt_no): no hay dos intentos con el mismo número.
--   * active_key: como mucho UN intento en curso por empresa y RNC. PostgreSQL
--     admite muchos NULL en un índice único, así que al cerrar el intento
--     (active_key = NULL) se libera el hueco sin borrar el historial.
--
-- NO aplicada todavía: esta fase la valida en una base desechable.

-- CreateEnum
CREATE TYPE "EcfDosaSessionStatus" AS ENUM ('NOT_STARTED', 'RUNNING', 'ATTENTION', 'COMPLETED', 'FAILED', 'CANCELLED', 'EXPIRED');

-- CreateTable
CREATE TABLE "ecf_dosa_certification_sessions" (
    "id" UUID NOT NULL,
    "company_id" UUID NOT NULL,
    "rnc" VARCHAR(32) NOT NULL,
    "attempt_no" INTEGER NOT NULL DEFAULT 1,
    "active_key" VARCHAR(96),
    "session_url" TEXT,
    "provider_postulation_id" VARCHAR(128),
    "status" "EcfDosaSessionStatus" NOT NULL DEFAULT 'NOT_STARTED',
    "last_event_type" VARCHAR(64),
    "last_event_at" TIMESTAMP(3),
    "provider_confirmed_at" TIMESTAMP(3),
    "closed_at" TIMESTAMP(3),
    "created_by_user_id" UUID,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "ecf_dosa_certification_sessions_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "ecf_dosa_certification_sessions_active_key_key" ON "ecf_dosa_certification_sessions"("active_key");

-- CreateIndex
CREATE UNIQUE INDEX "ecf_dosa_certification_sessions_company_id_rnc_attempt_no_key" ON "ecf_dosa_certification_sessions"("company_id", "rnc", "attempt_no");

-- CreateIndex
CREATE INDEX "ecf_dosa_certification_sessions_company_id_rnc_status_idx" ON "ecf_dosa_certification_sessions"("company_id", "rnc", "status");

-- CreateIndex
CREATE INDEX "ecf_dosa_certification_sessions_company_id_rnc_created_at_idx" ON "ecf_dosa_certification_sessions"("company_id", "rnc", "created_at");

-- AddForeignKey
ALTER TABLE "ecf_dosa_certification_sessions" ADD CONSTRAINT "ecf_dosa_certification_sessions_company_id_fkey" FOREIGN KEY ("company_id") REFERENCES "companies"("id") ON DELETE CASCADE ON UPDATE CASCADE;

