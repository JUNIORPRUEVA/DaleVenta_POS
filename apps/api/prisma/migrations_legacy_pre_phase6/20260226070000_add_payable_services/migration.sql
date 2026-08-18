-- CreateEnum
CREATE TYPE "PayableProviderKind" AS ENUM ('PERSON', 'COMPANY');

-- CreateEnum
CREATE TYPE "PayableFrequency" AS ENUM ('ONE_TIME', 'MONTHLY', 'BIWEEKLY');

-- CreateTable
CREATE TABLE "PayableService" (
    "id" UUID NOT NULL,
    "title" TEXT NOT NULL,
    "providerKind" "PayableProviderKind" NOT NULL,
    "providerName" TEXT NOT NULL,
    "description" TEXT,
    "frequency" "PayableFrequency" NOT NULL,
    "defaultAmount" DECIMAL(12,2),
    "nextDueDate" TIMESTAMP(3) NOT NULL,
    "lastPaidAt" TIMESTAMP(3),
    "active" BOOLEAN NOT NULL DEFAULT true,
    "createdById" UUID,
    "createdByName" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "PayableService_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "PayablePayment" (
    "id" UUID NOT NULL,
    "serviceId" UUID NOT NULL,
    "amount" DECIMAL(12,2) NOT NULL,
    "paidAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "note" TEXT,
    "createdById" UUID,
    "createdByName" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "PayablePayment_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "PayableService_active_nextDueDate_idx" ON "PayableService"("active", "nextDueDate");

-- CreateIndex
CREATE INDEX "PayableService_providerKind_idx" ON "PayableService"("providerKind");

-- CreateIndex
CREATE INDEX "PayableService_createdById_idx" ON "PayableService"("createdById");

-- CreateIndex
CREATE INDEX "PayablePayment_serviceId_paidAt_idx" ON "PayablePayment"("serviceId", "paidAt");

-- CreateIndex
CREATE INDEX "PayablePayment_paidAt_idx" ON "PayablePayment"("paidAt");

-- CreateIndex
CREATE INDEX "PayablePayment_createdById_idx" ON "PayablePayment"("createdById");

-- AddForeignKey
ALTER TABLE "PayablePayment" ADD CONSTRAINT "PayablePayment_serviceId_fkey" FOREIGN KEY ("serviceId") REFERENCES "PayableService"("id") ON DELETE CASCADE ON UPDATE CASCADE;
