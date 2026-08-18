-- Extend OrderType enum to support additional order kinds

DO $$
BEGIN
  ALTER TYPE "OrderType" ADD VALUE 'MANTENIMIENTO';
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

DO $$
BEGIN
  ALTER TYPE "OrderType" ADD VALUE 'INSTALACION';
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;
