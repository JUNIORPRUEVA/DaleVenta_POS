ALTER TABLE "Sale"
  ADD COLUMN IF NOT EXISTS "source_quotation_id" UUID,
  ADD COLUMN IF NOT EXISTS "refunded_sale_id" UUID,
  ADD COLUMN IF NOT EXISTS "commercial_profit" DECIMAL(12,2),
  ADD COLUMN IF NOT EXISTS "net_tax_profit" DECIMAL(12,2),
  ADD COLUMN IF NOT EXISTS "commercial_margin" DECIMAL(8,4),
  ADD COLUMN IF NOT EXISTS "net_tax_margin" DECIMAL(8,4);

ALTER TABLE "SaleItem"
  ADD COLUMN IF NOT EXISTS "refunded_sale_item_id" UUID,
  ADD COLUMN IF NOT EXISTS "commercial_profit" DECIMAL(12,2),
  ADD COLUMN IF NOT EXISTS "net_tax_profit" DECIMAL(12,2);

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'Sale_source_quotation_id_fkey'
  ) THEN
    ALTER TABLE "Sale"
      ADD CONSTRAINT "Sale_source_quotation_id_fkey"
      FOREIGN KEY ("source_quotation_id") REFERENCES "Cotizacion"("id")
      ON DELETE SET NULL ON UPDATE CASCADE;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'Sale_refunded_sale_id_fkey'
  ) THEN
    ALTER TABLE "Sale"
      ADD CONSTRAINT "Sale_refunded_sale_id_fkey"
      FOREIGN KEY ("refunded_sale_id") REFERENCES "Sale"("id")
      ON DELETE SET NULL ON UPDATE CASCADE;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'SaleItem_refunded_sale_item_id_fkey'
  ) THEN
    ALTER TABLE "SaleItem"
      ADD CONSTRAINT "SaleItem_refunded_sale_item_id_fkey"
      FOREIGN KEY ("refunded_sale_item_id") REFERENCES "SaleItem"("id")
      ON DELETE SET NULL ON UPDATE CASCADE;
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS "Sale_company_id_source_quotation_id_idx"
  ON "Sale"("company_id", "source_quotation_id");

CREATE INDEX IF NOT EXISTS "Sale_company_id_refunded_sale_id_idx"
  ON "Sale"("company_id", "refunded_sale_id");

CREATE INDEX IF NOT EXISTS "SaleItem_refunded_sale_item_id_idx"
  ON "SaleItem"("refunded_sale_item_id");
