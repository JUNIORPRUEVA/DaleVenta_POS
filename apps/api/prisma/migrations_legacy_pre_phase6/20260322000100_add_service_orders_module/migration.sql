DO $$
BEGIN
  CREATE TYPE "service_order_category" AS ENUM (
    'camara',
    'motor_porton',
    'alarma',
    'cerco_electrico',
    'intercom',
    'punto_venta'
  );
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

DO $$
BEGIN
  CREATE TYPE "service_order_type" AS ENUM (
    'instalacion',
    'mantenimiento',
    'levantamiento',
    'garantia'
  );
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

DO $$
BEGIN
  CREATE TYPE "service_order_status" AS ENUM (
    'pendiente',
    'en_proceso',
    'finalizado',
    'cancelado'
  );
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

DO $$
BEGIN
  CREATE TYPE "service_evidence_type" AS ENUM (
    'texto',
    'imagen',
    'video'
  );
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

CREATE TABLE "service_orders" (
  "id" UUID NOT NULL DEFAULT gen_random_uuid(),
  "client_id" UUID NOT NULL,
  "quotation_id" UUID NOT NULL,
  "category" "service_order_category" NOT NULL,
  "service_type" "service_order_type" NOT NULL,
  "status" "service_order_status" NOT NULL DEFAULT 'pendiente',
  "technical_note" TEXT,
  "extra_requirements" TEXT,
  "parent_order_id" UUID,
  "created_by" UUID NOT NULL,
  "assigned_to" UUID,
  "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updated_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

  CONSTRAINT "service_orders_pkey" PRIMARY KEY ("id")
);

CREATE TABLE "service_evidences" (
  "id" UUID NOT NULL DEFAULT gen_random_uuid(),
  "service_order_id" UUID NOT NULL,
  "type" "service_evidence_type" NOT NULL,
  "content" TEXT NOT NULL,
  "created_by" UUID NOT NULL,
  "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

  CONSTRAINT "service_evidences_pkey" PRIMARY KEY ("id")
);

CREATE TABLE "service_reports" (
  "id" UUID NOT NULL DEFAULT gen_random_uuid(),
  "service_order_id" UUID NOT NULL,
  "report" TEXT NOT NULL,
  "created_by" UUID NOT NULL,
  "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

  CONSTRAINT "service_reports_pkey" PRIMARY KEY ("id")
);

CREATE INDEX "service_orders_client_id_idx" ON "service_orders"("client_id");
CREATE INDEX "service_orders_quotation_id_idx" ON "service_orders"("quotation_id");
CREATE INDEX "service_orders_category_idx" ON "service_orders"("category");
CREATE INDEX "service_orders_service_type_idx" ON "service_orders"("service_type");
CREATE INDEX "service_orders_status_idx" ON "service_orders"("status");
CREATE INDEX "service_orders_created_by_idx" ON "service_orders"("created_by");
CREATE INDEX "service_orders_assigned_to_idx" ON "service_orders"("assigned_to");
CREATE INDEX "service_orders_parent_order_id_idx" ON "service_orders"("parent_order_id");
CREATE INDEX "service_orders_status_assigned_to_idx" ON "service_orders"("status", "assigned_to");
CREATE INDEX "service_orders_client_id_created_at_idx" ON "service_orders"("client_id", "created_at");

CREATE INDEX "service_evidences_service_order_id_idx" ON "service_evidences"("service_order_id");
CREATE INDEX "service_evidences_service_order_id_created_at_idx" ON "service_evidences"("service_order_id", "created_at");
CREATE INDEX "service_evidences_type_idx" ON "service_evidences"("type");
CREATE INDEX "service_evidences_created_by_idx" ON "service_evidences"("created_by");

CREATE INDEX "service_reports_service_order_id_idx" ON "service_reports"("service_order_id");
CREATE INDEX "service_reports_service_order_id_created_at_idx" ON "service_reports"("service_order_id", "created_at");
CREATE INDEX "service_reports_created_by_idx" ON "service_reports"("created_by");

ALTER TABLE "service_orders"
  ADD CONSTRAINT "service_orders_client_id_fkey"
  FOREIGN KEY ("client_id") REFERENCES "Client"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

ALTER TABLE "service_orders"
  ADD CONSTRAINT "service_orders_quotation_id_fkey"
  FOREIGN KEY ("quotation_id") REFERENCES "Cotizacion"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

ALTER TABLE "service_orders"
  ADD CONSTRAINT "service_orders_parent_order_id_fkey"
  FOREIGN KEY ("parent_order_id") REFERENCES "service_orders"("id") ON DELETE SET NULL ON UPDATE CASCADE;

ALTER TABLE "service_orders"
  ADD CONSTRAINT "service_orders_created_by_fkey"
  FOREIGN KEY ("created_by") REFERENCES "users"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

ALTER TABLE "service_orders"
  ADD CONSTRAINT "service_orders_assigned_to_fkey"
  FOREIGN KEY ("assigned_to") REFERENCES "users"("id") ON DELETE SET NULL ON UPDATE CASCADE;

ALTER TABLE "service_evidences"
  ADD CONSTRAINT "service_evidences_service_order_id_fkey"
  FOREIGN KEY ("service_order_id") REFERENCES "service_orders"("id") ON DELETE CASCADE ON UPDATE CASCADE;

ALTER TABLE "service_evidences"
  ADD CONSTRAINT "service_evidences_created_by_fkey"
  FOREIGN KEY ("created_by") REFERENCES "users"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

ALTER TABLE "service_reports"
  ADD CONSTRAINT "service_reports_service_order_id_fkey"
  FOREIGN KEY ("service_order_id") REFERENCES "service_orders"("id") ON DELETE CASCADE ON UPDATE CASCADE;

ALTER TABLE "service_reports"
  ADD CONSTRAINT "service_reports_created_by_fkey"
  FOREIGN KEY ("created_by") REFERENCES "users"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

CREATE OR REPLACE FUNCTION set_service_orders_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW."updated_at" = CURRENT_TIMESTAMP;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_service_orders_updated_at ON "service_orders";

CREATE TRIGGER trg_service_orders_updated_at
BEFORE UPDATE ON "service_orders"
FOR EACH ROW
EXECUTE FUNCTION set_service_orders_updated_at();