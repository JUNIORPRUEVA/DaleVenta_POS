-- Add identity/contact/document fields to User
ALTER TABLE "User"
  ADD COLUMN IF NOT EXISTS "telefonoFamiliar" TEXT,
  ADD COLUMN IF NOT EXISTS "cedula" TEXT,
  ADD COLUMN IF NOT EXISTS "fotoCedulaUrl" TEXT,
  ADD COLUMN IF NOT EXISTS "fotoLicenciaUrl" TEXT,
  ADD COLUMN IF NOT EXISTS "fotoPersonalUrl" TEXT;

CREATE UNIQUE INDEX IF NOT EXISTS "User_cedula_key" ON "User"("cedula");
