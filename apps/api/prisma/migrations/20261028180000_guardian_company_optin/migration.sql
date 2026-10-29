-- FASE 7 — Opt-in de APPYRA Guardian por empresa.
--
-- Aditivo y compatible hacia atrás:
--   * `guardian_enabled` arranca en FALSE: ninguna empresa existente ni nueva
--     queda instrumentada sin activación explícita.
--   * No se modifica ninguna tabla de negocio (ventas, caja, inventario,
--     offline) ni se tocan datos existentes.
--   * Reversible: la columna puede quedarse sin uso si se revierte la app.

ALTER TABLE "companies"
  ADD COLUMN IF NOT EXISTS "guardian_enabled" BOOLEAN NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS "guardian_enabled_at" TIMESTAMP(3),
  ADD COLUMN IF NOT EXISTS "guardian_enabled_by" VARCHAR(120);

-- Índice parcial para que el chequeo de política sea barato sin escanear todas
-- las empresas (la inmensa mayoría estará en false).
CREATE INDEX IF NOT EXISTS "companies_guardian_enabled_idx"
  ON "companies" ("guardian_enabled")
  WHERE "guardian_enabled" = true;
