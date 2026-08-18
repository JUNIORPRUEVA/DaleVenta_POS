ALTER TABLE "whatsapp_messages"
  ADD COLUMN IF NOT EXISTS "media_storage_key" TEXT,
  ADD COLUMN IF NOT EXISTS "media_file_size" INTEGER,
  ADD COLUMN IF NOT EXISTS "original_file_name" TEXT,
  ADD COLUMN IF NOT EXISTS "playable_storage_key" TEXT,
  ADD COLUMN IF NOT EXISTS "playable_mime_type" TEXT,
  ADD COLUMN IF NOT EXISTS "media_status" TEXT,
  ADD COLUMN IF NOT EXISTS "media_error" TEXT;

CREATE INDEX IF NOT EXISTS "whatsapp_messages_media_storage_key_idx"
  ON "whatsapp_messages"("media_storage_key");