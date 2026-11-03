-- Portal de certificacion automatica (DOSA) para administradores autorizados.
--
-- Dos tablas, ambas ADITIVAS: no modifican ni eliminan nada existente.
--
--  1. `ecf_certification_portal_tickets`: capacidad de un solo uso y corta
--     duracion que la app canjea por una sesion del portal. Solo se guarda el
--     hash SHA-256 del token, nunca el valor.
--  2. `ecf_certification_portal_sessions`: sesion ya autenticada. La empresa se
--     resuelve SIEMPRE desde esta fila, jamas desde el navegador, que es lo que
--     mantiene el aislamiento multiempresa.
--
-- Ninguna de las dos guarda datos fiscales, credenciales ni claves.

CREATE TABLE "ecf_certification_portal_tickets" (
    "id" UUID NOT NULL,
    "company_id" UUID NOT NULL,
    "user_id" UUID NOT NULL,
    "token_hash" VARCHAR(64) NOT NULL,
    "expires_at" TIMESTAMP(3) NOT NULL,
    "used_at" TIMESTAMP(3),
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "ecf_certification_portal_tickets_pkey" PRIMARY KEY ("id")
);

-- Un token no puede repetirse entre empresas ni entre tickets.
CREATE UNIQUE INDEX "ecf_certification_portal_tickets_token_hash_key"
    ON "ecf_certification_portal_tickets"("token_hash");

-- Limpieza y listado por empresa.
CREATE INDEX "ecf_certification_portal_tickets_company_id_expires_at_idx"
    ON "ecf_certification_portal_tickets"("company_id", "expires_at");

ALTER TABLE "ecf_certification_portal_tickets"
    ADD CONSTRAINT "ecf_certification_portal_tickets_company_id_fkey"
    FOREIGN KEY ("company_id") REFERENCES "companies"("id")
    ON DELETE CASCADE ON UPDATE CASCADE;

CREATE TABLE "ecf_certification_portal_sessions" (
    "id" UUID NOT NULL,
    "company_id" UUID NOT NULL,
    "user_id" UUID NOT NULL,
    "ticket_id" UUID,
    "token_hash" VARCHAR(64) NOT NULL,
    "expires_at" TIMESTAMP(3) NOT NULL,
    "revoked_at" TIMESTAMP(3),
    "last_seen_at" TIMESTAMP(3),
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "ecf_certification_portal_sessions_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX "ecf_certification_portal_sessions_token_hash_key"
    ON "ecf_certification_portal_sessions"("token_hash");

CREATE INDEX "ecf_certification_portal_sessions_company_id_expires_at_idx"
    ON "ecf_certification_portal_sessions"("company_id", "expires_at");

ALTER TABLE "ecf_certification_portal_sessions"
    ADD CONSTRAINT "ecf_certification_portal_sessions_company_id_fkey"
    FOREIGN KEY ("company_id") REFERENCES "companies"("id")
    ON DELETE CASCADE ON UPDATE CASCADE;
