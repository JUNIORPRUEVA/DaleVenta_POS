-- Extend ServiceFile to support R2/S3-style media storage (non-breaking).
-- NOTE: Existing uploads via /uploads keep working; new columns are nullable/default.

ALTER TABLE IF EXISTS "ServiceFile"
  ADD COLUMN IF NOT EXISTS "storageProvider" text NOT NULL DEFAULT 'LOCAL',
  ADD COLUMN IF NOT EXISTS "objectKey" text NULL,
  ADD COLUMN IF NOT EXISTS "originalFileName" text NULL,
  ADD COLUMN IF NOT EXISTS "mimeType" text NULL,
  ADD COLUMN IF NOT EXISTS "mediaType" text NULL,
  ADD COLUMN IF NOT EXISTS "kind" text NULL,
  ADD COLUMN IF NOT EXISTS "fileSize" integer NULL,
  ADD COLUMN IF NOT EXISTS "width" integer NULL,
  ADD COLUMN IF NOT EXISTS "height" integer NULL,
  ADD COLUMN IF NOT EXISTS "durationSeconds" integer NULL,
  ADD COLUMN IF NOT EXISTS "executionReportId" uuid NULL,
  ADD COLUMN IF NOT EXISTS "deletedAt" timestamptz NULL,
  ADD COLUMN IF NOT EXISTS "updatedAt" timestamptz NOT NULL DEFAULT now();

-- FK to execution report (optional)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'servicefile_execution_report_fk'
  ) THEN
    ALTER TABLE "ServiceFile"
      ADD CONSTRAINT servicefile_execution_report_fk
      FOREIGN KEY ("executionReportId")
      REFERENCES service_execution_reports(id)
      ON DELETE SET NULL;
  END IF;
END $$;

-- Indexes for listing/filtering
CREATE INDEX IF NOT EXISTS servicefile_service_created_idx
  ON "ServiceFile"("serviceId", "createdAt");

CREATE INDEX IF NOT EXISTS servicefile_service_kind_idx
  ON "ServiceFile"("serviceId", "kind");

CREATE INDEX IF NOT EXISTS servicefile_execution_report_idx
  ON "ServiceFile"("executionReportId");
