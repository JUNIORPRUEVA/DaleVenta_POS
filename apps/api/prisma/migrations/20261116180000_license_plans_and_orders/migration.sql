-- CreateEnum
CREATE TYPE "license_order_status" AS ENUM ('CREATED', 'AWAITING_TRANSFER', 'EVIDENCE_RECEIVED', 'UNCONFIRMED', 'SETTLED', 'REJECTED', 'CANCELLED', 'EXPIRED');

-- CreateEnum
CREATE TYPE "license_evidence_status" AS ENUM ('RECEIVED', 'DUPLICATE', 'REJECTED');

-- CreateEnum
CREATE TYPE "license_notification_kind" AS ENUM ('ADMIN_EVIDENCE', 'REMINDER_5D', 'REMINDER_1D');

-- CreateEnum
CREATE TYPE "license_notification_status" AS ENUM ('PENDING', 'SENT', 'FAILED', 'SKIPPED');

-- AlterTable
ALTER TABLE "companies" ADD COLUMN     "max_warehouses" INTEGER,
ADD COLUMN     "plan_catalog_version" INTEGER,
ADD COLUMN     "plan_code" VARCHAR(32);

-- CreateTable
CREATE TABLE "license_plans" (
    "id" UUID NOT NULL,
    "code" VARCHAR(32) NOT NULL,
    "name" TEXT NOT NULL,
    "version" INTEGER NOT NULL DEFAULT 1,
    "monthly_price" DECIMAL(12,2) NOT NULL,
    "currency" VARCHAR(3) NOT NULL DEFAULT 'DOP',
    "max_users" INTEGER NOT NULL,
    "max_products" INTEGER NOT NULL,
    "max_warehouses" INTEGER NOT NULL,
    "multi_warehouse" BOOLEAN NOT NULL DEFAULT false,
    "wholesale" BOOLEAN NOT NULL DEFAULT false,
    "uom" BOOLEAN NOT NULL DEFAULT false,
    "ecf" BOOLEAN NOT NULL DEFAULT false,
    "taxes" BOOLEAN NOT NULL DEFAULT false,
    "ecf_monthly_quota" INTEGER,
    "active" BOOLEAN NOT NULL DEFAULT true,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "license_plans_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "license_payment_orders" (
    "id" UUID NOT NULL,
    "company_id" UUID NOT NULL,
    "plan_code" VARCHAR(32) NOT NULL,
    "catalog_version" INTEGER NOT NULL,
    "currency" VARCHAR(3) NOT NULL DEFAULT 'DOP',
    "amount" DECIMAL(12,2) NOT NULL,
    "months" INTEGER NOT NULL DEFAULT 1,
    "period_start" TIMESTAMP(3),
    "period_end" TIMESTAMP(3),
    "status" "license_order_status" NOT NULL DEFAULT 'CREATED',
    "reference" VARCHAR(32) NOT NULL,
    "expires_at" TIMESTAMP(3) NOT NULL,
    "created_by_user_id" UUID,
    "notes" TEXT,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "license_payment_orders_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "license_payment_evidence" (
    "id" UUID NOT NULL,
    "order_id" UUID NOT NULL,
    "company_id" UUID NOT NULL,
    "channel" VARCHAR(16) NOT NULL DEFAULT 'APP',
    "storage_key" TEXT NOT NULL,
    "original_name" TEXT NOT NULL,
    "mime" VARCHAR(120) NOT NULL,
    "size_bytes" INTEGER NOT NULL,
    "sha256" VARCHAR(64) NOT NULL,
    "status" "license_evidence_status" NOT NULL DEFAULT 'RECEIVED',
    "notified_at" TIMESTAMP(3),
    "uploaded_by_user_id" UUID,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "license_payment_evidence_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "license_company_overrides" (
    "id" UUID NOT NULL,
    "company_id" UUID NOT NULL,
    "extra_users" INTEGER NOT NULL DEFAULT 0,
    "extra_products" INTEGER NOT NULL DEFAULT 0,
    "extra_warehouses" INTEGER NOT NULL DEFAULT 0,
    "allow_ecf" BOOLEAN NOT NULL DEFAULT false,
    "allow_taxes" BOOLEAN NOT NULL DEFAULT false,
    "allow_wholesale" BOOLEAN NOT NULL DEFAULT false,
    "allow_uom" BOOLEAN NOT NULL DEFAULT false,
    "note" TEXT,
    "granted_by" TEXT,
    "granted_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "expires_at" TIMESTAMP(3),

    CONSTRAINT "license_company_overrides_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "license_notification_jobs" (
    "id" UUID NOT NULL,
    "company_id" UUID NOT NULL,
    "kind" "license_notification_kind" NOT NULL,
    "payload" JSONB NOT NULL,
    "status" "license_notification_status" NOT NULL DEFAULT 'PENDING',
    "attempts" INTEGER NOT NULL DEFAULT 0,
    "last_error" TEXT,
    "scheduled_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "sent_at" TIMESTAMP(3),
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "license_notification_jobs_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "license_reminder_logs" (
    "id" UUID NOT NULL,
    "company_id" UUID NOT NULL,
    "kind" "license_notification_kind" NOT NULL,
    "period_end_snapshot" TIMESTAMP(3) NOT NULL,
    "status" "license_notification_status" NOT NULL DEFAULT 'SENT',
    "sent_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "license_reminder_logs_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "license_plans_code_key" ON "license_plans"("code");

-- CreateIndex
CREATE UNIQUE INDEX "license_payment_orders_reference_key" ON "license_payment_orders"("reference");

-- CreateIndex
CREATE INDEX "license_payment_orders_company_id_status_idx" ON "license_payment_orders"("company_id", "status");

-- CreateIndex
CREATE INDEX "license_payment_orders_status_created_at_idx" ON "license_payment_orders"("status", "created_at");

-- CreateIndex
CREATE INDEX "license_payment_evidence_order_id_idx" ON "license_payment_evidence"("order_id");

-- CreateIndex
CREATE UNIQUE INDEX "license_payment_evidence_company_id_sha256_key" ON "license_payment_evidence"("company_id", "sha256");

-- CreateIndex
CREATE UNIQUE INDEX "license_company_overrides_company_id_key" ON "license_company_overrides"("company_id");

-- CreateIndex
CREATE INDEX "license_notification_jobs_status_scheduled_at_idx" ON "license_notification_jobs"("status", "scheduled_at");

-- CreateIndex
CREATE UNIQUE INDEX "license_reminder_logs_company_id_kind_period_end_snapshot_key" ON "license_reminder_logs"("company_id", "kind", "period_end_snapshot");

-- AddForeignKey
ALTER TABLE "license_payment_orders" ADD CONSTRAINT "license_payment_orders_company_id_fkey" FOREIGN KEY ("company_id") REFERENCES "companies"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "license_payment_evidence" ADD CONSTRAINT "license_payment_evidence_order_id_fkey" FOREIGN KEY ("order_id") REFERENCES "license_payment_orders"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "license_payment_evidence" ADD CONSTRAINT "license_payment_evidence_company_id_fkey" FOREIGN KEY ("company_id") REFERENCES "companies"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "license_company_overrides" ADD CONSTRAINT "license_company_overrides_company_id_fkey" FOREIGN KEY ("company_id") REFERENCES "companies"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "license_notification_jobs" ADD CONSTRAINT "license_notification_jobs_company_id_fkey" FOREIGN KEY ("company_id") REFERENCES "companies"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "license_reminder_logs" ADD CONSTRAINT "license_reminder_logs_company_id_fkey" FOREIGN KEY ("company_id") REFERENCES "companies"("id") ON DELETE CASCADE ON UPDATE CASCADE;

