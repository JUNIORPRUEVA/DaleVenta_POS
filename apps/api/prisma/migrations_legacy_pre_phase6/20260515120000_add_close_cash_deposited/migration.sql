ALTER TABLE "Close"
ADD COLUMN IF NOT EXISTS "cashDeposited" BOOLEAN NOT NULL DEFAULT false,
ADD COLUMN IF NOT EXISTS "cashDepositedAt" TIMESTAMP(3),
ADD COLUMN IF NOT EXISTS "cashDepositedById" UUID,
ADD COLUMN IF NOT EXISTS "cashDepositedByName" TEXT;

CREATE INDEX IF NOT EXISTS "Close_cashDeposited_idx" ON "Close"("cashDeposited");