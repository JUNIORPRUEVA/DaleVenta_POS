CREATE TYPE "inventory_movement_type" AS ENUM (
  'INITIAL_STOCK',
  'SALE',
  'SALE_CANCELLATION',
  'PURCHASE_RECEIPT',
  'RETURN',
  'ADJUSTMENT_IN',
  'ADJUSTMENT_OUT',
  'TRANSFER_OUT',
  'TRANSFER_IN'
);

CREATE TYPE "warehouse_transfer_status" AS ENUM (
  'DRAFT',
  'COMPLETED',
  'CANCELLED'
);

ALTER TABLE "Product"
  ADD CONSTRAINT "products_company_id_id_key" UNIQUE ("company_id", "id");

CREATE TABLE "warehouses" (
  "id" UUID NOT NULL,
  "company_id" UUID NOT NULL,
  "name" TEXT NOT NULL,
  "code" TEXT NOT NULL,
  "is_default" BOOLEAN NOT NULL DEFAULT false,
  "is_active" BOOLEAN NOT NULL DEFAULT true,
  "deactivated_at" TIMESTAMP(3),
  "deactivated_by_id" UUID,
  "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updated_at" TIMESTAMP(3) NOT NULL,

  CONSTRAINT "warehouses_pkey" PRIMARY KEY ("id"),
  CONSTRAINT "warehouses_company_id_fkey"
    FOREIGN KEY ("company_id") REFERENCES "companies"("id") ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT "warehouses_deactivated_by_id_fkey"
    FOREIGN KEY ("deactivated_by_id") REFERENCES "users"("id") ON DELETE SET NULL ON UPDATE CASCADE
);

CREATE UNIQUE INDEX "warehouses_company_id_id_key"
  ON "warehouses" ("company_id", "id");
CREATE UNIQUE INDEX "warehouses_company_code_key"
  ON "warehouses" ("company_id", "code");
CREATE UNIQUE INDEX "warehouses_one_default_per_company_idx"
  ON "warehouses" ("company_id")
  WHERE "is_default" = true;
CREATE INDEX "warehouses_company_active_idx"
  ON "warehouses" ("company_id", "is_active");

CREATE TABLE "warehouse_stocks" (
  "id" UUID NOT NULL,
  "company_id" UUID NOT NULL,
  "warehouse_id" UUID NOT NULL,
  "product_id" UUID NOT NULL,
  "quantity" NUMERIC(18,6) NOT NULL DEFAULT 0,
  "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updated_at" TIMESTAMP(3) NOT NULL,

  CONSTRAINT "warehouse_stocks_pkey" PRIMARY KEY ("id"),
  CONSTRAINT "warehouse_stocks_company_id_fkey"
    FOREIGN KEY ("company_id") REFERENCES "companies"("id") ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT "warehouse_stocks_company_id_warehouse_id_fkey"
    FOREIGN KEY ("company_id", "warehouse_id") REFERENCES "warehouses"("company_id", "id") ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT "warehouse_stocks_company_id_product_id_fkey"
    FOREIGN KEY ("company_id", "product_id") REFERENCES "Product"("company_id", "id") ON DELETE CASCADE ON UPDATE CASCADE
);

CREATE TABLE "terminals" (
  "id" UUID NOT NULL,
  "company_id" UUID NOT NULL,
  "name" TEXT NOT NULL,
  "code" TEXT NOT NULL,
  "default_warehouse_id" UUID NOT NULL,
  "is_default" BOOLEAN NOT NULL DEFAULT false,
  "is_active" BOOLEAN NOT NULL DEFAULT true,
  "device_fingerprint" TEXT,
  "deactivated_at" TIMESTAMP(3),
  "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updated_at" TIMESTAMP(3) NOT NULL,

  CONSTRAINT "terminals_pkey" PRIMARY KEY ("id"),
  CONSTRAINT "terminals_company_id_fkey"
    FOREIGN KEY ("company_id") REFERENCES "companies"("id") ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT "terminals_company_id_default_warehouse_id_fkey"
    FOREIGN KEY ("company_id", "default_warehouse_id") REFERENCES "warehouses"("company_id", "id") ON DELETE RESTRICT ON UPDATE CASCADE
);

CREATE TABLE "inventory_movements" (
  "id" UUID NOT NULL,
  "company_id" UUID NOT NULL,
  "product_id" UUID NOT NULL,
  "warehouse_id" UUID NOT NULL,
  "type" "inventory_movement_type" NOT NULL,
  "quantity_delta" NUMERIC(18,6) NOT NULL,
  "previous_quantity" NUMERIC(18,6) NOT NULL,
  "resulting_quantity" NUMERIC(18,6) NOT NULL,
  "unit_code_snapshot" VARCHAR(32) NOT NULL,
  "unit_name_snapshot" TEXT NOT NULL,
  "unit_symbol_snapshot" VARCHAR(16) NOT NULL,
  "unit_precision_snapshot" INTEGER NOT NULL,
  "source_warehouse_id" UUID,
  "destination_warehouse_id" UUID,
  "source_type" VARCHAR(64),
  "source_id" UUID,
  "source_item_id" UUID,
  "reason" TEXT,
  "created_by_user_id" UUID,
  "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

  CONSTRAINT "inventory_movements_pkey" PRIMARY KEY ("id"),
  CONSTRAINT "inventory_movements_company_id_fkey"
    FOREIGN KEY ("company_id") REFERENCES "companies"("id") ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT "inventory_movements_company_id_product_id_fkey"
    FOREIGN KEY ("company_id", "product_id") REFERENCES "Product"("company_id", "id") ON DELETE RESTRICT ON UPDATE CASCADE,
  CONSTRAINT "inventory_movements_company_id_warehouse_id_fkey"
    FOREIGN KEY ("company_id", "warehouse_id") REFERENCES "warehouses"("company_id", "id") ON DELETE RESTRICT ON UPDATE CASCADE,
  CONSTRAINT "inventory_movements_company_id_source_warehouse_id_fkey"
    FOREIGN KEY ("company_id", "source_warehouse_id") REFERENCES "warehouses"("company_id", "id") ON DELETE RESTRICT ON UPDATE CASCADE,
  CONSTRAINT "inventory_movements_company_id_destination_warehouse_id_fkey"
    FOREIGN KEY ("company_id", "destination_warehouse_id") REFERENCES "warehouses"("company_id", "id") ON DELETE RESTRICT ON UPDATE CASCADE,
  CONSTRAINT "inventory_movements_created_by_user_id_fkey"
    FOREIGN KEY ("created_by_user_id") REFERENCES "users"("id") ON DELETE SET NULL ON UPDATE CASCADE
);

CREATE TABLE "warehouse_transfers" (
  "id" UUID NOT NULL,
  "company_id" UUID NOT NULL,
  "source_warehouse_id" UUID NOT NULL,
  "destination_warehouse_id" UUID NOT NULL,
  "status" "warehouse_transfer_status" NOT NULL DEFAULT 'DRAFT',
  "operation_id" TEXT,
  "client_request_id" TEXT,
  "created_by_user_id" UUID,
  "completed_at" TIMESTAMP(3),
  "notes" TEXT,
  "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updated_at" TIMESTAMP(3) NOT NULL,

  CONSTRAINT "warehouse_transfers_pkey" PRIMARY KEY ("id"),
  CONSTRAINT "warehouse_transfers_company_id_fkey"
    FOREIGN KEY ("company_id") REFERENCES "companies"("id") ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT "warehouse_transfers_company_id_source_warehouse_id_fkey"
    FOREIGN KEY ("company_id", "source_warehouse_id") REFERENCES "warehouses"("company_id", "id") ON DELETE RESTRICT ON UPDATE CASCADE,
  CONSTRAINT "warehouse_transfers_company_id_destination_warehouse_id_fkey"
    FOREIGN KEY ("company_id", "destination_warehouse_id") REFERENCES "warehouses"("company_id", "id") ON DELETE RESTRICT ON UPDATE CASCADE,
  CONSTRAINT "warehouse_transfers_created_by_user_id_fkey"
    FOREIGN KEY ("created_by_user_id") REFERENCES "users"("id") ON DELETE SET NULL ON UPDATE CASCADE,
  CONSTRAINT "warehouse_transfers_source_destination_check"
    CHECK ("source_warehouse_id" <> "destination_warehouse_id")
);

CREATE UNIQUE INDEX "warehouse_transfers_company_id_id_key"
  ON "warehouse_transfers" ("company_id", "id");

CREATE TABLE "warehouse_transfer_items" (
  "id" UUID NOT NULL,
  "company_id" UUID NOT NULL,
  "transfer_id" UUID NOT NULL,
  "product_id" UUID NOT NULL,
  "quantity" NUMERIC(18,6) NOT NULL,
  "unit_code_snapshot" VARCHAR(32) NOT NULL,
  "unit_name_snapshot" TEXT NOT NULL,
  "unit_symbol_snapshot" VARCHAR(16) NOT NULL,
  "unit_precision_snapshot" INTEGER NOT NULL,
  "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

  CONSTRAINT "warehouse_transfer_items_pkey" PRIMARY KEY ("id"),
  CONSTRAINT "warehouse_transfer_items_company_id_fkey"
    FOREIGN KEY ("company_id") REFERENCES "companies"("id") ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT "warehouse_transfer_items_company_id_transfer_id_fkey"
    FOREIGN KEY ("company_id", "transfer_id") REFERENCES "warehouse_transfers"("company_id", "id") ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT "warehouse_transfer_items_company_id_product_id_fkey"
    FOREIGN KEY ("company_id", "product_id") REFERENCES "Product"("company_id", "id") ON DELETE RESTRICT ON UPDATE CASCADE
);

CREATE UNIQUE INDEX "warehouse_stocks_company_warehouse_product_key"
  ON "warehouse_stocks" ("company_id", "warehouse_id", "product_id");
CREATE INDEX "warehouse_stocks_company_product_idx"
  ON "warehouse_stocks" ("company_id", "product_id");
CREATE INDEX "warehouse_stocks_company_warehouse_idx"
  ON "warehouse_stocks" ("company_id", "warehouse_id");

CREATE UNIQUE INDEX "terminals_company_code_key"
  ON "terminals" ("company_id", "code");
CREATE UNIQUE INDEX "terminals_one_default_per_company_idx"
  ON "terminals" ("company_id")
  WHERE "is_default" = true;
CREATE INDEX "terminals_company_active_idx"
  ON "terminals" ("company_id", "is_active");

CREATE INDEX "inventory_movements_company_product_created_idx"
  ON "inventory_movements" ("company_id", "product_id", "created_at");
CREATE INDEX "inventory_movements_company_warehouse_created_idx"
  ON "inventory_movements" ("company_id", "warehouse_id", "created_at");
CREATE INDEX "inventory_movements_company_source_idx"
  ON "inventory_movements" ("company_id", "source_type", "source_id");

CREATE UNIQUE INDEX "warehouse_transfers_company_operation_key"
  ON "warehouse_transfers" ("company_id", "operation_id");
CREATE UNIQUE INDEX "warehouse_transfers_company_client_request_key"
  ON "warehouse_transfers" ("company_id", "client_request_id");
CREATE INDEX "warehouse_transfers_company_status_idx"
  ON "warehouse_transfers" ("company_id", "status");
CREATE INDEX "warehouse_transfers_company_source_idx"
  ON "warehouse_transfers" ("company_id", "source_warehouse_id");
CREATE INDEX "warehouse_transfers_company_destination_idx"
  ON "warehouse_transfers" ("company_id", "destination_warehouse_id");

CREATE UNIQUE INDEX "warehouse_transfer_items_company_transfer_product_key"
  ON "warehouse_transfer_items" ("company_id", "transfer_id", "product_id");
CREATE INDEX "warehouse_transfer_items_company_product_idx"
  ON "warehouse_transfer_items" ("company_id", "product_id");
