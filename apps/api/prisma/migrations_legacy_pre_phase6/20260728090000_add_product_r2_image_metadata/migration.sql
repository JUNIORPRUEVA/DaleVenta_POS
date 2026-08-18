ALTER TABLE "Product"
  ADD COLUMN IF NOT EXISTS "image_storage_provider" TEXT,
  ADD COLUMN IF NOT EXISTS "image_key" TEXT,
  ADD COLUMN IF NOT EXISTS "image_mime_type" TEXT,
  ADD COLUMN IF NOT EXISTS "image_original_file_name" TEXT,
  ADD COLUMN IF NOT EXISTS "image_updated_at" TIMESTAMP(3);

CREATE INDEX IF NOT EXISTS "Product_company_id_image_key_idx"
  ON "Product"("company_id", "image_key");
