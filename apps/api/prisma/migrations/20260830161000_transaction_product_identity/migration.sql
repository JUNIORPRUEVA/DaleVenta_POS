ALTER TABLE "SaleItem"
  ADD COLUMN IF NOT EXISTS "product_source" "product_source",
  ADD COLUMN IF NOT EXISTS "source_product_id" TEXT;

ALTER TABLE "CotizacionItem"
  ADD COLUMN IF NOT EXISTS "product_source" "product_source",
  ADD COLUMN IF NOT EXISTS "source_product_id" TEXT;

ALTER TABLE "purchase_order_items"
  ADD COLUMN IF NOT EXISTS "product_source" "product_source",
  ADD COLUMN IF NOT EXISTS "source_product_id" TEXT;

ALTER TABLE "purchase_receipt_items"
  ADD COLUMN IF NOT EXISTS "product_source" "product_source",
  ADD COLUMN IF NOT EXISTS "source_product_id" TEXT;

UPDATE "SaleItem"
SET "product_source" = 'LOCAL',
    "source_product_id" = "productId"::text
WHERE "productId" IS NOT NULL
  AND "product_source" IS NULL;

UPDATE "CotizacionItem"
SET "product_source" = 'LOCAL',
    "source_product_id" = "productId"::text
WHERE "productId" IS NOT NULL
  AND "product_source" IS NULL;

UPDATE "purchase_order_items"
SET "product_source" = 'LOCAL',
    "source_product_id" = "product_id"::text
WHERE "product_id" IS NOT NULL
  AND "product_source" IS NULL;

UPDATE "purchase_receipt_items" receipt_item
SET "product_source" = order_item."product_source",
    "source_product_id" = order_item."source_product_id"
FROM "purchase_order_items" order_item
WHERE receipt_item."purchase_order_item_id" = order_item."id"
  AND receipt_item."product_source" IS NULL
  AND order_item."product_source" IS NOT NULL;

CREATE INDEX IF NOT EXISTS "sale_items_product_source_source_product_id_idx"
  ON "SaleItem"("product_source", "source_product_id");

CREATE INDEX IF NOT EXISTS "cotizacion_items_product_source_source_product_id_idx"
  ON "CotizacionItem"("product_source", "source_product_id");

CREATE INDEX IF NOT EXISTS "purchase_order_items_product_source_source_product_id_idx"
  ON "purchase_order_items"("product_source", "source_product_id");

CREATE INDEX IF NOT EXISTS "purchase_receipt_items_product_source_source_product_id_idx"
  ON "purchase_receipt_items"("product_source", "source_product_id");
