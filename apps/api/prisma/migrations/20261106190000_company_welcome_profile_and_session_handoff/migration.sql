-- Perfil de empresa: respuestas de la pantalla de bienvenida.
-- Aditivo y compatible: las filas existentes quedan con cadena vacía.
ALTER TABLE "app_config" ADD COLUMN IF NOT EXISTS "business_type" VARCHAR(80) NOT NULL DEFAULT '';
ALTER TABLE "app_config" ADD COLUMN IF NOT EXISTS "business_age_range" VARCHAR(40) NOT NULL DEFAULT '';
ALTER TABLE "app_config" ADD COLUMN IF NOT EXISTS "business_size" VARCHAR(40) NOT NULL DEFAULT '';
ALTER TABLE "app_config" ADD COLUMN IF NOT EXISTS "welcome_completed_at" TIMESTAMP(3);

-- Tickets de un solo uso para transferir una sesión autenticada del sitio
-- publico (Astro) a la app Flutter Web. Guarda solo el hash del ticket.
CREATE TABLE IF NOT EXISTS "session_handoff_tickets" (
    "id" UUID NOT NULL,
    "ticket_hash" TEXT NOT NULL,
    "user_id" UUID NOT NULL,
    "company_id" UUID,
    "session_id" UUID NOT NULL,
    "platform" VARCHAR(24) NOT NULL DEFAULT '',
    "expires_at" TIMESTAMP(3) NOT NULL,
    "used_at" TIMESTAMP(3),
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "session_handoff_tickets_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX IF NOT EXISTS "session_handoff_tickets_ticket_hash_key"
    ON "session_handoff_tickets"("ticket_hash");

CREATE INDEX IF NOT EXISTS "session_handoff_tickets_expires_at_idx"
    ON "session_handoff_tickets"("expires_at");

CREATE INDEX IF NOT EXISTS "session_handoff_tickets_user_id_used_at_idx"
    ON "session_handoff_tickets"("user_id", "used_at");
