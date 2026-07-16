ALTER TABLE "Sale"
ADD COLUMN IF NOT EXISTS "creditAmount" DECIMAL(12,2) NOT NULL DEFAULT 0,
ADD COLUMN IF NOT EXISTS "creditPaidAmount" DECIMAL(12,2) NOT NULL DEFAULT 0,
ADD COLUMN IF NOT EXISTS "creditBalance" DECIMAL(12,2) NOT NULL DEFAULT 0,
ADD COLUMN IF NOT EXISTS "creditStatus" TEXT NOT NULL DEFAULT 'none';

CREATE TABLE IF NOT EXISTS "sale_credit_payments" (
  "id" UUID NOT NULL DEFAULT gen_random_uuid(),
  "saleId" UUID NOT NULL,
  "userId" UUID NOT NULL,
  "cashSessionId" UUID,
  "amount" DECIMAL(12,2) NOT NULL,
  "cashAmount" DECIMAL(12,2) NOT NULL DEFAULT 0,
  "transferAmount" DECIMAL(12,2) NOT NULL DEFAULT 0,
  "note" TEXT,
  "paidAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "sale_credit_payments_pkey" PRIMARY KEY ("id")
);

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'sale_credit_payments_saleId_fkey'
  ) THEN
    ALTER TABLE "sale_credit_payments"
    ADD CONSTRAINT "sale_credit_payments_saleId_fkey"
    FOREIGN KEY ("saleId") REFERENCES "Sale"("id") ON DELETE CASCADE ON UPDATE CASCADE;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'sale_credit_payments_userId_fkey'
  ) THEN
    ALTER TABLE "sale_credit_payments"
    ADD CONSTRAINT "sale_credit_payments_userId_fkey"
    FOREIGN KEY ("userId") REFERENCES "users"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'sale_credit_payments_cashSessionId_fkey'
  ) THEN
    ALTER TABLE "sale_credit_payments"
    ADD CONSTRAINT "sale_credit_payments_cashSessionId_fkey"
    FOREIGN KEY ("cashSessionId") REFERENCES "cash_sessions"("id") ON DELETE SET NULL ON UPDATE CASCADE;
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS "Sale_creditStatus_idx" ON "Sale"("creditStatus");
CREATE INDEX IF NOT EXISTS "sale_credit_payments_saleId_idx" ON "sale_credit_payments"("saleId");
CREATE INDEX IF NOT EXISTS "sale_credit_payments_userId_idx" ON "sale_credit_payments"("userId");
CREATE INDEX IF NOT EXISTS "sale_credit_payments_cashSessionId_idx" ON "sale_credit_payments"("cashSessionId");
CREATE INDEX IF NOT EXISTS "sale_credit_payments_paidAt_idx" ON "sale_credit_payments"("paidAt");
