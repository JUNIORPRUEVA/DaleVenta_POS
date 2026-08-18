-- Client master profile: phone normalization, deduplication, and activity tracking

-- 1) Add columns
ALTER TABLE "Client"
  ADD COLUMN IF NOT EXISTS "phoneNormalized" TEXT NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS "lastActivityAt" TIMESTAMP(3);

ALTER TABLE "Cotizacion"
  ADD COLUMN IF NOT EXISTS "customerPhoneNormalized" TEXT NOT NULL DEFAULT '';

-- 2) Backfill normalization helpers
-- Normalize rule (RD default): keep digits only; if 11 digits and starts with '1', drop leading '1'.
WITH normalized AS (
  SELECT
    id,
    regexp_replace(COALESCE("telefono", ''), '\\D', '', 'g') AS digits
  FROM "Client"
)
UPDATE "Client" c
SET "phoneNormalized" = CASE
  WHEN n.digits = '' THEN ''
  WHEN length(n.digits) = 11 AND left(n.digits, 1) = '1' THEN right(n.digits, 10)
  ELSE n.digits
END
FROM normalized n
WHERE c.id = n.id;

WITH normalized_cot AS (
  SELECT
    id,
    regexp_replace(COALESCE("customerPhone", ''), '\\D', '', 'g') AS digits
  FROM "Cotizacion"
)
UPDATE "Cotizacion" co
SET "customerPhoneNormalized" = CASE
  WHEN n.digits = '' THEN ''
  WHEN length(n.digits) = 11 AND left(n.digits, 1) = '1' THEN right(n.digits, 10)
  ELSE n.digits
END
FROM normalized_cot n
WHERE co.id = n.id;

-- 3) Deduplicate active clients by phoneNormalized (reassign relations, then soft-delete duplicates)
-- Canonical pick: earliest createdAt, then smallest UUID.
WITH dups AS (
  SELECT
    "phoneNormalized",
    array_agg(id ORDER BY "createdAt" ASC, id ASC) AS ids
  FROM "Client"
  WHERE "isDeleted" = false AND "phoneNormalized" <> ''
  GROUP BY "phoneNormalized"
  HAVING COUNT(*) > 1
), mapping AS (
  SELECT
    d."phoneNormalized" AS phone_normalized,
    d.ids[1] AS canonical_id,
    unnest(d.ids[2:]) AS duplicate_id
  FROM dups d
)
UPDATE "Sale" s
SET "customerId" = m.canonical_id
FROM mapping m
WHERE s."customerId" = m.duplicate_id;

WITH dups AS (
  SELECT
    "phoneNormalized",
    array_agg(id ORDER BY "createdAt" ASC, id ASC) AS ids
  FROM "Client"
  WHERE "isDeleted" = false AND "phoneNormalized" <> ''
  GROUP BY "phoneNormalized"
  HAVING COUNT(*) > 1
), mapping AS (
  SELECT
    d.ids[1] AS canonical_id,
    unnest(d.ids[2:]) AS duplicate_id
  FROM dups d
)
UPDATE "Service" sv
SET "customerId" = m.canonical_id
FROM mapping m
WHERE sv."customerId" = m.duplicate_id;

WITH dups AS (
  SELECT
    "phoneNormalized",
    array_agg(id ORDER BY "createdAt" ASC, id ASC) AS ids
  FROM "Client"
  WHERE "isDeleted" = false AND "phoneNormalized" <> ''
  GROUP BY "phoneNormalized"
  HAVING COUNT(*) > 1
), mapping AS (
  SELECT
    d.ids[1] AS canonical_id,
    unnest(d.ids[2:]) AS duplicate_id
  FROM dups d
)
UPDATE "Cotizacion" co
SET "customerId" = m.canonical_id
FROM mapping m
WHERE co."customerId" = m.duplicate_id;

WITH dups AS (
  SELECT
    "phoneNormalized",
    array_agg(id ORDER BY "createdAt" ASC, id ASC) AS ids
  FROM "Client"
  WHERE "isDeleted" = false AND "phoneNormalized" <> ''
  GROUP BY "phoneNormalized"
  HAVING COUNT(*) > 1
), mapping AS (
  SELECT
    d.ids[1] AS canonical_id,
    unnest(d.ids[2:]) AS duplicate_id
  FROM dups d
)
UPDATE "Client" c
SET "isDeleted" = true,
    "updatedAt" = now()
FROM mapping m
WHERE c.id = m.duplicate_id;

-- 4) Link legacy cotizaciones (customerId null) by normalized phone
UPDATE "Cotizacion" co
SET "customerId" = c.id
FROM "Client" c
WHERE co."customerId" IS NULL
  AND c."isDeleted" = false
  AND co."customerPhoneNormalized" <> ''
  AND c."phoneNormalized" = co."customerPhoneNormalized";

-- 5) Backfill lastActivityAt (best-effort)
UPDATE "Client" c
SET "lastActivityAt" = GREATEST(
  COALESCE((SELECT MAX(s."saleDate") FROM "Sale" s WHERE s."customerId" = c.id AND s."isDeleted" = false), '1970-01-01'::timestamp),
  COALESCE((SELECT MAX(sv."updatedAt") FROM "Service" sv WHERE sv."customerId" = c.id AND sv."isDeleted" = false), '1970-01-01'::timestamp),
  COALESCE((SELECT MAX(co."updatedAt") FROM "Cotizacion" co WHERE co."customerId" = c.id), '1970-01-01'::timestamp),
  COALESCE(c."updatedAt", c."createdAt")
);

-- 6) Indexes (fast phone search) + enforce no duplicates for active clients
CREATE INDEX IF NOT EXISTS "idx_client_phone_normalized" ON "Client"("phoneNormalized");
CREATE INDEX IF NOT EXISTS "idx_client_last_activity" ON "Client"("lastActivityAt");
CREATE INDEX IF NOT EXISTS "idx_cotizacion_customer_phone_normalized" ON "Cotizacion"("customerPhoneNormalized");

-- Unique constraint for active non-empty normalized phone.
-- This guarantees no duplicates moving forward.
DO $$
BEGIN
  CREATE UNIQUE INDEX "uq_client_phone_normalized_active"
  ON "Client" ("phoneNormalized")
  WHERE "isDeleted" = false AND "phoneNormalized" <> '';
EXCEPTION
  WHEN duplicate_table THEN NULL;
END $$;
