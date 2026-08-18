-- CreateEnum (idempotent)
DO $$ BEGIN
  CREATE TYPE "marketing_research_status" AS ENUM ('DRAFT', 'APPROVED', 'REJECTED', 'USED');
EXCEPTION WHEN duplicate_object THEN null; END $$;

-- CreateEnum (idempotent)
DO $$ BEGIN
  CREATE TYPE "marketing_learning_status" AS ENUM ('ACTIVE', 'DISCARDED');
EXCEPTION WHEN duplicate_object THEN null; END $$;

-- AlterTable: add research_id to marketing_daily_stories (idempotent)
DO $$ BEGIN
  ALTER TABLE "marketing_daily_stories" ADD COLUMN "research_id" UUID;
EXCEPTION WHEN duplicate_column THEN null; END $$;

-- CreateTable
CREATE TABLE IF NOT EXISTS "marketing_research_configs" (
    "id" UUID NOT NULL,
    "company_id" UUID NOT NULL,
    "default_research_prompt" TEXT NOT NULL,
    "business_name" TEXT NOT NULL DEFAULT 'FULLTECH SRL',
    "business_location" TEXT NOT NULL DEFAULT 'Higüey, La Altagracia, República Dominicana',
    "business_description" TEXT,
    "main_services" TEXT[] DEFAULT ARRAY[]::TEXT[],
    "priority_services" TEXT[] DEFAULT ARRAY[]::TEXT[],
    "target_market" TEXT,
    "brand_tone" TEXT NOT NULL DEFAULT 'Profesional, confiable, claro, dominicano, directo, moderno, orientado a ventas.',
    "learning_enabled" BOOLEAN NOT NULL DEFAULT true,
    "research_frequency_days" INTEGER NOT NULL DEFAULT 2,
    "require_approval" BOOLEAN NOT NULL DEFAULT false,
    "updated_by_user_id" UUID,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "marketing_research_configs_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE IF NOT EXISTS "marketing_researches" (
    "id" UUID NOT NULL,
    "company_id" UUID NOT NULL,
    "date" DATE NOT NULL,
    "research_prompt" TEXT NOT NULL,
    "business_snapshot" JSONB,
    "country" TEXT NOT NULL DEFAULT 'República Dominicana',
    "city" TEXT NOT NULL DEFAULT 'Higüey',
    "main_focus" TEXT,
    "services_analyzed" JSONB,
    "market_summary" TEXT,
    "competitor_publishing_patterns" TEXT,
    "common_offers" TEXT,
    "observed_price_ranges" TEXT,
    "strong_angles" JSONB,
    "weak_angles" JSONB,
    "content_opportunities" TEXT,
    "recommended_products" JSONB,
    "recommended_content_types" JSONB,
    "recommended_offers" JSONB,
    "recommended_hooks" JSONB,
    "recommended_ctas" JSONB,
    "do_more_of_this" JSONB,
    "avoid_this" JSONB,
    "confidence_score" DOUBLE PRECISION NOT NULL DEFAULT 0.5,
    "data_sources" JSONB,
    "status" "marketing_research_status" NOT NULL DEFAULT 'DRAFT',
    "forced_by_user_id" UUID,
    "approved_by_user_id" UUID,
    "approved_at" TIMESTAMP(3),
    "rejected_at" TIMESTAMP(3),
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "marketing_researches_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE IF NOT EXISTS "marketing_learning_memories" (
    "id" UUID NOT NULL,
    "company_id" UUID NOT NULL,
    "category" TEXT NOT NULL,
    "insight" TEXT NOT NULL,
    "source_research_id" UUID,
    "score" DOUBLE PRECISION NOT NULL DEFAULT 1.0,
    "status" "marketing_learning_status" NOT NULL DEFAULT 'ACTIVE',
    "reason" TEXT,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "marketing_learning_memories_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX IF NOT EXISTS "marketing_research_configs_company_id_key" ON "marketing_research_configs"("company_id");

-- CreateIndex
CREATE INDEX IF NOT EXISTS "marketing_researches_company_id_date_status_idx" ON "marketing_researches"("company_id", "date", "status");

-- CreateIndex
CREATE INDEX IF NOT EXISTS "marketing_researches_company_id_status_created_at_idx" ON "marketing_researches"("company_id", "status", "created_at");

-- CreateIndex
CREATE INDEX IF NOT EXISTS "marketing_learning_memories_company_id_category_status_idx" ON "marketing_learning_memories"("company_id", "category", "status");

-- CreateIndex
CREATE INDEX IF NOT EXISTS "marketing_learning_memories_company_id_score_idx" ON "marketing_learning_memories"("company_id", "score" DESC);

-- AddForeignKey (idempotent)
DO $$ BEGIN
  ALTER TABLE "marketing_research_configs" ADD CONSTRAINT "marketing_research_configs_updated_by_user_id_fkey" FOREIGN KEY ("updated_by_user_id") REFERENCES "users"("id") ON DELETE SET NULL ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN null; END $$;

-- AddForeignKey (idempotent)
DO $$ BEGIN
  ALTER TABLE "marketing_researches" ADD CONSTRAINT "marketing_researches_forced_by_user_id_fkey" FOREIGN KEY ("forced_by_user_id") REFERENCES "users"("id") ON DELETE SET NULL ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN null; END $$;

-- AddForeignKey (idempotent)
DO $$ BEGIN
  ALTER TABLE "marketing_researches" ADD CONSTRAINT "marketing_researches_approved_by_user_id_fkey" FOREIGN KEY ("approved_by_user_id") REFERENCES "users"("id") ON DELETE SET NULL ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN null; END $$;

-- AddForeignKey (idempotent)
DO $$ BEGIN
  ALTER TABLE "marketing_learning_memories" ADD CONSTRAINT "marketing_learning_memories_source_research_id_fkey" FOREIGN KEY ("source_research_id") REFERENCES "marketing_researches"("id") ON DELETE SET NULL ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN null; END $$;

-- AddForeignKey (idempotent)
DO $$ BEGIN
  ALTER TABLE "marketing_daily_stories" ADD CONSTRAINT "marketing_daily_stories_research_id_fkey" FOREIGN KEY ("research_id") REFERENCES "marketing_researches"("id") ON DELETE SET NULL ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN null; END $$;
