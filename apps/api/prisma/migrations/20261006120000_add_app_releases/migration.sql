CREATE TYPE "app_release_platform" AS ENUM ('WINDOWS', 'ANDROID', 'IOS');

CREATE TYPE "app_release_channel" AS ENUM ('STABLE', 'BETA');

CREATE TYPE "app_release_status" AS ENUM ('DRAFT', 'PUBLISHED', 'REVOKED');

CREATE TABLE "app_releases" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "platform" "app_release_platform" NOT NULL,
    "channel" "app_release_channel" NOT NULL DEFAULT 'STABLE',
    "version" VARCHAR(32) NOT NULL,
    "build_number" INTEGER NOT NULL,
    "status" "app_release_status" NOT NULL DEFAULT 'DRAFT',
    "mandatory" BOOLEAN NOT NULL DEFAULT false,
    "minimum_supported_build" INTEGER,
    "file_name" VARCHAR(255) NOT NULL,
    "file_size" BIGINT NOT NULL,
    "sha256" VARCHAR(64) NOT NULL,
    "download_url" TEXT NOT NULL,
    "release_notes" JSONB NOT NULL DEFAULT '[]',
    "published_at" TIMESTAMP(3),
    "revoked_at" TIMESTAMP(3),
    "commit_sha" VARCHAR(64),
    "signed" BOOLEAN NOT NULL DEFAULT false,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "app_releases_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX "app_releases_platform_channel_build_number_key"
ON "app_releases"("platform", "channel", "build_number");

CREATE INDEX "app_releases_platform_channel_status_build_number_idx"
ON "app_releases"("platform", "channel", "status", "build_number");
