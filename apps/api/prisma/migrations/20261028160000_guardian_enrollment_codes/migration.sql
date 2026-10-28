-- APPYRA Guardian AI — enrolamiento de instalaciones (Fase 2, agente Flutter).
--
-- Aditivo. Permite que una instalación de DaleVentas POS obtenga su propia
-- credencial de máquina con un código de un solo uso, sin incrustar secretos
-- compartidos en instaladores ni reutilizar JWT de usuario.
--
-- El código en claro nunca se guarda: solo su SHA-256 (64 hex).

CREATE TABLE IF NOT EXISTS "guardian_enrollment_codes" (
  "id" UUID NOT NULL,
  "company_id" UUID NOT NULL,
  "code_hash" VARCHAR(64) NOT NULL,
  "code_prefix" VARCHAR(12) NOT NULL,
  "label" VARCHAR(120) NOT NULL,
  "max_uses" INTEGER NOT NULL DEFAULT 1,
  "uses" INTEGER NOT NULL DEFAULT 0,
  "expires_at" TIMESTAMP(3) NOT NULL,
  "revoked_at" TIMESTAMP(3),
  "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updated_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "guardian_enrollment_codes_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX IF NOT EXISTS "guardian_enrollment_codes_code_hash_key"
  ON "guardian_enrollment_codes" ("code_hash");

CREATE INDEX IF NOT EXISTS "guardian_enrollment_codes_company_id_expires_at_idx"
  ON "guardian_enrollment_codes" ("company_id", "expires_at");

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'guardian_enrollment_codes_company_id_fkey'
  ) THEN
    ALTER TABLE "guardian_enrollment_codes"
      ADD CONSTRAINT "guardian_enrollment_codes_company_id_fkey"
      FOREIGN KEY ("company_id") REFERENCES "companies"("id")
      ON DELETE CASCADE ON UPDATE CASCADE;
  END IF;
END $$;
