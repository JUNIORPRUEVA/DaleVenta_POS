-- Add fixed insurance amount for payroll employees

ALTER TABLE "PayrollEmployee"
  ADD COLUMN IF NOT EXISTS "seguroLeyMonto" DECIMAL(12,2) NOT NULL DEFAULT 0;
