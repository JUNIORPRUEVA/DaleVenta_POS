-- Add multi-tenant and soft-delete support to Client

-- Add columns (ownerId nullable first for backfill safety)
ALTER TABLE "Client"
  ADD COLUMN IF NOT EXISTS "ownerId" UUID,
  ADD COLUMN IF NOT EXISTS "isDeleted" BOOLEAN NOT NULL DEFAULT false;

-- Backfill ownerId using earliest existing user (if any)
UPDATE "Client"
SET "ownerId" = (
  SELECT "id"
  FROM "User"
  ORDER BY "createdAt" ASC
  LIMIT 1
)
WHERE "ownerId" IS NULL;

-- Enforce ownerId required
ALTER TABLE "Client"
  ALTER COLUMN "ownerId" SET NOT NULL;

-- Add FK (idempotent-safe)
DO $$
BEGIN
  ALTER TABLE "Client"
  ADD CONSTRAINT "Client_ownerId_fkey"
  FOREIGN KEY ("ownerId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

-- Indexes for scoped search/list
CREATE INDEX IF NOT EXISTS "idx_clientes_owner" ON "Client"("ownerId");
CREATE INDEX IF NOT EXISTS "idx_clientes_owner_nombre" ON "Client"("ownerId", "nombre");
CREATE INDEX IF NOT EXISTS "idx_clientes_owner_telefono" ON "Client"("ownerId", "telefono");
