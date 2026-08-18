DO $$ BEGIN
  CREATE TYPE "PayrollPaymentStatus" AS ENUM ('DRAFT', 'PAID');
EXCEPTION
  WHEN duplicate_object THEN null;
END $$;

CREATE TABLE IF NOT EXISTS "PayrollEmployeePeriodStatus" (
  "id" UUID NOT NULL DEFAULT gen_random_uuid(),
  "ownerId" UUID NOT NULL,
  "periodId" UUID NOT NULL,
  "employeeId" UUID NOT NULL,
  "status" "PayrollPaymentStatus" NOT NULL DEFAULT 'DRAFT',
  "paidAt" TIMESTAMP(3),
  "paidById" UUID,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

  CONSTRAINT "PayrollEmployeePeriodStatus_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX IF NOT EXISTS "PayrollEmployeePeriodStatus_ownerId_periodId_employeeId_key"
  ON "PayrollEmployeePeriodStatus"("ownerId", "periodId", "employeeId");
CREATE INDEX IF NOT EXISTS "PayrollEmployeePeriodStatus_ownerId_idx"
  ON "PayrollEmployeePeriodStatus"("ownerId");
CREATE INDEX IF NOT EXISTS "PayrollEmployeePeriodStatus_periodId_employeeId_idx"
  ON "PayrollEmployeePeriodStatus"("periodId", "employeeId");
CREATE INDEX IF NOT EXISTS "PayrollEmployeePeriodStatus_status_idx"
  ON "PayrollEmployeePeriodStatus"("status");

DO $$ BEGIN
  ALTER TABLE "PayrollEmployeePeriodStatus"
    ADD CONSTRAINT "PayrollEmployeePeriodStatus_ownerId_fkey"
    FOREIGN KEY ("ownerId") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;
EXCEPTION
  WHEN duplicate_object THEN null;
END $$;

DO $$ BEGIN
  ALTER TABLE "PayrollEmployeePeriodStatus"
    ADD CONSTRAINT "PayrollEmployeePeriodStatus_periodId_fkey"
    FOREIGN KEY ("periodId") REFERENCES "PayrollPeriod"("id") ON DELETE CASCADE ON UPDATE CASCADE;
EXCEPTION
  WHEN duplicate_object THEN null;
END $$;

DO $$ BEGIN
  ALTER TABLE "PayrollEmployeePeriodStatus"
    ADD CONSTRAINT "PayrollEmployeePeriodStatus_employeeId_fkey"
    FOREIGN KEY ("employeeId") REFERENCES "PayrollEmployee"("id") ON DELETE CASCADE ON UPDATE CASCADE;
EXCEPTION
  WHEN duplicate_object THEN null;
END $$;
