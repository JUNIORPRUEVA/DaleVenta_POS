-- Add admin-only phase/status fields to Service

DO $$
BEGIN
  CREATE TYPE "AdminOrderPhase" AS ENUM (
    'RESERVA',
    'CONFIRMACION',
    'PROGRAMACION',
    'EJECUCION',
    'REVISION',
    'FACTURACION',
    'CIERRE',
    'CANCELADA'
  );
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

DO $$
BEGIN
  CREATE TYPE "AdminOrderStatus" AS ENUM (
    'PENDIENTE',
    'CONFIRMADA',
    'ASIGNADA',
    'EN_CAMINO',
    'EN_PROCESO',
    'FINALIZADA',
    'REAGENDADA',
    'CANCELADA',
    'CERRADA'
  );
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

ALTER TABLE "Service"
  ADD COLUMN IF NOT EXISTS "adminPhase" "AdminOrderPhase",
  ADD COLUMN IF NOT EXISTS "adminStatus" "AdminOrderStatus";

CREATE INDEX IF NOT EXISTS "Service_adminPhase_idx" ON "Service"("adminPhase");
CREATE INDEX IF NOT EXISTS "Service_adminStatus_idx" ON "Service"("adminStatus");
