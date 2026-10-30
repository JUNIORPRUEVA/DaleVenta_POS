-- Concesiones de ASISTENCIA del cliente a FULLTECH.
--
-- Por qué: hasta ahora el personal de plataforma entraba al expediente de
-- cualquier empresa solo por pertenecer a la lista de staff. Este modelo hace
-- que el acceso requiera, además, una concesión explícita, acotada y revocable
-- otorgada por la propia empresa.
--
-- Aditivo: no modifica ninguna tabla existente.

CREATE TYPE "ecf_support_scope" AS ENUM (
  'VIEW_DOSSIER',
  'REVIEW_EVIDENCE',
  'REQUEST_CORRECTION'
);

CREATE TABLE "ecf_support_grants" (
  "id" TEXT NOT NULL,
  "company_id" TEXT NOT NULL,
  "granted_by_user_id" TEXT NOT NULL,
  "scopes" "ecf_support_scope"[] NOT NULL,
  "reason" TEXT,
  "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "expires_at" TIMESTAMP(3) NOT NULL,
  "revoked_at" TIMESTAMP(3),
  "revoked_by_user_id" TEXT,

  CONSTRAINT "ecf_support_grants_pkey" PRIMARY KEY ("id")
);

CREATE INDEX "ecf_support_grants_company_idx"
  ON "ecf_support_grants" ("company_id", "created_at");

-- Una sola concesión ACTIVA por empresa. La creación concurrente choca aquí y
-- se convierte en un 409 explícito en lugar de dejar dos concesiones vigentes.
CREATE UNIQUE INDEX "ecf_support_grants_one_active_per_company"
  ON "ecf_support_grants" ("company_id")
  WHERE "revoked_at" IS NULL;
