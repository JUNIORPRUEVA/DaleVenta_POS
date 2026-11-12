-- Onboarding de activación «Activa tu FullPOS».
--
-- Cambio puramente aditivo:
--   * `company_onboarding_tasks` guarda SOLO los overrides del usuario
--     (tarea omitida y avance de un recorrido guiado). El estado "completada"
--     NO se guarda aquí: se deriva de los datos reales de la empresa
--     (productos, ventas, configuración fiscal, logo...).
--   * Dos marcas de tiempo en `companies` para no reabrir la bienvenida ni el
--     panel en cada inicio de sesión.
--
-- No modifica, renombra ni elimina columnas existentes. Ninguna escritura
-- toca ventas, caja, inventario, facturación electrónica ni historial.

CREATE TABLE IF NOT EXISTS "company_onboarding_tasks" (
    "id" UUID NOT NULL,
    "company_id" UUID NOT NULL,
    "task_key" VARCHAR(40) NOT NULL,
    "status" VARCHAR(16) NOT NULL DEFAULT 'PENDING',
    "skipped_at" TIMESTAMP(3),
    "completed_at" TIMESTAMP(3),
    "tour_step" INTEGER NOT NULL DEFAULT 0,
    "tour_seen_at" TIMESTAMP(3),
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "company_onboarding_tasks_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX IF NOT EXISTS "company_onboarding_tasks_company_id_task_key_key"
    ON "company_onboarding_tasks"("company_id", "task_key");

CREATE INDEX IF NOT EXISTS "company_onboarding_tasks_company_id_idx"
    ON "company_onboarding_tasks"("company_id");

ALTER TABLE "company_onboarding_tasks"
    ADD CONSTRAINT "company_onboarding_tasks_company_id_fkey"
    FOREIGN KEY ("company_id") REFERENCES "companies"("id")
    ON DELETE CASCADE ON UPDATE CASCADE;

ALTER TABLE "companies"
    ADD COLUMN IF NOT EXISTS "activation_welcome_seen_at" TIMESTAMP(3),
    ADD COLUMN IF NOT EXISTS "activation_dismissed_at" TIMESTAMP(3);
