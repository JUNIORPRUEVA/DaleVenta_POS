CREATE TYPE "PayrollServiceCommissionStatus" AS ENUM ('PENDING', 'APPROVED', 'REJECTED', 'CANCELED');

CREATE TABLE "payroll_service_commission_requests" (
    "id" UUID NOT NULL,
    "ownerId" UUID NOT NULL,
    "service_order_id" UUID NOT NULL,
    "quotation_id" UUID,
    "employee_id" UUID NOT NULL,
    "technician_user_id" UUID NOT NULL,
    "created_by_user_id" UUID,
    "reviewed_by_user_id" UUID,
    "period_id" UUID,
    "payroll_entry_id" UUID,
    "service_type" "service_order_type" NOT NULL,
    "finalized_at" TIMESTAMP(3) NOT NULL,
    "profit_after_expense" DECIMAL(12,2) NOT NULL,
    "commission_rate" DECIMAL(5,4) NOT NULL DEFAULT 0.1000,
    "commission_amount" DECIMAL(12,2) NOT NULL,
    "concept" TEXT NOT NULL,
    "status" "PayrollServiceCommissionStatus" NOT NULL DEFAULT 'PENDING',
    "review_note" TEXT,
    "approved_at" TIMESTAMP(3),
    "rejected_at" TIMESTAMP(3),
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "payroll_service_commission_requests_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX "payroll_service_commission_requests_service_order_id_key"
    ON "payroll_service_commission_requests"("service_order_id");

CREATE UNIQUE INDEX "payroll_service_commission_requests_payroll_entry_id_key"
    ON "payroll_service_commission_requests"("payroll_entry_id");

CREATE INDEX "payroll_service_commission_requests_ownerId_idx"
    ON "payroll_service_commission_requests"("ownerId");

CREATE INDEX "payroll_service_commission_requests_ownerId_status_idx"
    ON "payroll_service_commission_requests"("ownerId", "status");

CREATE INDEX "payroll_service_commission_requests_employee_id_status_idx"
    ON "payroll_service_commission_requests"("employee_id", "status");

CREATE INDEX "payroll_service_commission_requests_technician_user_id_status_idx"
    ON "payroll_service_commission_requests"("technician_user_id", "status");

CREATE INDEX "payroll_service_commission_requests_finalized_at_idx"
    ON "payroll_service_commission_requests"("finalized_at");

CREATE INDEX "payroll_service_commission_requests_period_id_idx"
    ON "payroll_service_commission_requests"("period_id");

ALTER TABLE "payroll_service_commission_requests"
    ADD CONSTRAINT "payroll_service_commission_requests_ownerId_fkey"
    FOREIGN KEY ("ownerId") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

ALTER TABLE "payroll_service_commission_requests"
    ADD CONSTRAINT "payroll_service_commission_requests_service_order_id_fkey"
    FOREIGN KEY ("service_order_id") REFERENCES "service_orders"("id") ON DELETE CASCADE ON UPDATE CASCADE;

ALTER TABLE "payroll_service_commission_requests"
    ADD CONSTRAINT "payroll_service_commission_requests_employee_id_fkey"
    FOREIGN KEY ("employee_id") REFERENCES "PayrollEmployee"("id") ON DELETE CASCADE ON UPDATE CASCADE;

ALTER TABLE "payroll_service_commission_requests"
    ADD CONSTRAINT "payroll_service_commission_requests_technician_user_id_fkey"
    FOREIGN KEY ("technician_user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

ALTER TABLE "payroll_service_commission_requests"
    ADD CONSTRAINT "payroll_service_commission_requests_created_by_user_id_fkey"
    FOREIGN KEY ("created_by_user_id") REFERENCES "users"("id") ON DELETE SET NULL ON UPDATE CASCADE;

ALTER TABLE "payroll_service_commission_requests"
    ADD CONSTRAINT "payroll_service_commission_requests_reviewed_by_user_id_fkey"
    FOREIGN KEY ("reviewed_by_user_id") REFERENCES "users"("id") ON DELETE SET NULL ON UPDATE CASCADE;

ALTER TABLE "payroll_service_commission_requests"
    ADD CONSTRAINT "payroll_service_commission_requests_period_id_fkey"
    FOREIGN KEY ("period_id") REFERENCES "PayrollPeriod"("id") ON DELETE SET NULL ON UPDATE CASCADE;

ALTER TABLE "payroll_service_commission_requests"
    ADD CONSTRAINT "payroll_service_commission_requests_payroll_entry_id_fkey"
    FOREIGN KEY ("payroll_entry_id") REFERENCES "PayrollEntry"("id") ON DELETE SET NULL ON UPDATE CASCADE;