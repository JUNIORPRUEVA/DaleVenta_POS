-- Cash module: daily cashboxes, cashier sessions, manual movements, and sale payment/session metadata.

CREATE TABLE IF NOT EXISTS "cashbox_daily" (
  "id" UUID NOT NULL DEFAULT gen_random_uuid(),
  "businessDate" TEXT NOT NULL,
  "openedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "openedByUserId" UUID NOT NULL,
  "initialAmount" DECIMAL(12,2) NOT NULL DEFAULT 0,
  "currentAmount" DECIMAL(12,2) NOT NULL DEFAULT 0,
  "status" TEXT NOT NULL DEFAULT 'OPEN',
  "closedAt" TIMESTAMP(3),
  "closedByUserId" UUID,
  "note" TEXT,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "cashbox_daily_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX IF NOT EXISTS "cashbox_daily_businessDate_key" ON "cashbox_daily"("businessDate");
CREATE INDEX IF NOT EXISTS "cashbox_daily_status_idx" ON "cashbox_daily"("status");

CREATE TABLE IF NOT EXISTS "cash_sessions" (
  "id" UUID NOT NULL DEFAULT gen_random_uuid(),
  "openedByUserId" UUID NOT NULL,
  "userName" TEXT,
  "openedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "initialAmount" DECIMAL(12,2) NOT NULL DEFAULT 0,
  "closingAmount" DECIMAL(12,2),
  "expectedAmount" DECIMAL(12,2),
  "difference" DECIMAL(12,2),
  "status" TEXT NOT NULL DEFAULT 'OPEN',
  "closedAt" TIMESTAMP(3),
  "closedByUserId" UUID,
  "cashboxDailyId" UUID,
  "businessDate" TEXT,
  "requiresClosure" BOOLEAN NOT NULL DEFAULT false,
  "note" TEXT,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "cash_sessions_pkey" PRIMARY KEY ("id")
);

CREATE INDEX IF NOT EXISTS "cash_sessions_openedByUserId_status_idx" ON "cash_sessions"("openedByUserId", "status");
CREATE INDEX IF NOT EXISTS "cash_sessions_cashboxDailyId_idx" ON "cash_sessions"("cashboxDailyId");
CREATE INDEX IF NOT EXISTS "cash_sessions_businessDate_idx" ON "cash_sessions"("businessDate");

ALTER TABLE "cash_sessions"
  ADD CONSTRAINT "cash_sessions_cashboxDailyId_fkey"
  FOREIGN KEY ("cashboxDailyId") REFERENCES "cashbox_daily"("id") ON DELETE SET NULL ON UPDATE CASCADE;

CREATE TABLE IF NOT EXISTS "cash_movements" (
  "id" UUID NOT NULL DEFAULT gen_random_uuid(),
  "sessionId" UUID NOT NULL,
  "type" TEXT NOT NULL,
  "amount" DECIMAL(12,2) NOT NULL,
  "reason" TEXT,
  "movementType" TEXT NOT NULL DEFAULT 'expense',
  "affectsProfit" BOOLEAN NOT NULL DEFAULT true,
  "userId" UUID,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "cash_movements_pkey" PRIMARY KEY ("id")
);

CREATE INDEX IF NOT EXISTS "cash_movements_sessionId_idx" ON "cash_movements"("sessionId");
CREATE INDEX IF NOT EXISTS "cash_movements_createdAt_idx" ON "cash_movements"("createdAt");

ALTER TABLE "cash_movements"
  ADD CONSTRAINT "cash_movements_sessionId_fkey"
  FOREIGN KEY ("sessionId") REFERENCES "cash_sessions"("id") ON DELETE CASCADE ON UPDATE CASCADE;

ALTER TABLE "Sale"
  ADD COLUMN IF NOT EXISTS "cashSessionId" UUID,
  ADD COLUMN IF NOT EXISTS "paymentMethod" TEXT NOT NULL DEFAULT 'cash',
  ADD COLUMN IF NOT EXISTS "paymentCashAmount" DECIMAL(12,2) NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS "paymentTransferAmount" DECIMAL(12,2) NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS "kind" TEXT NOT NULL DEFAULT 'invoice',
  ADD COLUMN IF NOT EXISTS "status" TEXT NOT NULL DEFAULT 'PAID';

CREATE INDEX IF NOT EXISTS "Sale_cashSessionId_idx" ON "Sale"("cashSessionId");

ALTER TABLE "Sale"
  ADD CONSTRAINT "Sale_cashSessionId_fkey"
  FOREIGN KEY ("cashSessionId") REFERENCES "cash_sessions"("id") ON DELETE SET NULL ON UPDATE CASCADE;
