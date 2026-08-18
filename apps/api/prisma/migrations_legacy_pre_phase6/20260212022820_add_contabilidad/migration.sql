-- CreateEnum
CREATE TYPE "CloseType" AS ENUM ('CAPSULAS', 'POS', 'TIENDA');

-- CreateTable
CREATE TABLE "Close" (
    "id" UUID NOT NULL,
    "type" "CloseType" NOT NULL,
    "date" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "status" TEXT NOT NULL,
    "cash" DECIMAL(12,2) NOT NULL,
    "transfer" DECIMAL(12,2) NOT NULL,
    "card" DECIMAL(12,2) NOT NULL,
    "expenses" DECIMAL(12,2) NOT NULL,
    "cashDelivered" DECIMAL(12,2) NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "Close_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "Close_date_idx" ON "Close"("date");

-- CreateIndex
CREATE INDEX "Close_type_idx" ON "Close"("type");
