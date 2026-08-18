CREATE TYPE "WarrantyDurationUnit" AS ENUM ('DAYS', 'MONTHS', 'YEARS');

CREATE TABLE "warranty_product_configs" (
    "id" UUID NOT NULL,
    "owner_id" UUID NOT NULL,
    "category_id" UUID,
    "category_code" TEXT,
    "category_name" TEXT,
    "product_name" TEXT,
    "product_key" TEXT,
    "has_warranty" BOOLEAN NOT NULL DEFAULT true,
    "duration_value" INTEGER,
    "duration_unit" "WarrantyDurationUnit",
    "warranty_summary" TEXT,
    "coverage_summary" TEXT,
    "exclusions_summary" TEXT,
    "notes" TEXT,
    "is_active" BOOLEAN NOT NULL DEFAULT true,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "warranty_product_configs_pkey" PRIMARY KEY ("id")
);

CREATE INDEX "warranty_product_configs_owner_id_idx" ON "warranty_product_configs"("owner_id");
CREATE INDEX "warranty_product_configs_owner_id_is_active_idx" ON "warranty_product_configs"("owner_id", "is_active");
CREATE INDEX "warranty_product_configs_owner_id_category_id_idx" ON "warranty_product_configs"("owner_id", "category_id");
CREATE INDEX "warranty_product_configs_owner_id_category_code_idx" ON "warranty_product_configs"("owner_id", "category_code");
CREATE INDEX "warranty_product_configs_owner_id_product_key_idx" ON "warranty_product_configs"("owner_id", "product_key");

ALTER TABLE "warranty_product_configs"
    ADD CONSTRAINT "warranty_product_configs_owner_id_fkey"
    FOREIGN KEY ("owner_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

ALTER TABLE "warranty_product_configs"
    ADD CONSTRAINT "warranty_product_configs_category_id_fkey"
    FOREIGN KEY ("category_id") REFERENCES "service_categories"("id") ON DELETE SET NULL ON UPDATE CASCADE;