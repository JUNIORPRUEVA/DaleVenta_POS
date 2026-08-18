-- Add for_publicidad flag to service_evidences
ALTER TABLE "service_evidences" ADD COLUMN IF NOT EXISTS "for_publicidad" BOOLEAN NOT NULL DEFAULT false;

CREATE INDEX IF NOT EXISTS "service_evidences_for_publicidad_idx" ON "service_evidences" ("for_publicidad") WHERE "for_publicidad" = true;
