-- W15: company-scoped multi-warehouse visibility flag.
-- Safe default: existing companies remain in simple inventory mode.
ALTER TABLE "companies"
  ADD COLUMN IF NOT EXISTS "multi_warehouse_enabled" BOOLEAN NOT NULL DEFAULT false;
