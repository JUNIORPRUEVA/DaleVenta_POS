DO $$ BEGIN
  CREATE TYPE "marketing_campaign_status" AS ENUM ('DRAFT','READY','PUBLISHING','ACTIVE','PAUSED','ERROR','REJECTED');
EXCEPTION WHEN duplicate_object THEN null;
END $$;

DO $$ BEGIN
  CREATE TYPE "marketing_campaign_phase" AS ENUM ('DESIGN','COPY_SEGMENTATION','PUBLISH');
EXCEPTION WHEN duplicate_object THEN null;
END $$;

DO $$ BEGIN
  CREATE TYPE "marketing_campaign_type" AS ENUM ('META_ADS');
EXCEPTION WHEN duplicate_object THEN null;
END $$;

DO $$ BEGIN
  CREATE TYPE "marketing_campaign_currency" AS ENUM ('DOP','USD');
EXCEPTION WHEN duplicate_object THEN null;
END $$;

CREATE TABLE IF NOT EXISTS "marketing_ad_campaigns" (
  "id" UUID NOT NULL DEFAULT gen_random_uuid(),
  "company_id" UUID NOT NULL,
  "date" DATE NOT NULL,
  "campaign_type" "marketing_campaign_type" NOT NULL DEFAULT 'META_ADS',
  "status" "marketing_campaign_status" NOT NULL DEFAULT 'DRAFT',
  "phase" "marketing_campaign_phase" NOT NULL DEFAULT 'DESIGN',
  "base_image_url" TEXT,
  "final_design_url" TEXT,
  "gallery_asset_id" UUID,
  "headline" TEXT,
  "primary_text" TEXT,
  "description" TEXT,
  "cta" TEXT,
  "hashtags" TEXT[] NOT NULL DEFAULT ARRAY[]::TEXT[],
  "ai_angle" TEXT,
  "ai_research_id" UUID,
  "recommended_audience_json" JSONB,
  "final_audience_json" JSONB,
  "daily_budget" DECIMAL(12,2),
  "total_budget" DECIMAL(12,2),
  "currency" "marketing_campaign_currency" NOT NULL DEFAULT 'DOP',
  "whatsapp_phone" TEXT,
  "whatsapp_message_template" TEXT,
  "destination_url" TEXT,
  "start_time" TIMESTAMP(3),
  "end_time" TIMESTAMP(3),
  "keep_running_until_paused" BOOLEAN NOT NULL DEFAULT true,
  "meta_campaign_id" TEXT,
  "meta_ad_set_id" TEXT,
  "meta_creative_id" TEXT,
  "meta_ad_id" TEXT,
  "meta_status" TEXT,
  "meta_error" TEXT,
  "meta_error_code" TEXT,
  "meta_error_subcode" TEXT,
  "fbtrace_id" TEXT,
  "created_by_user_id" UUID,
  "updated_by_user_id" UUID,
  "published_at" TIMESTAMP(3),
  "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updated_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "marketing_ad_campaigns_pkey" PRIMARY KEY ("id")
);

CREATE INDEX IF NOT EXISTS "marketing_ad_campaigns_company_id_date_idx"
  ON "marketing_ad_campaigns"("company_id", "date");
CREATE INDEX IF NOT EXISTS "marketing_ad_campaigns_company_id_status_updated_at_idx"
  ON "marketing_ad_campaigns"("company_id", "status", "updated_at");
CREATE INDEX IF NOT EXISTS "marketing_ad_campaigns_company_id_phase_updated_at_idx"
  ON "marketing_ad_campaigns"("company_id", "phase", "updated_at");
CREATE INDEX IF NOT EXISTS "marketing_ad_campaigns_gallery_asset_id_idx"
  ON "marketing_ad_campaigns"("gallery_asset_id");
CREATE INDEX IF NOT EXISTS "marketing_ad_campaigns_ai_research_id_idx"
  ON "marketing_ad_campaigns"("ai_research_id");

DO $$ BEGIN
  ALTER TABLE "marketing_ad_campaigns"
  ADD CONSTRAINT "marketing_ad_campaigns_gallery_asset_id_fkey"
  FOREIGN KEY ("gallery_asset_id") REFERENCES "marketing_media_assets"("id")
  ON DELETE SET NULL ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN null;
END $$;

DO $$ BEGIN
  ALTER TABLE "marketing_ad_campaigns"
  ADD CONSTRAINT "marketing_ad_campaigns_ai_research_id_fkey"
  FOREIGN KEY ("ai_research_id") REFERENCES "marketing_researches"("id")
  ON DELETE SET NULL ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN null;
END $$;

DO $$ BEGIN
  ALTER TABLE "marketing_ad_campaigns"
  ADD CONSTRAINT "marketing_ad_campaigns_created_by_user_id_fkey"
  FOREIGN KEY ("created_by_user_id") REFERENCES "users"("id")
  ON DELETE SET NULL ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN null;
END $$;

DO $$ BEGIN
  ALTER TABLE "marketing_ad_campaigns"
  ADD CONSTRAINT "marketing_ad_campaigns_updated_by_user_id_fkey"
  FOREIGN KEY ("updated_by_user_id") REFERENCES "users"("id")
  ON DELETE SET NULL ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN null;
END $$;
