-- Accounting daily closing control.
ALTER TYPE "CloseType" ADD VALUE IF NOT EXISTS 'PHYTOEMAGRY';

ALTER TABLE "Close"
ADD COLUMN IF NOT EXISTS "otherIncome" DECIMAL(12,2) NOT NULL DEFAULT 0,
ADD COLUMN IF NOT EXISTS "totalIncome" DECIMAL(12,2) NOT NULL DEFAULT 0,
ADD COLUMN IF NOT EXISTS "netTotal" DECIMAL(12,2) NOT NULL DEFAULT 0,
ADD COLUMN IF NOT EXISTS "difference" DECIMAL(12,2) NOT NULL DEFAULT 0,
ADD COLUMN IF NOT EXISTS "notes" TEXT,
ADD COLUMN IF NOT EXISTS "evidenceUrl" TEXT,
ADD COLUMN IF NOT EXISTS "evidenceFileName" TEXT,
ADD COLUMN IF NOT EXISTS "pdfUrl" TEXT,
ADD COLUMN IF NOT EXISTS "pdfStorageKey" TEXT,
ADD COLUMN IF NOT EXISTS "pdfFileName" TEXT,
ADD COLUMN IF NOT EXISTS "notificationStatus" TEXT,
ADD COLUMN IF NOT EXISTS "notificationError" TEXT,
ADD COLUMN IF NOT EXISTS "reviewedById" UUID,
ADD COLUMN IF NOT EXISTS "reviewedByName" TEXT,
ADD COLUMN IF NOT EXISTS "reviewedAt" TIMESTAMP(3),
ADD COLUMN IF NOT EXISTS "reviewNote" TEXT,
ADD COLUMN IF NOT EXISTS "aiRiskLevel" TEXT,
ADD COLUMN IF NOT EXISTS "aiReportSummary" TEXT,
ADD COLUMN IF NOT EXISTS "aiReportJson" JSONB,
ADD COLUMN IF NOT EXISTS "aiGeneratedAt" TIMESTAMP(3);

UPDATE "Close" SET "status" = 'approved' WHERE "status" = 'closed';
UPDATE "Close" SET "status" = 'pending' WHERE "status" IS NULL OR "status" = 'draft';
UPDATE "Close"
SET
  "totalIncome" = COALESCE("cash", 0) + COALESCE("transfer", 0) + COALESCE("card", 0) + COALESCE("otherIncome", 0),
  "netTotal" = COALESCE("cash", 0) + COALESCE("transfer", 0) + COALESCE("card", 0) + COALESCE("otherIncome", 0) - COALESCE("expenses", 0),
  "difference" = COALESCE("cash", 0) - COALESCE("cashDelivered", 0);

CREATE INDEX IF NOT EXISTS "Close_reviewedById_idx" ON "Close"("reviewedById");
CREATE INDEX IF NOT EXISTS "Close_status_idx" ON "Close"("status");

CREATE INDEX IF NOT EXISTS "Close_type_date_active_idx"
ON "Close"("type", "date")
WHERE "status" <> 'rejected';

CREATE TABLE IF NOT EXISTS "CloseTransfer" (
  "id" UUID NOT NULL DEFAULT gen_random_uuid(),
  "closeId" UUID NOT NULL,
  "bankName" TEXT NOT NULL,
  "amount" DECIMAL(12,2) NOT NULL,
  "referenceNumber" TEXT,
  "note" TEXT,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "CloseTransfer_pkey" PRIMARY KEY ("id"),
  CONSTRAINT "CloseTransfer_closeId_fkey" FOREIGN KEY ("closeId") REFERENCES "Close"("id") ON DELETE CASCADE ON UPDATE CASCADE
);

CREATE TABLE IF NOT EXISTS "CloseTransferVoucher" (
  "id" UUID NOT NULL DEFAULT gen_random_uuid(),
  "transferId" UUID NOT NULL,
  "storageKey" TEXT NOT NULL,
  "fileUrl" TEXT NOT NULL,
  "fileName" TEXT NOT NULL,
  "mimeType" TEXT NOT NULL,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "CloseTransferVoucher_pkey" PRIMARY KEY ("id"),
  CONSTRAINT "CloseTransferVoucher_transferId_fkey" FOREIGN KEY ("transferId") REFERENCES "CloseTransfer"("id") ON DELETE CASCADE ON UPDATE CASCADE
);

CREATE INDEX IF NOT EXISTS "CloseTransfer_closeId_idx" ON "CloseTransfer"("closeId");
CREATE INDEX IF NOT EXISTS "CloseTransferVoucher_transferId_idx" ON "CloseTransferVoucher"("transferId");
