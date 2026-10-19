-- CreateEnum
CREATE TYPE "price_list_rule_mode" AS ENUM ('FIXED_PRICE', 'PERCENT_DISCOUNT');

-- Company-level feature flag. Default false preserves legacy pricing.
ALTER TABLE "companies"
  ADD COLUMN "wholesale_price_lists_enabled" BOOLEAN NOT NULL DEFAULT false;

-- Price-list assignment to clients.
ALTER TABLE "Client"
  ADD COLUMN "default_price_list_id" UUID;

-- Document-level snapshots.
ALTER TABLE "Sale"
  ADD COLUMN "price_list_id" UUID,
  ADD COLUMN "price_list_manual_override" BOOLEAN NOT NULL DEFAULT false,
  ADD COLUMN "price_list_name_snapshot" TEXT;

ALTER TABLE "Cotizacion"
  ADD COLUMN "price_list_id" UUID,
  ADD COLUMN "price_list_manual_override" BOOLEAN NOT NULL DEFAULT false,
  ADD COLUMN "price_list_name_snapshot" TEXT;

-- Line-level snapshots.
ALTER TABLE "SaleItem"
  ADD COLUMN "original_unit_price_snapshot" DECIMAL(12,2),
  ADD COLUMN "applied_price_list_id" UUID,
  ADD COLUMN "applied_price_list_name_snapshot" TEXT,
  ADD COLUMN "applied_pricing_rule_id" UUID,
  ADD COLUMN "applied_pricing_rule_mode" "price_list_rule_mode",
  ADD COLUMN "applied_pricing_snapshot" JSONB;

ALTER TABLE "CotizacionItem"
  ADD COLUMN "applied_price_list_id" UUID,
  ADD COLUMN "applied_price_list_name_snapshot" TEXT,
  ADD COLUMN "applied_pricing_rule_id" UUID,
  ADD COLUMN "applied_pricing_rule_mode" "price_list_rule_mode",
  ADD COLUMN "applied_pricing_snapshot" JSONB;

-- Master data.
CREATE TABLE "price_lists" (
  "id" UUID NOT NULL DEFAULT gen_random_uuid(),
  "company_id" UUID NOT NULL,
  "name" TEXT NOT NULL,
  "description" TEXT,
  "active" BOOLEAN NOT NULL DEFAULT true,
  "priority" INTEGER NOT NULL DEFAULT 0,
  "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updated_at" TIMESTAMP(3) NOT NULL,
  CONSTRAINT "price_lists_pkey" PRIMARY KEY ("id")
);

CREATE TABLE "price_list_product_rules" (
  "id" UUID NOT NULL DEFAULT gen_random_uuid(),
  "company_id" UUID NOT NULL,
  "price_list_id" UUID NOT NULL,
  "product_id" UUID NOT NULL,
  "mode" "price_list_rule_mode" NOT NULL,
  "fixed_price" DECIMAL(12,2),
  "discount_percent" DECIMAL(5,2),
  "min_quantity" DECIMAL(18,6) NOT NULL DEFAULT 1,
  "active" BOOLEAN NOT NULL DEFAULT true,
  "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updated_at" TIMESTAMP(3) NOT NULL,
  CONSTRAINT "price_list_product_rules_pkey" PRIMARY KEY ("id")
);

CREATE TABLE "price_list_quantity_tiers" (
  "id" UUID NOT NULL DEFAULT gen_random_uuid(),
  "company_id" UUID NOT NULL,
  "rule_id" UUID NOT NULL,
  "min_quantity" DECIMAL(18,6) NOT NULL,
  "mode" "price_list_rule_mode",
  "fixed_price" DECIMAL(12,2),
  "discount_percent" DECIMAL(5,2),
  "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updated_at" TIMESTAMP(3) NOT NULL,
  CONSTRAINT "price_list_quantity_tiers_pkey" PRIMARY KEY ("id")
);

CREATE INDEX "price_lists_company_id_active_priority_idx"
  ON "price_lists"("company_id", "active", "priority");
CREATE UNIQUE INDEX "price_lists_company_id_name_key"
  ON "price_lists"("company_id", "name");

CREATE INDEX "price_list_product_rules_company_id_product_id_active_idx"
  ON "price_list_product_rules"("company_id", "product_id", "active");
CREATE INDEX "price_list_product_rules_company_id_price_list_id_active_idx"
  ON "price_list_product_rules"("company_id", "price_list_id", "active");
CREATE UNIQUE INDEX "price_list_product_rules_price_list_id_product_id_min_quant_key"
  ON "price_list_product_rules"("price_list_id", "product_id", "min_quantity");

CREATE INDEX "price_list_quantity_tiers_company_id_rule_id_idx"
  ON "price_list_quantity_tiers"("company_id", "rule_id");
CREATE UNIQUE INDEX "price_list_quantity_tiers_rule_id_min_quantity_key"
  ON "price_list_quantity_tiers"("rule_id", "min_quantity");

CREATE INDEX "Client_default_price_list_id_idx"
  ON "Client"("default_price_list_id");
CREATE INDEX "Sale_company_id_price_list_id_idx"
  ON "Sale"("company_id", "price_list_id");
CREATE INDEX "SaleItem_applied_price_list_id_idx"
  ON "SaleItem"("applied_price_list_id");
CREATE INDEX "SaleItem_applied_pricing_rule_id_idx"
  ON "SaleItem"("applied_pricing_rule_id");
CREATE INDEX "Cotizacion_company_id_price_list_id_idx"
  ON "Cotizacion"("company_id", "price_list_id");
CREATE INDEX "CotizacionItem_applied_price_list_id_idx"
  ON "CotizacionItem"("applied_price_list_id");
CREATE INDEX "CotizacionItem_applied_pricing_rule_id_idx"
  ON "CotizacionItem"("applied_pricing_rule_id");

ALTER TABLE "Client"
  ADD CONSTRAINT "Client_default_price_list_id_fkey"
  FOREIGN KEY ("default_price_list_id") REFERENCES "price_lists"("id")
  ON DELETE SET NULL ON UPDATE CASCADE;

ALTER TABLE "price_lists"
  ADD CONSTRAINT "price_lists_company_id_fkey"
  FOREIGN KEY ("company_id") REFERENCES "companies"("id")
  ON DELETE CASCADE ON UPDATE CASCADE;

ALTER TABLE "price_list_product_rules"
  ADD CONSTRAINT "price_list_product_rules_price_list_id_fkey"
  FOREIGN KEY ("price_list_id") REFERENCES "price_lists"("id")
  ON DELETE CASCADE ON UPDATE CASCADE;

ALTER TABLE "price_list_product_rules"
  ADD CONSTRAINT "price_list_product_rules_product_id_fkey"
  FOREIGN KEY ("product_id") REFERENCES "Product"("id")
  ON DELETE CASCADE ON UPDATE CASCADE;

ALTER TABLE "price_list_quantity_tiers"
  ADD CONSTRAINT "price_list_quantity_tiers_rule_id_fkey"
  FOREIGN KEY ("rule_id") REFERENCES "price_list_product_rules"("id")
  ON DELETE CASCADE ON UPDATE CASCADE;

ALTER TABLE "Sale"
  ADD CONSTRAINT "Sale_price_list_id_fkey"
  FOREIGN KEY ("price_list_id") REFERENCES "price_lists"("id")
  ON DELETE SET NULL ON UPDATE CASCADE;

ALTER TABLE "SaleItem"
  ADD CONSTRAINT "SaleItem_applied_price_list_id_fkey"
  FOREIGN KEY ("applied_price_list_id") REFERENCES "price_lists"("id")
  ON DELETE SET NULL ON UPDATE CASCADE;

ALTER TABLE "SaleItem"
  ADD CONSTRAINT "SaleItem_applied_pricing_rule_id_fkey"
  FOREIGN KEY ("applied_pricing_rule_id") REFERENCES "price_list_product_rules"("id")
  ON DELETE SET NULL ON UPDATE CASCADE;

ALTER TABLE "Cotizacion"
  ADD CONSTRAINT "Cotizacion_price_list_id_fkey"
  FOREIGN KEY ("price_list_id") REFERENCES "price_lists"("id")
  ON DELETE SET NULL ON UPDATE CASCADE;

ALTER TABLE "CotizacionItem"
  ADD CONSTRAINT "CotizacionItem_applied_price_list_id_fkey"
  FOREIGN KEY ("applied_price_list_id") REFERENCES "price_lists"("id")
  ON DELETE SET NULL ON UPDATE CASCADE;

ALTER TABLE "CotizacionItem"
  ADD CONSTRAINT "CotizacionItem_applied_pricing_rule_id_fkey"
  FOREIGN KEY ("applied_pricing_rule_id") REFERENCES "price_list_product_rules"("id")
  ON DELETE SET NULL ON UPDATE CASCADE;
