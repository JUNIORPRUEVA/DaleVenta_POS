CREATE TABLE "inventory_zero_config_states" (
  "company_id" UUID NOT NULL,
  "version" VARCHAR(64) NOT NULL DEFAULT 'W3_ZERO_CONFIG',
  "status" VARCHAR(32) NOT NULL,
  "warehouse_id" UUID,
  "terminal_id" UUID,
  "local_product_count" INTEGER NOT NULL DEFAULT 0,
  "warehouse_stock_count" INTEGER NOT NULL DEFAULT 0,
  "stock_hash" VARCHAR(64),
  "started_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "completed_at" TIMESTAMP(3),
  "updated_at" TIMESTAMP(3) NOT NULL,

  CONSTRAINT "inventory_zero_config_states_pkey" PRIMARY KEY ("company_id"),
  CONSTRAINT "inventory_zero_config_states_company_id_fkey"
    FOREIGN KEY ("company_id") REFERENCES "companies"("id") ON DELETE CASCADE ON UPDATE CASCADE
);

CREATE INDEX "inventory_zero_config_states_status_idx"
  ON "inventory_zero_config_states" ("status");
