-- Nómina tables for cloud backend

-- Enums
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

-- PayrollEmployee
CREATE TABLE IF NOT EXISTS "PayrollEmployee" (
  "id" UUID NOT NULL DEFAULT gen_random_uuid(),
  "ownerId" UUID NOT NULL,
  "nombre" TEXT NOT NULL,
  "telefono" TEXT,
  "puesto" TEXT,
  "activo" BOOLEAN NOT NULL DEFAULT true,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "PayrollEmployee_pkey" PRIMARY KEY ("id")
);

-- PayrollPeriod
CREATE TABLE IF NOT EXISTS "PayrollPeriod" (
  "id" UUID NOT NULL DEFAULT gen_random_uuid(),
  "ownerId" UUID NOT NULL,
  "title" TEXT NOT NULL,
  "startDate" TIMESTAMP(3) NOT NULL,
  "endDate" TIMESTAMP(3) NOT NULL,
  "status" "PayrollPeriodStatus" NOT NULL DEFAULT 'OPEN',
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "PayrollPeriod_pkey" PRIMARY KEY ("id")
);

-- PayrollEmployeeConfig
CREATE TABLE IF NOT EXISTS "PayrollEmployeeConfig" (
  "id" UUID NOT NULL DEFAULT gen_random_uuid(),
  "ownerId" UUID NOT NULL,
  "periodId" UUID NOT NULL,
  "employeeId" UUID NOT NULL,
  "baseSalary" DECIMAL(12,2) NOT NULL,
  "includeCommissions" BOOLEAN NOT NULL DEFAULT false,
  "notes" TEXT,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "PayrollEmployeeConfig_pkey" PRIMARY KEY ("id")
);

-- PayrollEntry
CREATE TABLE IF NOT EXISTS "PayrollEntry" (
  "id" UUID NOT NULL DEFAULT gen_random_uuid(),
  "ownerId" UUID NOT NULL,
  "periodId" UUID NOT NULL,
  "employeeId" UUID NOT NULL,
  "date" TIMESTAMP(3) NOT NULL,
  "type" "PayrollEntryType" NOT NULL,
  "concept" TEXT NOT NULL,
  "amount" DECIMAL(12,2) NOT NULL,
  "cantidad" DECIMAL(12,2),
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "PayrollEntry_pkey" PRIMARY KEY ("id")
);

-- Constraints / indexes
CREATE UNIQUE INDEX IF NOT EXISTS "PayrollEmployeeConfig_ownerId_periodId_employeeId_key"
  ON "PayrollEmployeeConfig"("ownerId", "periodId", "employeeId");

CREATE INDEX IF NOT EXISTS "PayrollEmployee_ownerId_idx" ON "PayrollEmployee"("ownerId");
CREATE INDEX IF NOT EXISTS "PayrollEmployee_ownerId_nombre_idx" ON "PayrollEmployee"("ownerId", "nombre");

CREATE INDEX IF NOT EXISTS "PayrollPeriod_ownerId_idx" ON "PayrollPeriod"("ownerId");
CREATE INDEX IF NOT EXISTS "PayrollPeriod_ownerId_status_idx" ON "PayrollPeriod"("ownerId", "status");
CREATE INDEX IF NOT EXISTS "PayrollPeriod_startDate_endDate_idx" ON "PayrollPeriod"("startDate", "endDate");

CREATE INDEX IF NOT EXISTS "PayrollEmployeeConfig_ownerId_idx" ON "PayrollEmployeeConfig"("ownerId");
CREATE INDEX IF NOT EXISTS "PayrollEmployeeConfig_periodId_employeeId_idx" ON "PayrollEmployeeConfig"("periodId", "employeeId");

CREATE INDEX IF NOT EXISTS "PayrollEntry_ownerId_idx" ON "PayrollEntry"("ownerId");
CREATE INDEX IF NOT EXISTS "PayrollEntry_periodId_employeeId_idx" ON "PayrollEntry"("periodId", "employeeId");
CREATE INDEX IF NOT EXISTS "PayrollEntry_date_idx" ON "PayrollEntry"("date");

-- FKs
DO $$
BEGIN
  ALTER TABLE "PayrollEmployee"
    ADD CONSTRAINT "PayrollEmployee_ownerId_fkey"
    FOREIGN KEY ("ownerId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

DO $$
BEGIN
  ALTER TABLE "PayrollPeriod"
    ADD CONSTRAINT "PayrollPeriod_ownerId_fkey"
    FOREIGN KEY ("ownerId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

DO $$
BEGIN
  ALTER TABLE "PayrollEmployeeConfig"
    ADD CONSTRAINT "PayrollEmployeeConfig_ownerId_fkey"
    FOREIGN KEY ("ownerId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

DO $$
BEGIN
  ALTER TABLE "PayrollEmployeeConfig"
    ADD CONSTRAINT "PayrollEmployeeConfig_periodId_fkey"
    FOREIGN KEY ("periodId") REFERENCES "PayrollPeriod"("id") ON DELETE CASCADE ON UPDATE CASCADE;
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

DO $$
BEGIN
  ALTER TABLE "PayrollEmployeeConfig"
    ADD CONSTRAINT "PayrollEmployeeConfig_employeeId_fkey"
    FOREIGN KEY ("employeeId") REFERENCES "PayrollEmployee"("id") ON DELETE CASCADE ON UPDATE CASCADE;
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

DO $$
BEGIN
  ALTER TABLE "PayrollEntry"
    ADD CONSTRAINT "PayrollEntry_ownerId_fkey"
    FOREIGN KEY ("ownerId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

DO $$
BEGIN
  ALTER TABLE "PayrollEntry"
    ADD CONSTRAINT "PayrollEntry_periodId_fkey"
    FOREIGN KEY ("periodId") REFERENCES "PayrollPeriod"("id") ON DELETE CASCADE ON UPDATE CASCADE;
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

DO $$
BEGIN
  ALTER TABLE "PayrollEntry"
    ADD CONSTRAINT "PayrollEntry_employeeId_fkey"
    FOREIGN KEY ("employeeId") REFERENCES "PayrollEmployee"("id") ON DELETE CASCADE ON UPDATE CASCADE;
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;
