ALTER TABLE "Product"
  ADD COLUMN IF NOT EXISTS "codigo" TEXT;

CREATE UNIQUE INDEX IF NOT EXISTS "Product_company_id_codigo_key"
  ON "Product"("company_id", "codigo")
  WHERE "codigo" IS NOT NULL;
