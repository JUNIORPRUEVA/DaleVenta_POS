ALTER TABLE "marketing_daily_stories"
ADD COLUMN IF NOT EXISTS "publish_error_code" TEXT,
ADD COLUMN IF NOT EXISTS "publish_error_details" JSONB;
