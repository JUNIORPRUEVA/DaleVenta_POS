-- Store work contract signature metadata on users
ALTER TABLE users
  ADD COLUMN IF NOT EXISTS "workContractSignatureUrl" TEXT,
  ADD COLUMN IF NOT EXISTS "workContractSignedAt" TIMESTAMP(3),
  ADD COLUMN IF NOT EXISTS "workContractVersion" TEXT;
