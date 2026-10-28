-- APPYRA Guardian AI — credenciales de maquina para ingesta server-to-server.
--
-- Aditivo y sin tocar tablas existentes. Permite que una instalacion de
-- DaleVentas POS envie telemetria a Guardian con una credencial propia, sin
-- reutilizar un JWT de usuario y sin que el cliente pueda elegir la empresa.
--
-- La clave en claro nunca se almacena: solo su SHA-256 (64 hex).

CREATE TABLE IF NOT EXISTS "guardian_machine_credentials" (
  "id" UUID NOT NULL,
  "company_id" UUID NOT NULL,
  "label" VARCHAR(120) NOT NULL,
  "key_hash" VARCHAR(64) NOT NULL,
  "key_prefix" VARCHAR(12) NOT NULL,
  "install_id" VARCHAR(120),
  "scopes" JSONB NOT NULL DEFAULT '[]',
  "enabled" BOOLEAN NOT NULL DEFAULT true,
  "last_used_at" TIMESTAMP(3),
  "expires_at" TIMESTAMP(3),
  "revoked_at" TIMESTAMP(3),
  "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updated_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "guardian_machine_credentials_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX IF NOT EXISTS "guardian_machine_credentials_key_hash_key"
  ON "guardian_machine_credentials" ("key_hash");

CREATE INDEX IF NOT EXISTS "guardian_machine_credentials_company_id_enabled_idx"
  ON "guardian_machine_credentials" ("company_id", "enabled");

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'guardian_machine_credentials_company_id_fkey'
  ) THEN
    ALTER TABLE "guardian_machine_credentials"
      ADD CONSTRAINT "guardian_machine_credentials_company_id_fkey"
      FOREIGN KEY ("company_id") REFERENCES "companies"("id")
      ON DELETE CASCADE ON UPDATE CASCADE;
  END IF;
END $$;
