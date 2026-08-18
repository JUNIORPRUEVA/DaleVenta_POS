-- Add HR/payroll/profile fields to users
ALTER TABLE users
  ADD COLUMN IF NOT EXISTS "fechaIngreso" TIMESTAMP(3),
  ADD COLUMN IF NOT EXISTS "fechaNacimiento" TIMESTAMP(3),
  ADD COLUMN IF NOT EXISTS "cuentaNominaPreferencial" TEXT,
  ADD COLUMN IF NOT EXISTS "habilidades" JSONB;
