-- Additive only. No existing product, stock, document, code or movement is changed.
ALTER TABLE "Product"
  ADD COLUMN "annulled_at" TIMESTAMP(3),
  ADD COLUMN "annulled_by_user_id" UUID,
  ADD COLUMN "annulment_reason" VARCHAR(500),
  ADD COLUMN "annulment_operation_id" VARCHAR(128),
  ADD COLUMN "annulled_initial_movement_id" UUID,
  ADD COLUMN "lifecycle_version" INTEGER NOT NULL DEFAULT 0;
CREATE UNIQUE INDEX "products_company_annulment_operation_key" ON "Product" (company_id,annulment_operation_id);
CREATE INDEX "products_company_annulled_idx" ON "Product" (company_id,annulled_at);
ALTER TABLE "Product" ADD CONSTRAINT "Product_annulled_initial_movement_id_fkey"
  FOREIGN KEY (annulled_initial_movement_id) REFERENCES inventory_movements(id) ON DELETE RESTRICT ON UPDATE CASCADE;
ALTER TABLE "Product" ADD CONSTRAINT "product_annulment_complete" CHECK (
  annulled_at IS NULL OR (archived_at IS NOT NULL AND stock=0 AND annulled_by_user_id IS NOT NULL
    AND length(btrim(annulment_reason))>=10 AND annulment_operation_id IS NOT NULL
    AND annulled_initial_movement_id IS NOT NULL));

-- Old clients/backends cannot reactivate or restock an annulled identity.
CREATE FUNCTION fullpos_product_lifecycle_version() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF OLD.annulled_at IS NOT NULL AND (
    NEW.annulled_at IS DISTINCT FROM OLD.annulled_at OR NEW.archived_at IS NULL OR NEW.stock<>0
    OR NEW.annulment_operation_id IS DISTINCT FROM OLD.annulment_operation_id
    OR NEW.annulled_initial_movement_id IS DISTINCT FROM OLD.annulled_initial_movement_id
    OR NEW.annulled_by_user_id IS DISTINCT FROM OLD.annulled_by_user_id
    OR NEW.annulment_reason IS DISTINCT FROM OLD.annulment_reason
  ) THEN RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='PRODUCT_LIFECYCLE_ANNULLED'; END IF;
  NEW.lifecycle_version=OLD.lifecycle_version+1;
  RETURN NEW;
END $$;
CREATE TRIGGER product_lifecycle_version BEFORE UPDATE ON "Product"
  FOR EACH ROW EXECUTE FUNCTION fullpos_product_lifecycle_version();

-- A new reference takes KEY SHARE before checking the current lifecycle state.
-- Lifecycle transitions take FOR UPDATE: either the reference commits first
-- and is counted, or it waits and rejects the inactive identity afterwards.
CREATE FUNCTION fullpos_guard_product_reference() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE data jsonb:=to_jsonb(NEW); old_data jsonb; pid text; tenant uuid; p record;
BEGIN
  pid=data->>TG_ARGV[0];
  IF pid IS NULL OR pid !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' THEN RETURN NEW; END IF;
  IF TG_OP='UPDATE' AND TG_ARGV[1]<>'stock' THEN
    old_data=to_jsonb(OLD);
    IF old_data->>TG_ARGV[0]=pid AND old_data->>'company_id' IS NOT DISTINCT FROM data->>'company_id'
      AND (TG_NARGS<3 OR old_data->>TG_ARGV[2] IS NOT DISTINCT FROM data->>TG_ARGV[2]) THEN RETURN NEW; END IF;
  END IF;
  SELECT id,company_id,archived_at,annulled_at INTO p FROM "Product" WHERE id=pid::uuid FOR KEY SHARE;
  IF NOT FOUND THEN RETURN NEW; END IF; -- Existing FK or service validates missing products.
  IF data ? 'company_id' THEN tenant=(data->>'company_id')::uuid;
  ELSIF TG_TABLE_NAME='SaleItem' THEN SELECT company_id INTO tenant FROM "Sale" WHERE id=(data->>'saleId')::uuid;
  ELSIF TG_TABLE_NAME='CotizacionItem' THEN SELECT company_id INTO tenant FROM "Cotizacion" WHERE id=(data->>'cotizacionId')::uuid;
  ELSIF TG_TABLE_NAME='purchase_order_items' THEN SELECT company_id INTO tenant FROM purchase_orders WHERE id=(data->>'purchase_order_id')::uuid;
  ELSE tenant=p.company_id;
  END IF;
  IF tenant IS DISTINCT FROM p.company_id THEN RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='PRODUCT_LIFECYCLE_TENANT_MISMATCH'; END IF;
  IF p.annulled_at IS NOT NULL OR (TG_ARGV[1]='commercial' AND p.archived_at IS NOT NULL) THEN
    RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='PRODUCT_LIFECYCLE_NOT_ACTIVE';
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER product_lifecycle_sale BEFORE INSERT OR UPDATE OF "productId","saleId" ON "SaleItem"
 FOR EACH ROW EXECUTE FUNCTION fullpos_guard_product_reference('productId','commercial','saleId');
CREATE TRIGGER product_lifecycle_quote BEFORE INSERT OR UPDATE OF "productId","cotizacionId" ON "CotizacionItem"
 FOR EACH ROW EXECUTE FUNCTION fullpos_guard_product_reference('productId','commercial','cotizacionId');
CREATE TRIGGER product_lifecycle_purchase BEFORE INSERT OR UPDATE OF product_id,purchase_order_id ON purchase_order_items
 FOR EACH ROW EXECUTE FUNCTION fullpos_guard_product_reference('product_id','commercial','purchase_order_id');
CREATE TRIGGER product_lifecycle_transfer BEFORE INSERT OR UPDATE OF product_id ON warehouse_transfer_items
 FOR EACH ROW EXECUTE FUNCTION fullpos_guard_product_reference('product_id','commercial');
CREATE TRIGGER product_lifecycle_price_rule BEFORE INSERT OR UPDATE OF product_id,company_id ON price_list_product_rules
 FOR EACH ROW EXECUTE FUNCTION fullpos_guard_product_reference('product_id','commercial');
CREATE TRIGGER product_lifecycle_movement BEFORE INSERT ON inventory_movements
 FOR EACH ROW EXECUTE FUNCTION fullpos_guard_product_reference('product_id','stock');
CREATE TRIGGER product_lifecycle_stock BEFORE INSERT OR UPDATE OF quantity ON warehouse_stocks
 FOR EACH ROW EXECUTE FUNCTION fullpos_guard_product_reference('product_id','stock');
