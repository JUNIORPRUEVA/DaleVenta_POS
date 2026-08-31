-- W5: warehouse-aware sales snapshots and safe sale cancellation state.
-- This migration is schema-only. Historical sale items intentionally keep
-- nullable warehouse snapshots until a legacy cancellation fallback resolves them.

ALTER TABLE "Sale"
  ADD COLUMN "cancelled_at" TIMESTAMP(3),
  ADD COLUMN "cancelled_by_id" UUID,
  ADD COLUMN "cancellation_reason" TEXT,
  ADD COLUMN "inventory_restored_at" TIMESTAMP(3);

ALTER TABLE "SaleItem"
  ADD COLUMN "warehouse_id" UUID,
  ADD COLUMN "warehouse_name_snapshot" TEXT,
  ADD COLUMN "warehouse_code_snapshot" TEXT;

ALTER TABLE "Sale"
  ADD CONSTRAINT "Sale_cancelled_by_id_fkey"
  FOREIGN KEY ("cancelled_by_id") REFERENCES "users"("id")
  ON DELETE SET NULL ON UPDATE CASCADE;

ALTER TABLE "SaleItem"
  ADD CONSTRAINT "SaleItem_warehouse_id_fkey"
  FOREIGN KEY ("warehouse_id") REFERENCES "warehouses"("id")
  ON DELETE SET NULL ON UPDATE CASCADE;

CREATE INDEX "Sale_company_id_cancelled_at_idx"
  ON "Sale"("company_id", "cancelled_at");

CREATE INDEX "Sale_company_id_inventory_restored_at_idx"
  ON "Sale"("company_id", "inventory_restored_at");

CREATE INDEX "SaleItem_warehouse_id_idx"
  ON "SaleItem"("warehouse_id");
