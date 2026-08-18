-- Add orderExtras JSONB for dynamic order fields
ALTER TABLE "Service" ADD COLUMN IF NOT EXISTS "orderExtras" JSONB;
