CREATE INDEX IF NOT EXISTS "inventory_movements_company_created_idx"
ON "inventory_movements" ("company_id", "created_at");

CREATE INDEX IF NOT EXISTS "inventory_movements_company_type_created_idx"
ON "inventory_movements" ("company_id", "type", "created_at");

CREATE INDEX IF NOT EXISTS "warehouse_transfers_company_created_idx"
ON "warehouse_transfers" ("company_id", "created_at");

CREATE INDEX IF NOT EXISTS "warehouse_transfers_company_status_created_idx"
ON "warehouse_transfers" ("company_id", "status", "created_at");
