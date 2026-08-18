-- Add Service phases and phase history

DO $$
BEGIN
  CREATE TYPE "ServicePhaseType" AS ENUM ('RESERVA', 'LEVANTAMIENTO', 'INSTALACION', 'MANTENIMIENTO', 'GARANTIA');
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

ALTER TABLE "Service"
  ADD COLUMN IF NOT EXISTS "currentPhase" "ServicePhaseType" NOT NULL DEFAULT 'RESERVA';

CREATE INDEX IF NOT EXISTS "Service_currentPhase_idx" ON "Service"("currentPhase");

CREATE TABLE IF NOT EXISTS "ServicePhaseHistory" (
  "id" UUID NOT NULL DEFAULT gen_random_uuid(),
  "serviceId" UUID NOT NULL,
  "phase" "ServicePhaseType" NOT NULL,
  "note" TEXT,
  "changedByUserId" UUID NOT NULL,
  "changedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "fromPhase" "ServicePhaseType",
  "toPhase" "ServicePhaseType",
  CONSTRAINT "ServicePhaseHistory_pkey" PRIMARY KEY ("id")
);

CREATE INDEX IF NOT EXISTS "ServicePhaseHistory_serviceId_changedAt_idx" ON "ServicePhaseHistory"("serviceId", "changedAt");
CREATE INDEX IF NOT EXISTS "ServicePhaseHistory_changedByUserId_idx" ON "ServicePhaseHistory"("changedByUserId");

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'ServicePhaseHistory_serviceId_fkey'
  ) THEN
    ALTER TABLE "ServicePhaseHistory"
      ADD CONSTRAINT "ServicePhaseHistory_serviceId_fkey"
      FOREIGN KEY ("serviceId") REFERENCES "Service"("id") ON DELETE CASCADE ON UPDATE CASCADE;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'ServicePhaseHistory_changedByUserId_fkey'
  ) THEN
    ALTER TABLE "ServicePhaseHistory"
      ADD CONSTRAINT "ServicePhaseHistory_changedByUserId_fkey"
      FOREIGN KEY ("changedByUserId") REFERENCES "users"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
  END IF;
END $$;

-- Backfill initial history for existing services (only if not present)
INSERT INTO "ServicePhaseHistory" ("serviceId", "phase", "note", "changedByUserId", "changedAt", "fromPhase", "toPhase")
SELECT
  s."id",
  s."currentPhase",
  'Fase inicial automática',
  s."createdByUserId",
  COALESCE(s."createdAt", CURRENT_TIMESTAMP),
  NULL,
  s."currentPhase"
FROM "Service" s
WHERE NOT EXISTS (
  SELECT 1 FROM "ServicePhaseHistory" h WHERE h."serviceId" = s."id"
);
