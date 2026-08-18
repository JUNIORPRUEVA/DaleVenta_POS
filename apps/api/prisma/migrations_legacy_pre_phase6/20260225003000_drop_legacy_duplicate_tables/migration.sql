-- Cleanup legacy duplicated tables (lowercase/plural) and obsolete category table
-- Keep `users` because auth/users modules still use raw SQL against it.

DROP TABLE IF EXISTS "products" CASCADE;
DROP TABLE IF EXISTS "customers" CASCADE;
DROP TABLE IF EXISTS "sales" CASCADE;
DROP TABLE IF EXISTS "sale_items" CASCADE;
DROP TABLE IF EXISTS "payroll_employees" CASCADE;
DROP TABLE IF EXISTS "payroll_employee_config" CASCADE;
DROP TABLE IF EXISTS "payroll_entries" CASCADE;
DROP TABLE IF EXISTS "payroll_periods" CASCADE;

-- Category is obsolete after Product.categoria migration
DROP TABLE IF EXISTS "Category" CASCADE;
