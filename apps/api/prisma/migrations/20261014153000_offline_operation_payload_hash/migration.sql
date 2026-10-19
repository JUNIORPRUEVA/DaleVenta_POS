ALTER TABLE "Product" ADD COLUMN "create_payload_hash" VARCHAR(64);
ALTER TABLE "inventory_movements" ADD COLUMN "operation_payload_hash" VARCHAR(64);
