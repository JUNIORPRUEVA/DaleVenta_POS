DO $$
BEGIN
  CREATE TYPE "service_report_type" AS ENUM (
    'requerimiento_cliente',
    'servicio_finalizado',
    'otros'
  );
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

ALTER TABLE "service_reports"
  ADD COLUMN IF NOT EXISTS "type" "service_report_type" NOT NULL DEFAULT 'otros';

CREATE INDEX IF NOT EXISTS "service_reports_type_idx" ON "service_reports"("type");