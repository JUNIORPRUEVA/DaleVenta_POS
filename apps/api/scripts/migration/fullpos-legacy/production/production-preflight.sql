-- READ-ONLY production preflight (Phase 5, Step 3 + Step 4).
-- Executed only through an authorized read-only channel (psql inside the production
-- database container). SELECT statements only; no secrets are printed.

\echo '== A. CONNECTION =='
SELECT current_database() AS database_name,
       current_user AS db_user,
       inet_server_addr()::text AS server_address,
       inet_server_port() AS server_port,
       version() AS server_version;

\echo '== B. MIGRATION FOOTPRINT OF THE TARGET TENANT (must be empty) =='
SELECT
  (SELECT count(*) FROM "Product"        WHERE company_id = 'f3651f62-be10-41aa-bde7-663cf990eae8') AS products,
  (SELECT count(*) FROM warehouse_stocks WHERE company_id = 'f3651f62-be10-41aa-bde7-663cf990eae8') AS warehouse_stocks,
  (SELECT count(*) FROM "Sale"           WHERE company_id = 'f3651f62-be10-41aa-bde7-663cf990eae8') AS sales,
  (SELECT count(*) FROM "SaleItem" i JOIN "Sale" s ON s.id = i."saleId"
     WHERE s.company_id = 'f3651f62-be10-41aa-bde7-663cf990eae8') AS sale_items,
  (SELECT count(*) FROM cash_sessions    WHERE company_id = 'f3651f62-be10-41aa-bde7-663cf990eae8') AS cash_sessions,
  (SELECT count(*) FROM cash_movements   WHERE company_id = 'f3651f62-be10-41aa-bde7-663cf990eae8') AS cash_movements,
  (SELECT count(*) FROM cashbox_daily    WHERE company_id = 'f3651f62-be10-41aa-bde7-663cf990eae8') AS cashbox_daily,
  (SELECT count(*) FROM inventory_movements WHERE company_id = 'f3651f62-be10-41aa-bde7-663cf990eae8') AS inventory_movements,
  (SELECT count(*) FROM "Client"         WHERE company_id = 'f3651f62-be10-41aa-bde7-663cf990eae8') AS clients,
  (SELECT count(*) FROM suppliers        WHERE company_id = 'f3651f62-be10-41aa-bde7-663cf990eae8') AS suppliers,
  (SELECT count(*) FROM purchase_orders  WHERE company_id = 'f3651f62-be10-41aa-bde7-663cf990eae8') AS purchase_orders,
  (SELECT count(*) FROM taxes            WHERE company_id = 'f3651f62-be10-41aa-bde7-663cf990eae8') AS taxes,
  (SELECT count(*) FROM ncf_sequences    WHERE company_id = 'f3651f62-be10-41aa-bde7-663cf990eae8') AS ncf_sequences,
  (SELECT count(*) FROM sale_credit_payments WHERE company_id = 'f3651f62-be10-41aa-bde7-663cf990eae8') AS credit_payments;

\echo '== C. TARGET TENANT IDENTITY + LICENSE (Step 4) =='
SELECT c.id, c.name, c.slug, c.status::text AS status, c.plan::text AS plan,
       c.license_status::text AS license_status,
       (c.license_key IS NOT NULL) AS has_license_key,
       c.trial_started_at, c.trial_ends_at, c.license_activated_at, c.license_expires_at,
       (c.license_expires_at IS NULL OR c.license_expires_at > now()) AS license_current,
       c.license_blocked_at, c.max_users, c.max_products,
       c.tax_enabled, c.ncf_enabled, c.prices_include_tax, c.default_tax_rate,
       c.inventory_enabled, c.measurement_units_enabled, c.multi_warehouse_enabled,
       c.product_source::text AS product_source,
       (SELECT count(*) FROM taxes t WHERE t.company_id = c.id) AS taxes_of_company,
       (SELECT count(*) FROM ncf_sequences n WHERE n.company_id = c.id) AS ncf_sequences_of_company
FROM companies c
WHERE c.id = 'f3651f62-be10-41aa-bde7-663cf990eae8';

\echo '== D. TENANT ISOLATION: warehouse / terminal / owner belong to the company =='
SELECT w.id AS warehouse_id, w.company_id AS warehouse_company, (w.company_id = 'f3651f62-be10-41aa-bde7-663cf990eae8') AS warehouse_ok,
       w.name AS warehouse_name, w.code AS warehouse_code, w.is_active, w.is_default
FROM warehouses w WHERE w.id = 'ffc9ef9b-9157-418d-8aa1-94112278bb68';

SELECT t.id AS terminal_id, t.company_id AS terminal_company, (t.company_id = 'f3651f62-be10-41aa-bde7-663cf990eae8') AS terminal_ok,
       t.default_warehouse_id, (t.default_warehouse_id = 'ffc9ef9b-9157-418d-8aa1-94112278bb68') AS terminal_warehouse_ok,
       t.name AS terminal_name, t.code AS terminal_code, t.is_active
FROM terminals t WHERE t.id = '00931697-e152-48bc-9e44-02023e14d465';

SELECT u.id AS owner_id, u.company_id AS owner_company, (u.company_id = 'f3651f62-be10-41aa-bde7-663cf990eae8') AS owner_ok,
       u.email, u.role::text AS role, u.blocked
FROM users u WHERE u.id = 'adc4bf90-41b3-4e20-99eb-f37d398200f5';

SELECT m.role::text AS member_role, m.status::text AS member_status
FROM company_members m
WHERE m.company_id = 'f3651f62-be10-41aa-bde7-663cf990eae8'
  AND m.user_id = 'adc4bf90-41b3-4e20-99eb-f37d398200f5';

\echo '== E. GLOBAL REFERENCE VALUES (no writes) =='
SELECT 'companies_total' AS metric, count(*)::text AS value FROM companies
UNION ALL SELECT 'users_of_target', count(*)::text FROM users WHERE company_id = 'f3651f62-be10-41aa-bde7-663cf990eae8'
UNION ALL SELECT 'products_total_all_tenants', count(*)::text FROM "Product"
UNION ALL SELECT 'sales_total_all_tenants', count(*)::text FROM "Sale"
UNION ALL SELECT 'uom_unit_present', count(*)::text FROM unit_of_measures WHERE id = 'UNIT'
UNION ALL SELECT 'migrations_applied', count(*)::text FROM _prisma_migrations WHERE finished_at IS NOT NULL;

\echo '== F. OTHER TENANTS MUST KEEP THEIR OWN FOOTPRINT (isolation reference) =='
SELECT company_id, count(*) AS products
FROM "Product" WHERE company_id <> 'f3651f62-be10-41aa-bde7-663cf990eae8'
GROUP BY company_id ORDER BY products DESC LIMIT 10;
