-- UAT verification queries (READ-ONLY). Independent of the TypeScript reconciliation.
-- Company: f3651f62-be10-41aa-bde7-663cf990eae8 (Cafeteria la bomba)
-- Decoy  : 1b2c3d4e-5f60-4711-8223-334455667788 (must never change)

\echo '== 1. Imported volume per entity (target company) =='
SELECT
  (SELECT count(*) FROM "Product" WHERE company_id = 'f3651f62-be10-41aa-bde7-663cf990eae8') AS products,
  (SELECT count(*) FROM "Product" WHERE company_id = 'f3651f62-be10-41aa-bde7-663cf990eae8' AND archived_at IS NULL) AS active_products,
  (SELECT count(*) FROM "Product" WHERE company_id = 'f3651f62-be10-41aa-bde7-663cf990eae8' AND archived_at IS NOT NULL) AS archived_products,
  (SELECT count(*) FROM warehouse_stocks WHERE company_id = 'f3651f62-be10-41aa-bde7-663cf990eae8') AS stocks,
  (SELECT count(*) FROM cash_sessions WHERE company_id = 'f3651f62-be10-41aa-bde7-663cf990eae8') AS shifts,
  (SELECT count(*) FROM "Sale" WHERE company_id = 'f3651f62-be10-41aa-bde7-663cf990eae8') AS sales,
  (SELECT count(*) FROM "SaleItem" i JOIN "Sale" s ON s.id = i."saleId" WHERE s.company_id = 'f3651f62-be10-41aa-bde7-663cf990eae8') AS sale_items;

\echo '== 2. Money totals from PostgreSQL =='
SELECT
  sum(s."totalSold") AS revenue,
  sum(s."totalCost") AS cost,
  sum(s."totalProfit") AS profit,
  sum(s.tax_amount) AS itbis,
  sum(s."commissionAmount") AS commission,
  count(*) FILTER (WHERE s.ncf IS NOT NULL) AS with_ncf,
  count(*) FILTER (WHERE s.status = 'CANCELLED') AS cancelled,
  count(*) FILTER (WHERE s."cashSessionId" IS NOT NULL) AS linked_to_shift,
  count(*) FILTER (WHERE s."cashSessionId" IS NULL) AS without_shift
FROM "Sale" s
WHERE s.company_id = 'f3651f62-be10-41aa-bde7-663cf990eae8';

\echo '== 3. Stock invariant: Product.stock must equal SUM(WarehouseStock.quantity) =='
SELECT count(*) AS mismatches
FROM "Product" p
LEFT JOIN (
  SELECT product_id, sum(quantity) AS total FROM warehouse_stocks
  WHERE company_id = 'f3651f62-be10-41aa-bde7-663cf990eae8'
  GROUP BY product_id
) ws ON ws.product_id = p.id
WHERE p.company_id = 'f3651f62-be10-41aa-bde7-663cf990eae8'
  AND p.stock <> COALESCE(ws.total, 0);

\echo '== 4. Shift history: every imported shift CLOSED with a real closed_at =='
SELECT count(*) AS shifts, count(*) FILTER (WHERE status = 'CLOSED') AS closed,
       count(*) FILTER (WHERE "closedAt" IS NULL) AS closed_at_null,
       count(*) FILTER (WHERE status = 'OPEN') AS open_shifts,
       min("closedAt") AS oldest, max("closedAt") AS newest
FROM cash_sessions WHERE company_id = 'f3651f62-be10-41aa-bde7-663cf990eae8';

\echo '== 5. What the Cloud shift-history endpoint would return (closedAt DESC, LIMIT 60) =='
SELECT count(*) AS visible_shifts FROM (
  SELECT id FROM cash_sessions
  WHERE company_id = 'f3651f62-be10-41aa-bde7-663cf990eae8' AND status = 'CLOSED'
  ORDER BY "closedAt" DESC LIMIT 60
) t;

\echo '== 6. Referential integrity of the imported set (orphans) =='
SELECT
  (SELECT count(*) FROM "SaleItem" i LEFT JOIN "Sale" s ON s.id = i."saleId" WHERE s.id IS NULL) AS items_without_sale,
  (SELECT count(*) FROM warehouse_stocks w LEFT JOIN "Product" p ON p.id = w.product_id WHERE p.id IS NULL) AS stocks_without_product,
  (SELECT count(*) FROM "Sale" s LEFT JOIN users u ON u.id = s."userId" WHERE u.id IS NULL) AS sales_without_user;

\echo '== 7. Cross-tenant canary: decoy rows must be intact and no stray tenants =='
SELECT
  (SELECT count(*) FROM companies) AS companies,
  (SELECT count(*) FROM "Product" WHERE company_id = '1b2c3d4e-5f60-4711-8223-334455667788') AS decoy_products,
  (SELECT count(*) FROM warehouse_stocks WHERE company_id = '1b2c3d4e-5f60-4711-8223-334455667788') AS decoy_stocks,
  (SELECT count(*) FROM cash_sessions WHERE company_id = '1b2c3d4e-5f60-4711-8223-334455667788') AS decoy_shifts,
  (SELECT count(*) FROM "Sale" WHERE company_id = '1b2c3d4e-5f60-4711-8223-334455667788') AS decoy_sales,
  (SELECT count(*) FROM "SaleItem" i JOIN "Sale" s ON s.id = i."saleId" WHERE s.company_id = '1b2c3d4e-5f60-4711-8223-334455667788') AS decoy_items;

\echo '== 8. Distinct company_id values per imported table (must only be the 2 known tenants) =='
SELECT 'products' AS tabla, count(DISTINCT company_id) AS empresas FROM "Product"
UNION ALL SELECT 'warehouse_stocks', count(DISTINCT company_id) FROM warehouse_stocks
UNION ALL SELECT 'cash_sessions', count(DISTINCT company_id) FROM cash_sessions
UNION ALL SELECT 'sales', count(DISTINCT company_id) FROM "Sale"
ORDER BY tabla;

\echo '== 9. Out-of-scope objects must be ZERO for the target company =='
SELECT
  (SELECT count(*) FROM "Client" WHERE company_id = 'f3651f62-be10-41aa-bde7-663cf990eae8') AS clients,
  (SELECT count(*) FROM suppliers WHERE company_id = 'f3651f62-be10-41aa-bde7-663cf990eae8') AS suppliers,
  (SELECT count(*) FROM purchase_orders WHERE company_id = 'f3651f62-be10-41aa-bde7-663cf990eae8') AS purchase_orders,
  (SELECT count(*) FROM cash_movements WHERE company_id = 'f3651f62-be10-41aa-bde7-663cf990eae8') AS cash_movements,
  (SELECT count(*) FROM cashbox_daily WHERE company_id = 'f3651f62-be10-41aa-bde7-663cf990eae8') AS cashbox_daily,
  (SELECT count(*) FROM inventory_movements WHERE company_id = 'f3651f62-be10-41aa-bde7-663cf990eae8') AS inventory_movements,
  (SELECT count(*) FROM taxes WHERE company_id = 'f3651f62-be10-41aa-bde7-663cf990eae8') AS taxes,
  (SELECT count(*) FROM ncf_sequences WHERE company_id = 'f3651f62-be10-41aa-bde7-663cf990eae8') AS ncf_sequences,
  (SELECT count(*) FROM "Product" WHERE company_id = 'f3651f62-be10-41aa-bde7-663cf990eae8' AND codigo LIKE 'DEMO-%') AS demo_products;
\echo '== 10. Reporting shape: daily totals / top products (Cloud report equivalents) =='
SELECT date(s."saleDate") AS dia, count(*) AS ventas, sum(s."totalSold") AS total
FROM "Sale" s
WHERE s.company_id = 'f3651f62-be10-41aa-bde7-663cf990eae8'
GROUP BY 1 ORDER BY 1 DESC LIMIT 5;

SELECT i."productNameSnapshot" AS producto, sum(i.qty) AS cantidad, sum(i."subtotalSold") AS total
FROM "SaleItem" i JOIN "Sale" s ON s.id = i."saleId"
WHERE s.company_id = 'f3651f62-be10-41aa-bde7-663cf990eae8'
GROUP BY 1 ORDER BY 3 DESC LIMIT 5;

\echo '== 11. Text integrity: Spanish accents preserved as UTF-8 (chr(209)=N-tilde) =='
SELECT count(*) AS productos,
       count(*) FILTER (WHERE strpos(nombre, chr(209)) > 0) AS con_enie_mayuscula,
       count(*) FILTER (WHERE strpos(nombre, chr(241)) > 0) AS con_enie_minuscula,
       count(*) FILTER (WHERE strpos(nombre, chr(193)) > 0) AS con_a_acentuada,
       sum(octet_length(nombre)) AS bytes_nombre
FROM "Product" WHERE company_id = 'f3651f62-be10-41aa-bde7-663cf990eae8';

\echo '== 12. No imported row is shared with the decoy tenant =='
SELECT
  (SELECT count(*) FROM "Product" WHERE company_id = '1b2c3d4e-5f60-4711-8223-334455667788'
     AND id IN (SELECT id FROM "Product" WHERE company_id = 'f3651f62-be10-41aa-bde7-663cf990eae8')) AS shared_products,
  (SELECT count(*) FROM "Sale" WHERE company_id = '1b2c3d4e-5f60-4711-8223-334455667788'
     AND id IN (SELECT id FROM "Sale" WHERE company_id = 'f3651f62-be10-41aa-bde7-663cf990eae8')) AS shared_sales,
  (SELECT count(*) FROM cash_sessions WHERE company_id = '1b2c3d4e-5f60-4711-8223-334455667788'
     AND id IN (SELECT id FROM cash_sessions WHERE company_id = 'f3651f62-be10-41aa-bde7-663cf990eae8')) AS shared_shifts;
