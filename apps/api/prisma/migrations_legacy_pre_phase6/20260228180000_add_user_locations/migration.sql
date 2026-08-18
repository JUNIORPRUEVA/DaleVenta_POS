-- CreateTable
CREATE TABLE IF NOT EXISTS "user_locations" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "userId" UUID NOT NULL,
    "latitude" DOUBLE PRECISION NOT NULL,
    "longitude" DOUBLE PRECISION NOT NULL,
    "accuracyMeters" DOUBLE PRECISION,
    "altitudeMeters" DOUBLE PRECISION,
    "headingDegrees" DOUBLE PRECISION,
    "speedMps" DOUBLE PRECISION,
    "recordedAt" TIMESTAMP(3),
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "user_locations_pkey" PRIMARY KEY ("id")
);

-- Indexes
CREATE UNIQUE INDEX IF NOT EXISTS "user_locations_userId_key" ON "user_locations"("userId");
CREATE INDEX IF NOT EXISTS "user_locations_updatedAt_idx" ON "user_locations"("updatedAt");

-- ForeignKeys
DO $$
BEGIN
  ALTER TABLE "user_locations"
    ADD CONSTRAINT "user_locations_userId_fkey"
    FOREIGN KEY ("userId") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;
