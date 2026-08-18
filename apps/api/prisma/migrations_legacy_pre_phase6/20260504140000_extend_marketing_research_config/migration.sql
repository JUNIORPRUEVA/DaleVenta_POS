-- Extend marketing_research_configs with full company profile fields
ALTER TABLE "marketing_research_configs" ADD COLUMN IF NOT EXISTS "phone" TEXT;
ALTER TABLE "marketing_research_configs" ADD COLUMN IF NOT EXISTS "address" TEXT;
ALTER TABLE "marketing_research_configs" ADD COLUMN IF NOT EXISTS "city" TEXT NOT NULL DEFAULT 'Higüey';
ALTER TABLE "marketing_research_configs" ADD COLUMN IF NOT EXISTS "province" TEXT NOT NULL DEFAULT 'La Altagracia';
ALTER TABLE "marketing_research_configs" ADD COLUMN IF NOT EXISTS "country" TEXT NOT NULL DEFAULT 'República Dominicana';
ALTER TABLE "marketing_research_configs" ADD COLUMN IF NOT EXISTS "latitude" DOUBLE PRECISION;
ALTER TABLE "marketing_research_configs" ADD COLUMN IF NOT EXISTS "longitude" DOUBLE PRECISION;
ALTER TABLE "marketing_research_configs" ADD COLUMN IF NOT EXISTS "service_radius_km" INTEGER NOT NULL DEFAULT 25;
ALTER TABLE "marketing_research_configs" ADD COLUMN IF NOT EXISTS "service_zones" TEXT[] NOT NULL DEFAULT '{}';
ALTER TABLE "marketing_research_configs" ADD COLUMN IF NOT EXISTS "default_cta" TEXT;
ALTER TABLE "marketing_research_configs" ADD COLUMN IF NOT EXISTS "brand_colors" TEXT[] NOT NULL DEFAULT '{}';
ALTER TABLE "marketing_research_configs" ADD COLUMN IF NOT EXISTS "business_hours" TEXT;
ALTER TABLE "marketing_research_configs" ADD COLUMN IF NOT EXISTS "internal_notes" TEXT;
