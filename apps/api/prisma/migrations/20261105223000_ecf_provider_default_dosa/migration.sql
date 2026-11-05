-- El proveedor efectivo por defecto pasa a ser DOSA.
-- ALANUBE permanece en el enum para leer y conservar el historial existente.
ALTER TABLE "ecf_company_configurations"
  ALTER COLUMN "provider" SET DEFAULT 'DOSA'::"ecf_provider";
