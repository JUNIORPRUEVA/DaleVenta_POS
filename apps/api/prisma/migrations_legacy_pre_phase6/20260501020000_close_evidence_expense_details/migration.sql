-- Add POS closing voucher storage info and expense details JSON to Close table
ALTER TABLE "Close"
  ADD COLUMN "evidenceStorageKey" TEXT,
  ADD COLUMN "evidenceMimeType"   TEXT,
  ADD COLUMN "expenseDetails"     JSONB;
