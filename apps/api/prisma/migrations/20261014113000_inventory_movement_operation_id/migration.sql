ALTER TABLE "inventory_movements"
  ADD COLUMN IF NOT EXISTS "operation_id" TEXT;

CREATE UNIQUE INDEX IF NOT EXISTS "inventory_movements_company_operation_key"
  ON "inventory_movements"("company_id", "operation_id");
