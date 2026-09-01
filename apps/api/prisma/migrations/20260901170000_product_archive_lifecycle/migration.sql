ALTER TABLE "Product"
  ADD COLUMN IF NOT EXISTS "archived_at" TIMESTAMP(3);

CREATE INDEX IF NOT EXISTS "products_company_archived_idx"
  ON "Product"("company_id", "archived_at");
