-- Cloud-sync schema init (PostgreSQL 15+)

-- Ensure schema exists
CREATE SCHEMA IF NOT EXISTS public;

-- UUID generation (gen_random_uuid)
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- Drop previous demo schema (safe for fresh or reset dev DB)
DROP TABLE IF EXISTS "Sale" CASCADE;
DROP TABLE IF EXISTS "Product" CASCADE;
DROP TABLE IF EXISTS "Customer" CASCADE;
DROP TABLE IF EXISTS "User" CASCADE;
DROP TYPE IF EXISTS "Role";

-- Drop sync tables if re-running
DROP TABLE IF EXISTS sale_items CASCADE;
DROP TABLE IF EXISTS sales CASCADE;
DROP TABLE IF EXISTS products CASCADE;
DROP TABLE IF EXISTS customers CASCADE;
DROP TABLE IF EXISTS sync_state CASCADE;
DROP TABLE IF EXISTS audit_log CASCADE;
DROP TABLE IF EXISTS users CASCADE;

-- Enums
CREATE TYPE "Role" AS ENUM ('ADMIN', 'USER');

-- Tables
CREATE TABLE users (
  "id" uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "email" text NOT NULL UNIQUE,
  "passwordHash" text NOT NULL,
  "role" "Role" NOT NULL DEFAULT 'USER',
  "createdAt" timestamptz NOT NULL DEFAULT now(),
  "updatedAt" timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE customers (
  "id" uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "name" text NOT NULL,
  "phone" text NULL,
  "address" text NULL,
  "createdAt" timestamptz NOT NULL DEFAULT now(),
  "updatedAt" timestamptz NOT NULL DEFAULT now(),
  "deletedAt" timestamptz NULL,
  "version" int NOT NULL DEFAULT 1,
  "updatedById" uuid NULL REFERENCES users("id") ON DELETE SET NULL,
  "deviceId" text NULL
);

CREATE INDEX customers_updatedAt_idx ON customers ("updatedAt");
CREATE INDEX customers_deletedAt_idx ON customers ("deletedAt");
CREATE INDEX customers_updatedAt_deletedAt_idx ON customers ("updatedAt", "deletedAt");

CREATE TABLE products (
  "id" uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "name" text NOT NULL,
  "sku" text NULL UNIQUE,
  "price" numeric(12,2) NOT NULL DEFAULT 0,
  "stock" numeric(12,2) NOT NULL DEFAULT 0,
  "createdAt" timestamptz NOT NULL DEFAULT now(),
  "updatedAt" timestamptz NOT NULL DEFAULT now(),
  "deletedAt" timestamptz NULL,
  "version" int NOT NULL DEFAULT 1,
  "updatedById" uuid NULL REFERENCES users("id") ON DELETE SET NULL,
  "deviceId" text NULL
);

CREATE INDEX products_updatedAt_idx ON products ("updatedAt");
CREATE INDEX products_deletedAt_idx ON products ("deletedAt");
CREATE INDEX products_updatedAt_deletedAt_idx ON products ("updatedAt", "deletedAt");

CREATE TABLE sales (
  "id" uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "customerId" uuid NULL REFERENCES customers("id") ON DELETE SET NULL,
  "total" numeric(12,2) NOT NULL DEFAULT 0,
  "note" text NULL,
  "createdAt" timestamptz NOT NULL DEFAULT now(),
  "updatedAt" timestamptz NOT NULL DEFAULT now(),
  "deletedAt" timestamptz NULL,
  "version" int NOT NULL DEFAULT 1,
  "updatedById" uuid NULL REFERENCES users("id") ON DELETE SET NULL,
  "deviceId" text NULL
);

CREATE INDEX sales_updatedAt_idx ON sales ("updatedAt");
CREATE INDEX sales_deletedAt_idx ON sales ("deletedAt");
CREATE INDEX sales_updatedAt_deletedAt_idx ON sales ("updatedAt", "deletedAt");
CREATE INDEX sales_customerId_idx ON sales ("customerId");

CREATE TABLE sale_items (
  "id" uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "saleId" uuid NOT NULL REFERENCES sales("id") ON DELETE CASCADE,
  "productId" uuid NOT NULL REFERENCES products("id") ON DELETE RESTRICT,
  "qty" numeric(12,2) NOT NULL DEFAULT 1,
  "price" numeric(12,2) NOT NULL DEFAULT 0,
  "lineTotal" numeric(12,2) GENERATED ALWAYS AS ("qty" * "price") STORED,
  "createdAt" timestamptz NOT NULL DEFAULT now(),
  "updatedAt" timestamptz NOT NULL DEFAULT now(),
  "deletedAt" timestamptz NULL
);

CREATE INDEX sale_items_updatedAt_idx ON sale_items ("updatedAt");
CREATE INDEX sale_items_deletedAt_idx ON sale_items ("deletedAt");
CREATE INDEX sale_items_updatedAt_deletedAt_idx ON sale_items ("updatedAt", "deletedAt");
CREATE INDEX sale_items_saleId_idx ON sale_items ("saleId");
CREATE INDEX sale_items_productId_idx ON sale_items ("productId");

CREATE TABLE audit_log (
  "id" uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "entity" text NOT NULL,
  "entityId" uuid NOT NULL,
  "action" text NOT NULL,
  "userId" uuid NULL REFERENCES users("id") ON DELETE SET NULL,
  "deviceId" text NULL,
  "meta" jsonb NULL,
  "createdAt" timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT audit_log_action_check CHECK ("action" IN ('CREATE', 'UPDATE', 'DELETE', 'SYNC_PUSH'))
);

CREATE INDEX audit_log_createdAt_idx ON audit_log ("createdAt");
CREATE INDEX audit_log_entity_entityId_idx ON audit_log ("entity", "entityId");

CREATE TABLE sync_state (
  "userId" uuid PRIMARY KEY REFERENCES users("id") ON DELETE CASCADE,
  "lastPullAt" timestamptz NULL,
  "lastPushAt" timestamptz NULL,
  "updatedAt" timestamptz NOT NULL DEFAULT now()
);

-- Triggers
CREATE OR REPLACE FUNCTION set_updated_at() RETURNS trigger AS $$
BEGIN
  NEW."updatedAt" = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION bump_version() RETURNS trigger AS $$
BEGIN
  NEW."version" = COALESCE(OLD."version", 0) + 1;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_customers_set_updated_at ON customers;
CREATE TRIGGER trg_customers_set_updated_at
BEFORE UPDATE ON customers
FOR EACH ROW EXECUTE FUNCTION set_updated_at();

DROP TRIGGER IF EXISTS trg_products_set_updated_at ON products;
CREATE TRIGGER trg_products_set_updated_at
BEFORE UPDATE ON products
FOR EACH ROW EXECUTE FUNCTION set_updated_at();

DROP TRIGGER IF EXISTS trg_sales_set_updated_at ON sales;
CREATE TRIGGER trg_sales_set_updated_at
BEFORE UPDATE ON sales
FOR EACH ROW EXECUTE FUNCTION set_updated_at();

DROP TRIGGER IF EXISTS trg_sale_items_set_updated_at ON sale_items;
CREATE TRIGGER trg_sale_items_set_updated_at
BEFORE UPDATE ON sale_items
FOR EACH ROW EXECUTE FUNCTION set_updated_at();

DROP TRIGGER IF EXISTS trg_sync_state_set_updated_at ON sync_state;
CREATE TRIGGER trg_sync_state_set_updated_at
BEFORE UPDATE ON sync_state
FOR EACH ROW EXECUTE FUNCTION set_updated_at();

DROP TRIGGER IF EXISTS trg_customers_bump_version ON customers;
CREATE TRIGGER trg_customers_bump_version
BEFORE UPDATE ON customers
FOR EACH ROW EXECUTE FUNCTION bump_version();

DROP TRIGGER IF EXISTS trg_products_bump_version ON products;
CREATE TRIGGER trg_products_bump_version
BEFORE UPDATE ON products
FOR EACH ROW EXECUTE FUNCTION bump_version();

DROP TRIGGER IF EXISTS trg_sales_bump_version ON sales;
CREATE TRIGGER trg_sales_bump_version
BEFORE UPDATE ON sales
FOR EACH ROW EXECUTE FUNCTION bump_version();
