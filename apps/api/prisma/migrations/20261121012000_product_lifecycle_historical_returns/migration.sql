-- Preserve legitimate returns of historical sales after archiving. New sales
-- remain forbidden, and an annulled identity can never acquire a reference.
CREATE OR REPLACE FUNCTION fullpos_guard_product_reference() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE data jsonb:=to_jsonb(NEW); old_data jsonb; pid text; tenant uuid; p record;
  historical_refund boolean:=false;
BEGIN
  pid=data->>TG_ARGV[0];
  IF pid IS NULL OR pid !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' THEN RETURN NEW; END IF;
  IF TG_OP='UPDATE' AND TG_ARGV[1]<>'stock' THEN
    old_data=to_jsonb(OLD);
    IF old_data->>TG_ARGV[0]=pid AND old_data->>'company_id' IS NOT DISTINCT FROM data->>'company_id'
      AND (TG_NARGS<3 OR old_data->>TG_ARGV[2] IS NOT DISTINCT FROM data->>TG_ARGV[2]) THEN RETURN NEW; END IF;
  END IF;
  SELECT id,company_id,archived_at,annulled_at INTO p FROM "Product" WHERE id=pid::uuid FOR KEY SHARE;
  IF NOT FOUND THEN RETURN NEW; END IF;
  IF data ? 'company_id' THEN tenant=(data->>'company_id')::uuid;
  ELSIF TG_TABLE_NAME='SaleItem' THEN SELECT company_id INTO tenant FROM "Sale" WHERE id=(data->>'saleId')::uuid;
  ELSIF TG_TABLE_NAME='CotizacionItem' THEN SELECT company_id INTO tenant FROM "Cotizacion" WHERE id=(data->>'cotizacionId')::uuid;
  ELSIF TG_TABLE_NAME='purchase_order_items' THEN SELECT company_id INTO tenant FROM purchase_orders WHERE id=(data->>'purchase_order_id')::uuid;
  ELSE tenant=p.company_id;
  END IF;
  IF tenant IS DISTINCT FROM p.company_id THEN RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='PRODUCT_LIFECYCLE_TENANT_MISMATCH'; END IF;
  IF TG_TABLE_NAME='SaleItem' AND p.archived_at IS NOT NULL AND p.annulled_at IS NULL THEN
    SELECT EXISTS (
      SELECT 1 FROM "Sale" refund
      JOIN "SaleItem" original_item ON original_item.id=(data->>'refundedSaleItemId')::uuid
      JOIN "Sale" original ON original.id=original_item."saleId"
      WHERE refund.id=(data->>'saleId')::uuid AND refund.kind='refund'
        AND refund."refundedSaleId"=original.id AND refund.company_id=p.company_id
        AND original.company_id=p.company_id AND original.kind='invoice'
        AND original_item."productId"=pid::uuid
    ) INTO historical_refund;
  END IF;
  IF p.annulled_at IS NOT NULL OR (TG_ARGV[1]='commercial' AND p.archived_at IS NOT NULL AND NOT historical_refund) THEN
    RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='PRODUCT_LIFECYCLE_NOT_ACTIVE';
  END IF;
  RETURN NEW;
END $$;
