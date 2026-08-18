DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'marketing_platform_format') THEN
    CREATE TYPE "marketing_platform_format" AS ENUM ('STORY_9_16');
  END IF;
END
$$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'marketing_image_status') THEN
    CREATE TYPE "marketing_image_status" AS ENUM (
      'PENDING',
      'PENDING_MEDIA',
      'GENERATED',
      'GENERATED_PLACEHOLDER',
      'FAILED'
    );
  END IF;
END
$$;

CREATE TABLE IF NOT EXISTS "marketing_media_assets" (
  "id" UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  "company_id" UUID NOT NULL,
  "file_url" TEXT NOT NULL,
  "thumbnail_url" TEXT,
  "file_name" TEXT NOT NULL,
  "mime_type" TEXT NOT NULL,
  "category" TEXT NOT NULL,
  "related_service" TEXT,
  "tags" JSONB,
  "description" TEXT,
  "is_active" BOOLEAN NOT NULL DEFAULT true,
  "is_featured" BOOLEAN NOT NULL DEFAULT false,
  "use_count" INTEGER NOT NULL DEFAULT 0,
  "last_used_at" TIMESTAMP(3),
  "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updated_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP
);

ALTER TABLE "marketing_daily_stories"
  ADD COLUMN IF NOT EXISTS "media_asset_id" UUID,
  ADD COLUMN IF NOT EXISTS "visual_concept" TEXT,
  ADD COLUMN IF NOT EXISTS "design_notes" TEXT,
  ADD COLUMN IF NOT EXISTS "platform_format" "marketing_platform_format" NOT NULL DEFAULT 'STORY_9_16',
  ADD COLUMN IF NOT EXISTS "image_status" "marketing_image_status" NOT NULL DEFAULT 'PENDING',
  ADD COLUMN IF NOT EXISTS "generated_image_url" TEXT,
  ADD COLUMN IF NOT EXISTS "generated_image_provider" TEXT,
  ADD COLUMN IF NOT EXISTS "image_generation_metadata" JSONB,
  ADD COLUMN IF NOT EXISTS "used_research_angle" TEXT,
  ADD COLUMN IF NOT EXISTS "used_offer" TEXT,
  ADD COLUMN IF NOT EXISTS "used_cta" TEXT;

CREATE INDEX IF NOT EXISTS "marketing_media_assets_company_active_featured_idx"
  ON "marketing_media_assets" ("company_id", "is_active", "is_featured");

CREATE INDEX IF NOT EXISTS "marketing_media_assets_company_category_service_idx"
  ON "marketing_media_assets" ("company_id", "category", "related_service");

CREATE INDEX IF NOT EXISTS "marketing_media_assets_company_use_count_last_used_idx"
  ON "marketing_media_assets" ("company_id", "use_count", "last_used_at");

CREATE INDEX IF NOT EXISTS "marketing_daily_stories_company_image_status_date_idx"
  ON "marketing_daily_stories" ("company_id", "image_status", "date");

CREATE INDEX IF NOT EXISTS "marketing_daily_stories_company_media_asset_id_idx"
  ON "marketing_daily_stories" ("company_id", "media_asset_id");

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'marketing_daily_stories_media_asset_id_fkey'
  ) THEN
    ALTER TABLE "marketing_daily_stories"
      ADD CONSTRAINT "marketing_daily_stories_media_asset_id_fkey"
      FOREIGN KEY ("media_asset_id")
      REFERENCES "marketing_media_assets"("id")
      ON DELETE SET NULL
      ON UPDATE CASCADE;
  END IF;
END
$$;
