DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_type
    WHERE typname = 'crm_commercial_library_item_type'
  ) THEN
    CREATE TYPE "crm_commercial_library_item_type" AS ENUM (
      'TEXT',
      'IMAGE',
      'VIDEO',
      'AUDIO',
      'DOCUMENT',
      'LOCATION',
      'BANK_ACCOUNT',
      'BUSINESS_HOURS',
      'CATALOG',
      'QUOTE_TEMPLATE',
      'LINK',
      'PROMOTION',
      'WARRANTY',
      'FAQ',
      'FOLLOW_UP'
    );
  END IF;
END $$;

CREATE TABLE IF NOT EXISTS "crm_commercial_library_items" (
  "id" UUID NOT NULL,
  "company_id" UUID NOT NULL,
  "title" TEXT NOT NULL,
  "description" TEXT,
  "type" "crm_commercial_library_item_type" NOT NULL,
  "content_text" TEXT,
  "media_url" TEXT,
  "file_name" TEXT,
  "mime_type" TEXT,
  "latitude" DECIMAL(10,7),
  "longitude" DECIMAL(10,7),
  "external_url" TEXT,
  "category" TEXT,
  "tags" TEXT[] NOT NULL DEFAULT ARRAY[]::TEXT[],
  "is_active" BOOLEAN NOT NULL DEFAULT true,
  "sort_order" INTEGER NOT NULL DEFAULT 0,
  "created_by_user_id" UUID NOT NULL,
  "updated_by_user_id" UUID NOT NULL,
  "use_count" INTEGER NOT NULL DEFAULT 0,
  "last_used_at" TIMESTAMP(3),
  "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updated_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

  CONSTRAINT "crm_commercial_library_items_pkey" PRIMARY KEY ("id")
);

CREATE INDEX IF NOT EXISTS "crm_commercial_library_items_company_id_is_active_sort_order_idx"
  ON "crm_commercial_library_items"("company_id", "is_active", "sort_order");

CREATE INDEX IF NOT EXISTS "crm_commercial_library_items_company_id_type_is_active_idx"
  ON "crm_commercial_library_items"("company_id", "type", "is_active");

CREATE INDEX IF NOT EXISTS "crm_commercial_library_items_company_id_category_is_active_idx"
  ON "crm_commercial_library_items"("company_id", "category", "is_active");

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM information_schema.table_constraints
    WHERE constraint_name = 'crm_commercial_library_items_created_by_user_id_fkey'
      AND table_name = 'crm_commercial_library_items'
  ) THEN
    ALTER TABLE "crm_commercial_library_items"
      ADD CONSTRAINT "crm_commercial_library_items_created_by_user_id_fkey"
      FOREIGN KEY ("created_by_user_id") REFERENCES "users"("id")
      ON DELETE RESTRICT ON UPDATE CASCADE;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM information_schema.table_constraints
    WHERE constraint_name = 'crm_commercial_library_items_updated_by_user_id_fkey'
      AND table_name = 'crm_commercial_library_items'
  ) THEN
    ALTER TABLE "crm_commercial_library_items"
      ADD CONSTRAINT "crm_commercial_library_items_updated_by_user_id_fkey"
      FOREIGN KEY ("updated_by_user_id") REFERENCES "users"("id")
      ON DELETE RESTRICT ON UPDATE CASCADE;
  END IF;
END $$;
