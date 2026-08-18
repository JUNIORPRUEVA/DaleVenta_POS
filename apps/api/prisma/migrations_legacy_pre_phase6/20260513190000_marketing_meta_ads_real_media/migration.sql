ALTER TABLE "marketing_ad_campaigns"
ADD COLUMN IF NOT EXISTS "meta_image_hash" TEXT,
ADD COLUMN IF NOT EXISTS "meta_video_id" TEXT,
ADD COLUMN IF NOT EXISTS "meta_media_type" TEXT,
ADD COLUMN IF NOT EXISTS "meta_media_url" TEXT,
ADD COLUMN IF NOT EXISTS "meta_publish_progress_json" JSONB;
