-- Solicitudes de mejora de plan (ticket de soporte cuando la empresa ya esta
-- en el ultimo plan del catalogo).

CREATE TYPE "license_plan_request_status" AS ENUM ('OPEN', 'CONTACTED', 'CLOSED');

CREATE TABLE "license_plan_requests" (
    "id" UUID NOT NULL,
    "company_id" UUID NOT NULL,
    "current_plan_code" VARCHAR(32),
    "requested_plan_code" VARCHAR(32),
    "message" TEXT,
    "status" "license_plan_request_status" NOT NULL DEFAULT 'OPEN',
    "reference" VARCHAR(32) NOT NULL,
    "created_by_user_id" UUID,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "license_plan_requests_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX "license_plan_requests_reference_key" ON "license_plan_requests"("reference");
CREATE INDEX "license_plan_requests_company_id_status_idx" ON "license_plan_requests"("company_id", "status");
CREATE INDEX "license_plan_requests_status_created_at_idx" ON "license_plan_requests"("status", "created_at");

ALTER TABLE "license_plan_requests"
  ADD CONSTRAINT "license_plan_requests_company_id_fkey"
  FOREIGN KEY ("company_id") REFERENCES "companies"("id") ON DELETE CASCADE ON UPDATE CASCADE;
