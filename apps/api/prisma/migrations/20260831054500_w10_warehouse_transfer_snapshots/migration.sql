ALTER TABLE "warehouse_transfers"
  ADD COLUMN "source_warehouse_name_snapshot" TEXT,
  ADD COLUMN "source_warehouse_code_snapshot" TEXT,
  ADD COLUMN "destination_warehouse_name_snapshot" TEXT,
  ADD COLUMN "destination_warehouse_code_snapshot" TEXT;

UPDATE "warehouse_transfers" wt
SET
  "source_warehouse_name_snapshot" = COALESCE(sw."name", 'Almacén origen'),
  "source_warehouse_code_snapshot" = COALESCE(sw."code", ''),
  "destination_warehouse_name_snapshot" = COALESCE(dw."name", 'Almacén destino'),
  "destination_warehouse_code_snapshot" = COALESCE(dw."code", '')
FROM "warehouses" sw, "warehouses" dw
WHERE sw."company_id" = wt."company_id"
  AND sw."id" = wt."source_warehouse_id"
  AND dw."company_id" = wt."company_id"
  AND dw."id" = wt."destination_warehouse_id";

ALTER TABLE "warehouse_transfers"
  ALTER COLUMN "source_warehouse_name_snapshot" SET NOT NULL,
  ALTER COLUMN "source_warehouse_code_snapshot" SET NOT NULL,
  ALTER COLUMN "destination_warehouse_name_snapshot" SET NOT NULL,
  ALTER COLUMN "destination_warehouse_code_snapshot" SET NOT NULL;

ALTER TABLE "warehouse_transfer_items"
  ADD COLUMN "product_name_snapshot" TEXT,
  ADD COLUMN "product_code_snapshot" TEXT;

UPDATE "warehouse_transfer_items" wti
SET
  "product_name_snapshot" = COALESCE(p."nombre", 'Producto transferido'),
  "product_code_snapshot" = p."codigo"
FROM "Product" p
WHERE p."company_id" = wti."company_id"
  AND p."id" = wti."product_id";

ALTER TABLE "warehouse_transfer_items"
  ALTER COLUMN "product_name_snapshot" SET NOT NULL;
