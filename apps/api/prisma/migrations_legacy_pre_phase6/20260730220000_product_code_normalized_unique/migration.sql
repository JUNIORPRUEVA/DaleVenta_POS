-- Enforce tenant-scoped product-code uniqueness using normalized, non-empty codes.
-- This intentionally does not merge/delete existing data. If duplicate codes
-- already exist inside a company, the migration stops with a diagnostic so data
-- can be reconciled without risking sales, purchase or stock history.

DO $$
DECLARE
  duplicate_count INTEGER;
BEGIN
  SELECT COUNT(*)
  INTO duplicate_count
  FROM (
    SELECT "company_id", LOWER(BTRIM("codigo")) AS normalized_code
    FROM "Product"
    WHERE "company_id" IS NOT NULL
      AND NULLIF(BTRIM("codigo"), '') IS NOT NULL
    GROUP BY "company_id", LOWER(BTRIM("codigo"))
    HAVING COUNT(*) > 1
  ) duplicates;

  IF duplicate_count > 0 THEN
    RAISE EXCEPTION
      'Cannot create Product tenant/code unique index: % duplicate company/code group(s) exist. Run the product duplicate audit report and reconcile before applying this migration.',
      duplicate_count;
  END IF;
END $$;

DROP INDEX IF EXISTS "Product_company_id_codigo_key";

CREATE UNIQUE INDEX IF NOT EXISTS "Product_company_id_codigo_normalized_key"
  ON "Product"("company_id", LOWER(BTRIM("codigo")))
  WHERE "company_id" IS NOT NULL
    AND NULLIF(BTRIM("codigo"), '') IS NOT NULL;
