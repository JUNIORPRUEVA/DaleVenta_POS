CREATE TYPE "unit_of_measure_category" AS ENUM ('COUNT', 'LENGTH', 'WEIGHT', 'VOLUME', 'OTHER');

CREATE TABLE "unit_of_measures" (
  "id" VARCHAR(64) NOT NULL,
  "company_id" UUID,
  "code" VARCHAR(32) NOT NULL,
  "name" TEXT NOT NULL,
  "symbol" VARCHAR(16) NOT NULL,
  "category" "unit_of_measure_category" NOT NULL,
  "allow_decimals" BOOLEAN NOT NULL DEFAULT false,
  "precision" INTEGER NOT NULL DEFAULT 0,
  "active" BOOLEAN NOT NULL DEFAULT true,
  "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updated_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

  CONSTRAINT "unit_of_measures_pkey" PRIMARY KEY ("id"),
  CONSTRAINT "unit_of_measures_company_id_fkey"
    FOREIGN KEY ("company_id") REFERENCES "companies"("id") ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT "unit_of_measures_precision_check" CHECK ("precision" >= 0 AND "precision" <= 6),
  CONSTRAINT "unit_of_measures_global_id_check" CHECK (
    ("company_id" IS NULL AND "id" = "code")
    OR
    ("company_id" IS NOT NULL)
  )
);

CREATE UNIQUE INDEX "unit_of_measures_company_code_key"
  ON "unit_of_measures" ("company_id", "code");
CREATE UNIQUE INDEX "unit_of_measures_global_code_key"
  ON "unit_of_measures" ("code")
  WHERE "company_id" IS NULL;
CREATE INDEX "unit_of_measures_company_active_idx"
  ON "unit_of_measures" ("company_id", "active");
CREATE INDEX "unit_of_measures_category_idx"
  ON "unit_of_measures" ("category");

INSERT INTO "unit_of_measures"
  ("id", "company_id", "code", "name", "symbol", "category", "allow_decimals", "precision")
VALUES
  ('UNIT', NULL, 'UNIT', 'Unidad', 'u', 'COUNT', false, 0),
  ('YARD', NULL, 'YARD', 'Yarda', 'yd', 'LENGTH', true, 3),
  ('METER', NULL, 'METER', 'Metro', 'm', 'LENGTH', true, 3),
  ('FOOT', NULL, 'FOOT', 'Pie', 'ft', 'LENGTH', true, 3),
  ('INCH', NULL, 'INCH', 'Pulgada', 'in', 'LENGTH', true, 3),
  ('POUND', NULL, 'POUND', 'Libra', 'lb', 'WEIGHT', true, 3),
  ('KILOGRAM', NULL, 'KILOGRAM', 'Kilogramo', 'kg', 'WEIGHT', true, 3),
  ('GRAM', NULL, 'GRAM', 'Gramo', 'g', 'WEIGHT', true, 3),
  ('OUNCE', NULL, 'OUNCE', 'Onza', 'oz', 'WEIGHT', true, 3),
  ('LITER', NULL, 'LITER', 'Litro', 'L', 'VOLUME', true, 3),
  ('MILLILITER', NULL, 'MILLILITER', 'Mililitro', 'ml', 'VOLUME', true, 3),
  ('GALLON', NULL, 'GALLON', 'Galon', 'gal', 'VOLUME', true, 3);

ALTER TABLE "companies"
  ADD COLUMN "measurement_units_enabled" BOOLEAN NOT NULL DEFAULT false;

ALTER TABLE "Product"
  ADD COLUMN "unit_of_measure_id" VARCHAR(64) NOT NULL DEFAULT 'UNIT';

UPDATE "Product"
SET "unit_of_measure_id" = 'UNIT'
WHERE "unit_of_measure_id" IS NULL;

ALTER TABLE "Product"
  ALTER COLUMN "stock" TYPE NUMERIC(18,6),
  ADD CONSTRAINT "Product_unit_of_measure_id_fkey"
    FOREIGN KEY ("unit_of_measure_id") REFERENCES "unit_of_measures"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

CREATE INDEX "Product_unit_of_measure_id_idx" ON "Product" ("unit_of_measure_id");

ALTER TABLE "service_execution_changes"
  ALTER COLUMN "quantity" TYPE NUMERIC(18,6);

ALTER TABLE "purchase_order_items"
  ALTER COLUMN "quantity" TYPE NUMERIC(18,6),
  ALTER COLUMN "received_quantity" TYPE NUMERIC(18,6),
  ALTER COLUMN "pending_quantity" TYPE NUMERIC(18,6),
  ADD COLUMN "unit_code_snapshot" VARCHAR(32) NOT NULL DEFAULT 'UNIT',
  ADD COLUMN "unit_name_snapshot" TEXT NOT NULL DEFAULT 'Unidad',
  ADD COLUMN "unit_symbol_snapshot" VARCHAR(16) NOT NULL DEFAULT 'u',
  ADD COLUMN "unit_precision_snapshot" INTEGER NOT NULL DEFAULT 0;

ALTER TABLE "purchase_receipt_items"
  ALTER COLUMN "quantity_received" TYPE NUMERIC(18,6),
  ADD COLUMN "unit_code_snapshot" VARCHAR(32) NOT NULL DEFAULT 'UNIT',
  ADD COLUMN "unit_name_snapshot" TEXT NOT NULL DEFAULT 'Unidad',
  ADD COLUMN "unit_symbol_snapshot" VARCHAR(16) NOT NULL DEFAULT 'u',
  ADD COLUMN "unit_precision_snapshot" INTEGER NOT NULL DEFAULT 0;

ALTER TABLE "SaleItem"
  ALTER COLUMN "qty" TYPE NUMERIC(18,6),
  ADD COLUMN "unit_code_snapshot" VARCHAR(32) NOT NULL DEFAULT 'UNIT',
  ADD COLUMN "unit_name_snapshot" TEXT NOT NULL DEFAULT 'Unidad',
  ADD COLUMN "unit_symbol_snapshot" VARCHAR(16) NOT NULL DEFAULT 'u',
  ADD COLUMN "unit_precision_snapshot" INTEGER NOT NULL DEFAULT 0;

ALTER TABLE "CotizacionItem"
  ALTER COLUMN "qty" TYPE NUMERIC(18,6),
  ADD COLUMN "unit_code_snapshot" VARCHAR(32) NOT NULL DEFAULT 'UNIT',
  ADD COLUMN "unit_name_snapshot" TEXT NOT NULL DEFAULT 'Unidad',
  ADD COLUMN "unit_symbol_snapshot" VARCHAR(16) NOT NULL DEFAULT 'u',
  ADD COLUMN "unit_precision_snapshot" INTEGER NOT NULL DEFAULT 0;
