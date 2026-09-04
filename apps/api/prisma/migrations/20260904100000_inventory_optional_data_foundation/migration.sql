-- INVENTORY-OPTIONAL-02 data foundation only.
-- Additive fields preserve current behavior; optional-inventory behavior is not active yet.

CREATE TYPE "product_item_type" AS ENUM ('PRODUCT', 'SERVICE');

ALTER TABLE "companies"
ADD COLUMN "inventory_enabled" BOOLEAN NOT NULL DEFAULT true;

ALTER TABLE "Product"
ADD COLUMN "item_type" "product_item_type" NOT NULL DEFAULT 'PRODUCT',
ADD COLUMN "track_inventory" BOOLEAN NOT NULL DEFAULT true;

ALTER TABLE "SaleItem"
ADD COLUMN "inventory_tracked_snapshot" BOOLEAN;

UPDATE "SaleItem"
SET "inventory_tracked_snapshot" =
  CASE
    WHEN "productId" IS NOT NULL
     AND ("product_source" IS NULL OR "product_source" = 'LOCAL'::"product_source")
    THEN true
    ELSE false
  END
WHERE "inventory_tracked_snapshot" IS NULL;

ALTER TABLE "SaleItem"
ALTER COLUMN "inventory_tracked_snapshot" SET DEFAULT false,
ALTER COLUMN "inventory_tracked_snapshot" SET NOT NULL;
