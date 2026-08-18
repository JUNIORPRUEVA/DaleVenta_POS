-- CreateEnum
CREATE TYPE "marketing_story_type" AS ENUM ('SALES', 'TRUST', 'EDUCATIONAL');

-- CreateEnum
CREATE TYPE "marketing_story_status" AS ENUM ('PENDING', 'APPROVED', 'REJECTED', 'REGENERATED');

-- CreateTable
CREATE TABLE "marketing_flow_configs" (
    "id" UUID NOT NULL,
    "company_id" UUID NOT NULL,
    "active" BOOLEAN NOT NULL DEFAULT false,
    "paused" BOOLEAN NOT NULL DEFAULT false,
    "daily_stories_count" INTEGER NOT NULL DEFAULT 3,
    "generation_time" TEXT NOT NULL DEFAULT '08:00',
    "auto_regenerate" BOOLEAN NOT NULL DEFAULT false,
    "regenerate_after_hours" INTEGER NOT NULL DEFAULT 6,
    "target_city" TEXT,
    "brand_tone" TEXT,
    "priority_products" TEXT[] DEFAULT ARRAY[]::TEXT[],
    "updated_by_user_id" UUID,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "marketing_flow_configs_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "marketing_daily_stories" (
    "id" UUID NOT NULL,
    "company_id" UUID NOT NULL,
    "date" DATE NOT NULL,
    "type" "marketing_story_type" NOT NULL,
    "title" TEXT NOT NULL,
    "short_text" TEXT NOT NULL,
    "long_text" TEXT,
    "hashtags" TEXT[] DEFAULT ARRAY[]::TEXT[],
    "image_prompt" TEXT,
    "image_url" TEXT,
    "status" "marketing_story_status" NOT NULL DEFAULT 'PENDING',
    "generation_attempt" INTEGER NOT NULL DEFAULT 1,
    "approved_by_user_id" UUID,
    "approved_at" TIMESTAMP(3),
    "rejected_at" TIMESTAMP(3),
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "marketing_daily_stories_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "marketing_activity_logs" (
    "id" UUID NOT NULL,
    "company_id" UUID NOT NULL,
    "action" TEXT NOT NULL,
    "description" TEXT NOT NULL,
    "user_id" UUID,
    "metadata" JSONB,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "marketing_activity_logs_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "marketing_flow_configs_company_id_key" ON "marketing_flow_configs"("company_id");

-- CreateIndex
CREATE INDEX "marketing_flow_configs_company_id_active_idx" ON "marketing_flow_configs"("company_id", "active");

-- CreateIndex
CREATE UNIQUE INDEX "marketing_daily_stories_company_id_date_type_key" ON "marketing_daily_stories"("company_id", "date", "type");

-- CreateIndex
CREATE INDEX "marketing_daily_stories_company_id_date_status_idx" ON "marketing_daily_stories"("company_id", "date", "status");

-- CreateIndex
CREATE INDEX "marketing_daily_stories_company_id_status_updated_at_idx" ON "marketing_daily_stories"("company_id", "status", "updated_at");

-- CreateIndex
CREATE INDEX "marketing_activity_logs_company_id_created_at_idx" ON "marketing_activity_logs"("company_id", "created_at");

-- CreateIndex
CREATE INDEX "marketing_activity_logs_company_id_action_idx" ON "marketing_activity_logs"("company_id", "action");

-- AddForeignKey
ALTER TABLE "marketing_flow_configs" ADD CONSTRAINT "marketing_flow_configs_updated_by_user_id_fkey" FOREIGN KEY ("updated_by_user_id") REFERENCES "users"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "marketing_daily_stories" ADD CONSTRAINT "marketing_daily_stories_approved_by_user_id_fkey" FOREIGN KEY ("approved_by_user_id") REFERENCES "users"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "marketing_activity_logs" ADD CONSTRAINT "marketing_activity_logs_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE SET NULL ON UPDATE CASCADE;
