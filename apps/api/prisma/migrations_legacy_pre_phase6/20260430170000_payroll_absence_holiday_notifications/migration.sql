ALTER TYPE "PayrollEntryType" ADD VALUE IF NOT EXISTS 'FERIADO_TRABAJADO';

ALTER TABLE "PayrollEmployee"
  ADD COLUMN IF NOT EXISTS "seguro_ley_monto_locked" BOOLEAN NOT NULL DEFAULT false;

UPDATE "PayrollEmployee"
SET "seguro_ley_monto_locked" = true
WHERE "seguroLeyMonto" IS NOT NULL;
