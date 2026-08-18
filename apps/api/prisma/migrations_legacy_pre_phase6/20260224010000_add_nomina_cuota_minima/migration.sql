-- Add cuota minima (quincenal goal) for payroll employees

ALTER TABLE "PayrollEmployee"
  ADD COLUMN IF NOT EXISTS "cuotaMinima" DECIMAL(12,2) NOT NULL DEFAULT 0;
