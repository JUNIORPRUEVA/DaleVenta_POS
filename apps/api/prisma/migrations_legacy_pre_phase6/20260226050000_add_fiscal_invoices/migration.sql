-- CreateEnum
CREATE TYPE "FiscalInvoiceKind" AS ENUM ('SALE', 'PURCHASE');

-- CreateTable
CREATE TABLE "FiscalInvoice" (
    "id" UUID NOT NULL,
    "kind" "FiscalInvoiceKind" NOT NULL,
    "invoiceDate" TIMESTAMP(3) NOT NULL,
    "imageUrl" TEXT NOT NULL,
    "note" TEXT,
    "createdById" UUID,
    "createdByName" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "FiscalInvoice_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "FiscalInvoice_kind_idx" ON "FiscalInvoice"("kind");

-- CreateIndex
CREATE INDEX "FiscalInvoice_invoiceDate_idx" ON "FiscalInvoice"("invoiceDate");

-- CreateIndex
CREATE INDEX "FiscalInvoice_createdById_idx" ON "FiscalInvoice"("createdById");
