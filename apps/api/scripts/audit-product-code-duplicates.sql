-- Report product-code duplicates scoped by company using normalized codes.
-- Read-only: this script does not delete, merge or update any product.

SELECT
  "company_id",
  LOWER(BTRIM("codigo")) AS normalized_code,
  COUNT(*) AS duplicate_count,
  STRING_AGG("id"::text, ', ' ORDER BY "id"::text) AS product_ids,
  STRING_AGG("nombre", ' | ' ORDER BY "nombre") AS product_names
FROM "Product"
WHERE "company_id" IS NOT NULL
  AND NULLIF(BTRIM("codigo"), '') IS NOT NULL
GROUP BY "company_id", LOWER(BTRIM("codigo"))
HAVING COUNT(*) > 1
ORDER BY duplicate_count DESC, "company_id", normalized_code;
