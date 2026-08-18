CREATE TABLE IF NOT EXISTS "website_product_overrides" (
  "id" UUID NOT NULL DEFAULT gen_random_uuid(),
  "product_id" TEXT NOT NULL,
  "title" TEXT,
  "description" TEXT,
  "category" TEXT,
  "image_url" TEXT,
  "extra_image_urls" JSONB,
  "visible" BOOLEAN NOT NULL DEFAULT true,
  "featured" BOOLEAN NOT NULL DEFAULT false,
  "sort_order" INTEGER NOT NULL DEFAULT 0,
  "seo_title" TEXT,
  "seo_description" TEXT,
  "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updated_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "website_product_overrides_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX IF NOT EXISTS "website_product_overrides_product_id_key"
  ON "website_product_overrides" ("product_id");

CREATE INDEX IF NOT EXISTS "website_product_overrides_visible_idx"
  ON "website_product_overrides" ("visible");

CREATE INDEX IF NOT EXISTS "website_product_overrides_featured_idx"
  ON "website_product_overrides" ("featured");

CREATE INDEX IF NOT EXISTS "website_product_overrides_sort_order_idx"
  ON "website_product_overrides" ("sort_order");

CREATE OR REPLACE FUNCTION set_website_product_overrides_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW."updated_at" = CURRENT_TIMESTAMP;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS "website_product_overrides_updated_at_trigger"
  ON "website_product_overrides";

CREATE TRIGGER "website_product_overrides_updated_at_trigger"
BEFORE UPDATE ON "website_product_overrides"
FOR EACH ROW
EXECUTE FUNCTION set_website_product_overrides_updated_at();
