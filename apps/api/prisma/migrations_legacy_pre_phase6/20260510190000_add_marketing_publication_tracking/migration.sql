ALTER TABLE "marketing_daily_stories"
ADD COLUMN IF NOT EXISTS "published_at" TIMESTAMP(3),
ADD COLUMN IF NOT EXISTS "facebook_post_id" TEXT,
ADD COLUMN IF NOT EXISTS "instagram_post_id" TEXT,
ADD COLUMN IF NOT EXISTS "publish_status" TEXT NOT NULL DEFAULT 'PENDING',
ADD COLUMN IF NOT EXISTS "publish_error" TEXT,
ADD COLUMN IF NOT EXISTS "retry_count" INTEGER NOT NULL DEFAULT 0;

CREATE INDEX IF NOT EXISTS "marketing_daily_stories_company_publish_status_idx"
  ON "marketing_daily_stories" ("company_id", "publish_status");
