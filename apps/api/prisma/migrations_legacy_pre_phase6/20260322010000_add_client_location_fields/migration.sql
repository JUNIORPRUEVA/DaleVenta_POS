-- Optional GPS location support for clients

ALTER TABLE "Client"
  ADD COLUMN IF NOT EXISTS "latitude" DECIMAL(10,8),
  ADD COLUMN IF NOT EXISTS "longitude" DECIMAL(11,8),
  ADD COLUMN IF NOT EXISTS "location_url" TEXT;

CREATE INDEX IF NOT EXISTS "idx_client_coordinates"
  ON "Client" ("latitude", "longitude");