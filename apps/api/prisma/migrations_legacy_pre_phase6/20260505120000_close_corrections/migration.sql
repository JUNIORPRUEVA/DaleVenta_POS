-- Add traceable correction metadata for daily closes.
ALTER TABLE "Close"
  ADD COLUMN IF NOT EXISTS "correctionOfCloseId" UUID,
  ADD COLUMN IF NOT EXISTS "correctionReason" TEXT;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'Close_correctionOfCloseId_fkey'
  ) THEN
    ALTER TABLE "Close"
      ADD CONSTRAINT "Close_correctionOfCloseId_fkey"
      FOREIGN KEY ("correctionOfCloseId") REFERENCES "Close"("id")
      ON DELETE RESTRICT ON UPDATE CASCADE;
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS "Close_correctionOfCloseId_idx"
  ON "Close"("correctionOfCloseId");
