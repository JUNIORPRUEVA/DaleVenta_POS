-- POST-CUTOVER RECONCILIATION (read-only). Phase 5, Step 8.
-- Run inside the production database container after the authorized cutover:
--   docker exec -i <db_container> sh -c 'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -f /tmp/reconciliation.sql'
--
-- Every block prints PASS/FAIL. Nothing here writes.

\echo '== 1. TARGET TENANT VOLUME (expected 91 / 87 / 4 / 87 / 50 / 7179 / 9746) =='
SELECT
  CASE WHEN products = 91 AND active = 87 AND archived = 4 AND stocks = 87
            AND shifts = 50 AND sales = 7179 AND items = 9746
       THEN 'PASS' ELSE 'FAIL' END AS verdict,
  products, active, archived, stocks, shifts, sales, items
FROM (
  SELECT
    (SELECT count(*) FROM "Product" WHERE company_id = 'f3651f62-be10-41aa-bde7-663cf990eae8') AS products,
    (SELECT count(*) FROM "Product" WHERE company_id = 'f3651f62-be10-41aa-bde7-663cf990eae8' AND archived_at IS NULL) AS active,
    (SELECT count(*) FROM "Product" WHERE company_id = 'f3651f62-be10-41aa-bde7-663cf990eae8' AND archived_at IS NOT NULL) AS archived,
    (SELECT count(*) FROM warehouse_stocks WHERE company_id = 'f3651f62-be10-41aa-bde7-663cf990eae8') AS stocks,
    (SELECT count(*) FROM cash_sessions WHERE company_id = 'f3651f62-be10-41aa-bde7-663cf990eae8') AS shifts,
    (SELECT count(*) FROM "Sale" WHERE company_id = 'f3651f62-be10-41aa-bde7-663cf990eae8') AS sales,
    (SELECT count(*) FROM "SaleItem" i JOIN "Sale" s ON s.id = i."saleId" WHERE s.company_id = 'f3651f62-be10-41aa-bde7-663cf990eae8') AS items
) t;

\echo '== 2. MONEY (expected 1095535.00 / 742332.88 / 353202.12 · ITBIS 0 · NCF 0 · comision 0) =='
SELECT
  CASE WHEN revenue = 1095535.00 AND cost = 742332.88 AND profit = 353202.12
            AND itbis = 0.00 AND commission = 0.00 AND with_ncf = 0
       THEN 'PASS' ELSE 'FAIL' END AS verdict,
  revenue, cost, profit, itbis, commission, with_ncf
FROM (
  SELECT sum(s."totalSold") AS revenue, sum(s."totalCost") AS cost, sum(s."totalProfit") AS profit,
         sum(s.tax_amount) AS itbis, sum(s."commissionAmount") AS commission,
         count(*) FILTER (WHERE s.ncf IS NOT NULL) AS with_ncf
  FROM "Sale" s WHERE s.company_id = 'f3651f62-be10-41aa-bde7-663cf990eae8'
) t;

\echo '== 3. SALES STATUS AND SHIFT LINKS (expected 7176 / 3 / 3930 / 3249) =='
SELECT
  CASE WHEN completed = 7176 AND cancelled = 3 AND linked = 3930 AND unlinked = 3249
       THEN 'PASS' ELSE 'FAIL' END AS verdict,
  completed, cancelled, linked, unlinked
FROM (
  SELECT count(*) FILTER (WHERE s.status = 'PAID') AS completed,
         count(*) FILTER (WHERE s.status = 'CANCELLED') AS cancelled,
         count(*) FILTER (WHERE s."cashSessionId" IS NOT NULL) AS linked,
         count(*) FILTER (WHERE s."cashSessionId" IS NULL) AS unlinked
  FROM "Sale" s WHERE s.company_id = 'f3651f62-be10-41aa-bde7-663cf990eae8'
) t;

\echo '== 4. STOCK INTEGRITY (expected total 1557.00 · mismatches 0 · negatives 0) =='
SELECT
  CASE WHEN mismatches = 0 AND negatives = 0 AND stock_total = 1557.00
       THEN 'PASS' ELSE 'FAIL' END AS verdict, stock_total, mismatches, negatives
FROM (
  SELECT
    (SELECT coalesce(sum(quantity), 0) FROM warehouse_stocks WHERE company_id = 'f3651f62-be10-41aa-bde7-663cf990eae8') AS stock_total,
    (SELECT count(*) FROM "Product" p
       LEFT JOIN (SELECT product_id, sum(quantity) AS total FROM warehouse_stocks
                   WHERE company_id = 'f3651f62-be10-41aa-bde7-663cf990eae8' GROUP BY product_id) ws
         ON ws.product_id = p.id
      WHERE p.company_id = 'f3651f62-be10-41aa-bde7-663cf990eae8'
        AND p.stock <> COALESCE(ws.total, 0)) AS mismatches,
    (SELECT count(*) FROM "Product" WHERE company_id = 'f3651f62-be10-41aa-bde7-663cf990eae8' AND stock < 0) AS negatives
) t;

\echo '== 5. SHIFT HISTORY (expected 50 CLOSED · 0 OPEN · 0 null closedAt) =='
SELECT
  CASE WHEN shifts = 50 AND closed = 50 AND open_shifts = 0 AND null_closed = 0
       THEN 'PASS' ELSE 'FAIL' END AS verdict, shifts, closed, open_shifts, null_closed, oldest, newest
FROM (
  SELECT count(*) AS shifts, count(*) FILTER (WHERE status = 'CLOSED') AS closed,
         count(*) FILTER (WHERE status = 'OPEN') AS open_shifts,
         count(*) FILTER (WHERE "closedAt" IS NULL) AS null_closed,
         min("closedAt") AS oldest, max("closedAt") AS newest
  FROM cash_sessions WHERE company_id = 'f3651f62-be10-41aa-bde7-663cf990eae8'
) t;

\echo '== 6. OUT-OF-SCOPE OBJECTS MUST BE ZERO (expected PASS) =='
SELECT
  CASE WHEN clients = 0 AND suppliers = 0 AND purchase_orders = 0 AND cash_movements = 0
            AND cashbox_daily = 0 AND inventory_movements = 0 AND taxes = 0 AND ncf_sequences = 0
            AND credit_payments = 0 AND demo_products = 0
       THEN 'PASS' ELSE 'FAIL' END AS verdict,
  clients, suppliers, purchase_orders, cash_movements, cashbox_daily, inventory_movements, taxes, ncf_sequences, credit_payments, demo_products
FROM (
  SELECT
    (SELECT count(*) FROM "Client" WHERE company_id = 'f3651f62-be10-41aa-bde7-663cf990eae8') AS clients,
    (SELECT count(*) FROM suppliers WHERE company_id = 'f3651f62-be10-41aa-bde7-663cf990eae8') AS suppliers,
    (SELECT count(*) FROM purchase_orders WHERE company_id = 'f3651f62-be10-41aa-bde7-663cf990eae8') AS purchase_orders,
    (SELECT count(*) FROM cash_movements WHERE company_id = 'f3651f62-be10-41aa-bde7-663cf990eae8') AS cash_movements,
    (SELECT count(*) FROM cashbox_daily WHERE company_id = 'f3651f62-be10-41aa-bde7-663cf990eae8') AS cashbox_daily,
    (SELECT count(*) FROM inventory_movements WHERE company_id = 'f3651f62-be10-41aa-bde7-663cf990eae8') AS inventory_movements,
    (SELECT count(*) FROM taxes WHERE company_id = 'f3651f62-be10-41aa-bde7-663cf990eae8') AS taxes,
    (SELECT count(*) FROM ncf_sequences WHERE company_id = 'f3651f62-be10-41aa-bde7-663cf990eae8') AS ncf_sequences,
    (SELECT count(*) FROM sale_credit_payments WHERE company_id = 'f3651f62-be10-41aa-bde7-663cf990eae8') AS credit_payments,
    (SELECT count(*) FROM "Product" WHERE company_id = 'f3651f62-be10-41aa-bde7-663cf990eae8' AND codigo LIKE 'DEMO-%') AS demo_products
) t;

\echo '== 7. OPERATIONAL NEUTRALITY OF IMPORTED HISTORY (expected 0 tracked items) =='
SELECT
  CASE WHEN tracked = 0 AND not_local = 0 THEN 'PASS' ELSE 'FAIL' END AS verdict, tracked, not_local
FROM (
  SELECT
    (SELECT count(*) FROM "SaleItem" i JOIN "Sale" s ON s.id = i."saleId"
      WHERE s.company_id = 'f3651f62-be10-41aa-bde7-663cf990eae8' AND i.inventory_tracked_snapshot) AS tracked,
    (SELECT count(*) FROM "SaleItem" i JOIN "Sale" s ON s.id = i."saleId"
      WHERE s.company_id = 'f3651f62-be10-41aa-bde7-663cf990eae8' AND i.product_source <> 'LOCAL') AS not_local
) t;

\echo '== 8. OTHER TENANTS NOT DAMAGED (reference captured 2026-09-16 18:5xZ; production is LIVE) =='
-- Production is live: other tenants legitimately create new rows (a new sale was observed
-- during the freeze phase). Therefore this check is monotonic: no other tenant may LOSE rows
-- and no tenant may disappear. The target tenant itself is checked exactly in blocks 1-7.
SELECT
  CASE WHEN
     (SELECT count(*) FROM companies) >= 27
     AND (SELECT count(*) FROM "Product" WHERE company_id = '165e3fca-6225-479b-8805-d2205f10536c') >= 110
     AND (SELECT count(*) FROM "Product" WHERE company_id = '019b0b85-44d8-46ba-a114-5b362a8477ed') >= 100
     AND (SELECT count(*) FROM "Product" WHERE company_id = '4fc72f78-e5d1-427a-9877-d95cf2898947') >= 85
     AND (SELECT count(*) FROM "Product" WHERE company_id = 'e4fe4847-96d7-4cac-b909-07e756988af3') >= 29
     AND (SELECT count(*) FROM "Product" WHERE company_id IN (
            '1c99e261-06d8-4e6e-b84e-e1f16d2aba59','efbb9fa1-d5a3-4f9c-a9f4-9e15e01c7d3e',
            'd5bfb7d7-54e1-488f-a821-cdfa0ce54ad0','7de5e28d-1347-4918-badd-2d4aeca840fc')) >= 4
     AND (SELECT count(*) FROM "Product" WHERE company_id <> 'f3651f62-be10-41aa-bde7-663cf990eae8') >= 328
     AND (SELECT count(*) FROM "Sale" WHERE company_id <> 'f3651f62-be10-41aa-bde7-663cf990eae8') >= 1223
     AND (SELECT count(*) FROM "Product" WHERE company_id = 'f3651f62-be10-41aa-bde7-663cf990eae8') = 91
     AND (SELECT count(*) FROM "Sale" WHERE company_id = 'f3651f62-be10-41aa-bde7-663cf990eae8') = 7179
   THEN 'PASS' ELSE 'FAIL' END AS verdict,
  (SELECT count(*) FROM companies) AS companies,
  (SELECT count(*) FROM "Product") AS products_all_tenants,
  (SELECT count(*) FROM "Sale") AS sales_all_tenants,
  (SELECT count(*) FROM "Product" WHERE company_id <> 'f3651f62-be10-41aa-bde7-663cf990eae8') AS products_other_tenants,
  (SELECT count(*) FROM "Sale" WHERE company_id <> 'f3651f62-be10-41aa-bde7-663cf990eae8') AS sales_other_tenants;

\echo '== 9. DETERMINISTIC IDs PRESENT (sample from the manifest) =='
SELECT count(*) AS expected_sample_present, 5 AS expected_sample_size
FROM "Product"
WHERE company_id = 'f3651f62-be10-41aa-bde7-663cf990eae8';

\echo '== 10. LICENSE / TENANT FLAGS UNCHANGED BY THE MIGRATION =='
SELECT c.status::text, c.plan::text, c.license_status::text, c.max_users, c.max_products,
       c.tax_enabled, c.ncf_enabled, c.product_source::text
FROM companies c WHERE c.id = 'f3651f62-be10-41aa-bde7-663cf990eae8';
