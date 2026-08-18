-- Payroll module tables (cloud backend)

-- Create enums
DO $$
BEGIN
  CREATE TYPE "PayrollPeriodStatus" AS ENUM ('OPEN', 'CLOSED');
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

DO $$
BEGIN
  CREATE TYPE "PayrollEntryType" AS ENUM ('FALTA_DIA', 'TARDE', 'BONO', 'COMISION', 'ADELANTO', 'DESCUENTO', 'OTRO');
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

-- payroll_employees
CREATE TABLE IF NOT EXISTS "payroll_employees" (
  "id" UUID NOT NULL DEFAULT gen_random_uuid(),
  "ownerId" UUID NOT NULL,
  "nombre" TEXT NOT NULL,
  "telefono" TEXT,
  "puesto" TEXT,
  "activo" BOOLEAN NOT NULL DEFAULT true,
  "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "payroll_employees_pkey" PRIMARY KEY ("id")
);

-- payroll_periods
CREATE TABLE IF NOT EXISTS "payroll_periods" (
  "id" UUID NOT NULL DEFAULT gen_random_uuid(),
  "ownerId" UUID NOT NULL,
  "title" TEXT NOT NULL,
  "startDate" TIMESTAMPTZ(6) NOT NULL,
  "endDate" TIMESTAMPTZ(6) NOT NULL,
  "status" "PayrollPeriodStatus" NOT NULL DEFAULT 'OPEN',
  "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "payroll_periods_pkey" PRIMARY KEY ("id")
);

-- payroll_employee_config
CREATE TABLE IF NOT EXISTS "payroll_employee_config" (
  "id" UUID NOT NULL DEFAULT gen_random_uuid(),
  "ownerId" UUID NOT NULL,
  "periodId" UUID NOT NULL,
  "employeeId" UUID NOT NULL,
  "baseSalary" DECIMAL(12,2) NOT NULL,
  "includeCommissions" BOOLEAN NOT NULL DEFAULT false,
  "notes" TEXT,
  "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "payroll_employee_config_pkey" PRIMARY KEY ("id")
);

-- payroll_entries
CREATE TABLE IF NOT EXISTS "payroll_entries" (
  "id" UUID NOT NULL DEFAULT gen_random_uuid(),
  "ownerId" UUID NOT NULL,
  "periodId" UUID NOT NULL,
  "employeeId" UUID NOT NULL,
  "date" TIMESTAMPTZ(6) NOT NULL,
  "type" "PayrollEntryType" NOT NULL,
  "concept" TEXT NOT NULL,
  "amount" DECIMAL(12,2) NOT NULL,
  "cantidad" DECIMAL(12,2),
  "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "payroll_entries_pkey" PRIMARY KEY ("id")
);

-- Unique and indexes
CREATE UNIQUE INDEX IF NOT EXISTS "payroll_employee_config_ownerId_periodId_employeeId_key"
  ON "payroll_employee_config" ("ownerId", "periodId", "employeeId");

CREATE INDEX IF NOT EXISTS "payroll_employees_ownerId_idx" ON "payroll_employees" ("ownerId");
CREATE INDEX IF NOT EXISTS "payroll_employees_ownerId_nombre_idx" ON "payroll_employees" ("ownerId", "nombre");

CREATE INDEX IF NOT EXISTS "payroll_periods_ownerId_idx" ON "payroll_periods" ("ownerId");
CREATE INDEX IF NOT EXISTS "payroll_periods_ownerId_status_idx" ON "payroll_periods" ("ownerId", "status");
CREATE INDEX IF NOT EXISTS "payroll_periods_startDate_endDate_idx" ON "payroll_periods" ("startDate", "endDate");

CREATE INDEX IF NOT EXISTS "payroll_employee_config_ownerId_idx" ON "payroll_employee_config" ("ownerId");
CREATE INDEX IF NOT EXISTS "payroll_employee_config_periodId_employeeId_idx" ON "payroll_employee_config" ("periodId", "employeeId");

CREATE INDEX IF NOT EXISTS "payroll_entries_ownerId_idx" ON "payroll_entries" ("ownerId");
CREATE INDEX IF NOT EXISTS "payroll_entries_periodId_employeeId_idx" ON "payroll_entries" ("periodId", "employeeId");
CREATE INDEX IF NOT EXISTS "payroll_entries_date_idx" ON "payroll_entries" ("date");

-- FKs
DO $$
BEGIN
  ALTER TABLE "payroll_employees"
    ADD CONSTRAINT "payroll_employees_ownerId_fkey"
    FOREIGN KEY ("ownerId") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

DO $$
BEGIN
  ALTER TABLE "payroll_periods"
    ADD CONSTRAINT "payroll_periods_ownerId_fkey"
    FOREIGN KEY ("ownerId") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

DO $$
BEGIN
  ALTER TABLE "payroll_employee_config"
    ADD CONSTRAINT "payroll_employee_config_ownerId_fkey"
    FOREIGN KEY ("ownerId") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

DO $$
BEGIN
  ALTER TABLE "payroll_employee_config"
    ADD CONSTRAINT "payroll_employee_config_periodId_fkey"
    FOREIGN KEY ("periodId") REFERENCES "payroll_periods"("id") ON DELETE CASCADE ON UPDATE CASCADE;
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

DO $$
BEGIN
  ALTER TABLE "payroll_employee_config"
    ADD CONSTRAINT "payroll_employee_config_employeeId_fkey"
    FOREIGN KEY ("employeeId") REFERENCES "payroll_employees"("id") ON DELETE CASCADE ON UPDATE CASCADE;
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

DO $$
BEGIN
  ALTER TABLE "payroll_entries"
    ADD CONSTRAINT "payroll_entries_ownerId_fkey"
    FOREIGN KEY ("ownerId") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

DO $$
BEGIN
  ALTER TABLE "payroll_entries"
    ADD CONSTRAINT "payroll_entries_periodId_fkey"
    FOREIGN KEY ("periodId") REFERENCES "payroll_periods"("id") ON DELETE CASCADE ON UPDATE CASCADE;
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

DO $$
BEGIN
  ALTER TABLE "payroll_entries"
    ADD CONSTRAINT "payroll_entries_employeeId_fkey"
    FOREIGN KEY ("employeeId") REFERENCES "payroll_employees"("id") ON DELETE CASCADE ON UPDATE CASCADE;
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;
