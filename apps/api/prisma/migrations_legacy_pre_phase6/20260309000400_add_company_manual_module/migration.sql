DO $$
BEGIN
  CREATE TYPE "CompanyManualEntryKind" AS ENUM (
    'GENERAL_RULE',
    'ROLE_RULE',
    'POLICY',
    'WARRANTY_POLICY',
    'RESPONSIBILITY',
    'PRODUCT_SERVICE',
    'PRICE_RULE',
    'SERVICE_RULE',
    'MODULE_GUIDE'
  );
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

DO $$
BEGIN
  CREATE TYPE "CompanyManualAudience" AS ENUM ('GENERAL', 'ROLE_SPECIFIC');
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

CREATE TABLE IF NOT EXISTS "CompanyManualEntry" (
  "id" UUID NOT NULL DEFAULT gen_random_uuid(),
  "ownerId" UUID NOT NULL,
  "title" TEXT NOT NULL,
  "summary" TEXT,
  "content" TEXT NOT NULL,
  "kind" "CompanyManualEntryKind" NOT NULL,
  "audience" "CompanyManualAudience" NOT NULL DEFAULT 'GENERAL',
  "targetRoles" "Role"[] NOT NULL DEFAULT ARRAY[]::"Role"[],
  "moduleKey" TEXT,
  "published" BOOLEAN NOT NULL DEFAULT true,
  "sortOrder" INTEGER NOT NULL DEFAULT 0,
  "createdByUserId" UUID NOT NULL,
  "updatedByUserId" UUID,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "CompanyManualEntry_pkey" PRIMARY KEY ("id")
);

CREATE INDEX IF NOT EXISTS "CompanyManualEntry_ownerId_idx"
  ON "CompanyManualEntry"("ownerId");

CREATE INDEX IF NOT EXISTS "CompanyManualEntry_ownerId_published_idx"
  ON "CompanyManualEntry"("ownerId", "published");

CREATE INDEX IF NOT EXISTS "CompanyManualEntry_ownerId_kind_idx"
  ON "CompanyManualEntry"("ownerId", "kind");

CREATE INDEX IF NOT EXISTS "CompanyManualEntry_ownerId_audience_idx"
  ON "CompanyManualEntry"("ownerId", "audience");

CREATE INDEX IF NOT EXISTS "CompanyManualEntry_updatedAt_idx"
  ON "CompanyManualEntry"("updatedAt");