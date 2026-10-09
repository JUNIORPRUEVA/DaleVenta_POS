ALTER TYPE "app_release_status" ADD VALUE IF NOT EXISTS 'ARCHIVED';

ALTER TABLE "app_releases"
  ADD COLUMN IF NOT EXISTS "storage_key" TEXT,
  ADD COLUMN IF NOT EXISTS "storage_deleted_at" TIMESTAMP(3);

CREATE INDEX IF NOT EXISTS "app_releases_storage_key_idx"
  ON "app_releases"("storage_key");
