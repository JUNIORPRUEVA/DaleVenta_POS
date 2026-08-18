-- Add Order fields to Service (tipo_orden, estado, tecnico_id)

DO $$
BEGIN
  CREATE TYPE "OrderType" AS ENUM ('RESERVA', 'SERVICIO', 'LEVANTAMIENTO', 'GARANTIA');
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

DO $$
BEGIN
  CREATE TYPE "OrderState" AS ENUM ('PENDING', 'CONFIRMED', 'ASSIGNED', 'IN_PROGRESS', 'FINALIZED', 'CANCELLED', 'RESCHEDULED');
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

ALTER TABLE "Service"
  ADD COLUMN IF NOT EXISTS "orderType" "OrderType" NOT NULL DEFAULT 'RESERVA',
  ADD COLUMN IF NOT EXISTS "orderState" "OrderState" NOT NULL DEFAULT 'PENDING',
  ADD COLUMN IF NOT EXISTS "technicianId" UUID;

CREATE INDEX IF NOT EXISTS "Service_orderType_idx" ON "Service"("orderType");
CREATE INDEX IF NOT EXISTS "Service_orderState_idx" ON "Service"("orderState");
CREATE INDEX IF NOT EXISTS "Service_technicianId_idx" ON "Service"("technicianId");

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'Service_technicianId_fkey'
  ) THEN
    ALTER TABLE "Service"
      ADD CONSTRAINT "Service_technicianId_fkey"
      FOREIGN KEY ("technicianId") REFERENCES "users"("id") ON DELETE SET NULL ON UPDATE CASCADE;
  END IF;
END $$;
