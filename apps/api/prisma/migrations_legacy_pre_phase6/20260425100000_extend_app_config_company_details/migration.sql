-- AlterTable: extend app_config with company detail fields
ALTER TABLE "app_config"
  ADD COLUMN IF NOT EXISTS "description"        TEXT NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS "phone_preferential" TEXT NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS "instagram_url"      TEXT NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS "facebook_url"       TEXT NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS "website_url"        TEXT NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS "gps_location_url"   TEXT NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS "business_hours"     TEXT NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS "bank_accounts"      JSONB NOT NULL DEFAULT '[]';
