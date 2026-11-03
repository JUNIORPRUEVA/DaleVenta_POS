-- Credenciales fiscales de DOSA: CIFRADAS, por empresa y por entorno.
--
-- Esta tabla NO contiene ningun valor en claro: guarda el criptograma
-- AES-256-GCM y los metadatos necesarios para descifrarlo. La clave se deriva
-- del contexto (company_id + rnc + environment), que ademas va como AAD, de modo
-- que un criptograma copiado a otra fila no se puede descifrar.
--
-- Migracion aditiva: no modifica ni elimina nada existente.

CREATE TABLE "ecf_dosa_company_credentials" (
    "id" UUID NOT NULL,
    "company_id" UUID NOT NULL,
    "rnc" VARCHAR(32) NOT NULL,
    "environment" VARCHAR(16) NOT NULL,
    "status" VARCHAR(32) NOT NULL,
    "source" VARCHAR(16) NOT NULL,
    "key_version" INTEGER NOT NULL,
    "ciphertext" TEXT NOT NULL,
    "iv" VARCHAR(64) NOT NULL,
    "auth_tag" VARCHAR(64) NOT NULL,
    "fingerprint" VARCHAR(64) NOT NULL,
    "present" JSONB NOT NULL,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "ecf_dosa_company_credentials_pkey" PRIMARY KEY ("id")
);

-- Una sola credencial por empresa, RNC y entorno: impide que un RNC herede las
-- credenciales de otra empresa o que test pise produccion.
CREATE UNIQUE INDEX "ecf_dosa_company_credentials_company_id_rnc_environment_key"
    ON "ecf_dosa_company_credentials"("company_id", "rnc", "environment");

CREATE INDEX "ecf_dosa_company_credentials_company_id_status_idx"
    ON "ecf_dosa_company_credentials"("company_id", "status");

ALTER TABLE "ecf_dosa_company_credentials"
    ADD CONSTRAINT "ecf_dosa_company_credentials_company_id_fkey"
    FOREIGN KEY ("company_id") REFERENCES "companies"("id")
    ON DELETE CASCADE ON UPDATE CASCADE;
