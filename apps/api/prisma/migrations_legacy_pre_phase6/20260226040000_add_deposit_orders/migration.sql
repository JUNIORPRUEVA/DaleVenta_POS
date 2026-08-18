-- CreateEnum
CREATE TYPE "DepositOrderStatus" AS ENUM ('PENDING', 'EXECUTED', 'CANCELLED');

-- CreateTable
CREATE TABLE "DepositOrder" (
    "id" UUID NOT NULL,
    "windowFrom" TIMESTAMP(3) NOT NULL,
    "windowTo" TIMESTAMP(3) NOT NULL,
    "bankName" TEXT NOT NULL,
    "reserveAmount" DECIMAL(12,2) NOT NULL,
    "totalAvailableCash" DECIMAL(12,2) NOT NULL,
    "depositTotal" DECIMAL(12,2) NOT NULL,
    "closesCountByType" JSONB NOT NULL,
    "depositByType" JSONB NOT NULL,
    "accountByType" JSONB NOT NULL,
    "status" "DepositOrderStatus" NOT NULL DEFAULT 'PENDING',
    "createdById" UUID,
    "createdByName" TEXT,
    "executedById" UUID,
    "executedByName" TEXT,
    "executedAt" TIMESTAMP(3),
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "DepositOrder_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "DepositOrder_windowFrom_windowTo_idx" ON "DepositOrder"("windowFrom", "windowTo");

-- CreateIndex
CREATE INDEX "DepositOrder_status_idx" ON "DepositOrder"("status");

-- CreateIndex
CREATE INDEX "DepositOrder_createdById_idx" ON "DepositOrder"("createdById");
