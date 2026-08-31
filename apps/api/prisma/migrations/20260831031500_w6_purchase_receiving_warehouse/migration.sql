-- W6: purchase receiving warehouse snapshots and receipt idempotency.
-- Schema-only. Historical receipt items intentionally keep nullable warehouse
-- snapshots and no client_request_id.

ALTER TABLE "purchase_receipts"
  ADD COLUMN "client_request_id" TEXT;

ALTER TABLE "purchase_receipt_items"
  ADD COLUMN "destination_warehouse_id" UUID,
  ADD COLUMN "warehouse_name_snapshot" TEXT,
  ADD COLUMN "warehouse_code_snapshot" TEXT;

ALTER TABLE "purchase_receipt_items"
  ADD CONSTRAINT "purchase_receipt_items_destination_warehouse_id_fkey"
  FOREIGN KEY ("destination_warehouse_id") REFERENCES "warehouses"("id")
  ON DELETE SET NULL ON UPDATE CASCADE;

CREATE UNIQUE INDEX "purchase_receipts_order_client_request_key"
  ON "purchase_receipts"("purchase_order_id", "client_request_id");

CREATE INDEX "purchase_receipt_items_destination_warehouse_id_idx"
  ON "purchase_receipt_items"("destination_warehouse_id");
