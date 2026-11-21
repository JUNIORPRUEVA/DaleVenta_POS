-- Use physical PostgreSQL names for the two Prisma @map refund fields.
-- Keep the already rehearsed migration immutable; no business row is changed.
DO $$
DECLARE definition text;
BEGIN
  SELECT pg_get_functiondef('fullpos_guard_product_reference()'::regprocedure) INTO definition;
  IF position('refundedSaleItemId' IN definition)=0 OR position('refund."refundedSaleId"' IN definition)=0 THEN
    RAISE EXCEPTION 'Unexpected product lifecycle guard definition';
  END IF;
  definition=replace(definition, 'data->>''refundedSaleItemId''', 'data->>''refunded_sale_item_id''');
  definition=replace(definition, 'refund."refundedSaleId"', 'refund.refunded_sale_id');
  EXECUTE definition;
END $$;
