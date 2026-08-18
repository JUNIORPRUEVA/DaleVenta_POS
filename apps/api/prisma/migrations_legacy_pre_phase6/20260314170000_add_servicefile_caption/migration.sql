-- Add optional caption/description for ServiceFile (evidence text)

ALTER TABLE IF EXISTS "ServiceFile"
  ADD COLUMN IF NOT EXISTS "caption" text NULL;
