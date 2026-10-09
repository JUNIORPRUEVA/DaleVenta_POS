ALTER TABLE "service_orders"
  ADD COLUMN IF NOT EXISTS "deleted_at" TIMESTAMP(3);

CREATE INDEX IF NOT EXISTS "service_orders_deleted_at_idx"
  ON "service_orders"("deleted_at");
