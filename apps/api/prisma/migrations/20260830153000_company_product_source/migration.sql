DO $$ BEGIN
  CREATE TYPE "product_source" AS ENUM ('LOCAL', 'FULLPOS', 'FULLPOS_DIRECT');
EXCEPTION
  WHEN duplicate_object THEN null;
END $$;

ALTER TABLE "companies"
  ADD COLUMN IF NOT EXISTS "product_source" "product_source",
  ADD COLUMN IF NOT EXISTS "fullpos_company_id" TEXT;

CREATE INDEX IF NOT EXISTS "Company_product_source_idx"
  ON "companies"("product_source");
