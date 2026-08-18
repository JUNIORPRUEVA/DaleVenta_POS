-- Operations module tables

DO $$
BEGIN
  CREATE TYPE "ServiceType" AS ENUM ('INSTALLATION', 'MAINTENANCE', 'WARRANTY', 'POS_SUPPORT', 'OTHER');
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

DO $$
BEGIN
  CREATE TYPE "ServiceStatus" AS ENUM ('RESERVED', 'SURVEY', 'SCHEDULED', 'IN_PROGRESS', 'COMPLETED', 'WARRANTY', 'CLOSED', 'CANCELLED');
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

DO $$
BEGIN
  CREATE TYPE "ServiceAssignmentRole" AS ENUM ('LEAD', 'ASSISTANT');
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

DO $$
BEGIN
  CREATE TYPE "ServiceUpdateType" AS ENUM ('STATUS_CHANGE', 'NOTE', 'SCHEDULE_CHANGE', 'ASSIGNMENT_CHANGE', 'PAYMENT_UPDATE', 'STEP_UPDATE', 'FILE_UPLOAD', 'WARRANTY_CREATED');
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

CREATE TABLE IF NOT EXISTS "Service" (
  "id" UUID NOT NULL DEFAULT gen_random_uuid(),
  "customerId" UUID NOT NULL,
  "createdByUserId" UUID NOT NULL,
  "serviceType" "ServiceType" NOT NULL,
  "category" TEXT NOT NULL,
  "status" "ServiceStatus" NOT NULL DEFAULT 'RESERVED',
  "priority" INTEGER NOT NULL DEFAULT 2,
  "title" TEXT NOT NULL,
  "description" TEXT NOT NULL,
  "quotedAmount" DECIMAL(12,2),
  "depositAmount" DECIMAL(12,2),
  "paymentStatus" TEXT NOT NULL DEFAULT 'pending',
  "addressSnapshot" TEXT,
  "scheduledStart" TIMESTAMP(3),
  "scheduledEnd" TIMESTAMP(3),
  "completedAt" TIMESTAMP(3),
  "warrantyParentServiceId" UUID,
  "tags" TEXT[] DEFAULT ARRAY[]::TEXT[],
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "isDeleted" BOOLEAN NOT NULL DEFAULT false,
  CONSTRAINT "Service_pkey" PRIMARY KEY ("id")
);

CREATE TABLE IF NOT EXISTS "ServiceAssignment" (
  "id" UUID NOT NULL DEFAULT gen_random_uuid(),
  "serviceId" UUID NOT NULL,
  "userId" UUID NOT NULL,
  "role" "ServiceAssignmentRole" NOT NULL DEFAULT 'ASSISTANT',
  "assignedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "ServiceAssignment_pkey" PRIMARY KEY ("id")
);

CREATE TABLE IF NOT EXISTS "ServiceStep" (
  "id" UUID NOT NULL DEFAULT gen_random_uuid(),
  "serviceId" UUID NOT NULL,
  "stepKey" TEXT NOT NULL,
  "stepLabel" TEXT NOT NULL,
  "isDone" BOOLEAN NOT NULL DEFAULT false,
  "doneAt" TIMESTAMP(3),
  "doneByUserId" UUID,
  CONSTRAINT "ServiceStep_pkey" PRIMARY KEY ("id")
);

CREATE TABLE IF NOT EXISTS "ServiceUpdate" (
  "id" UUID NOT NULL DEFAULT gen_random_uuid(),
  "serviceId" UUID NOT NULL,
  "changedByUserId" UUID NOT NULL,
  "type" "ServiceUpdateType" NOT NULL,
  "oldValue" JSONB,
  "newValue" JSONB,
  "message" TEXT,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "ServiceUpdate_pkey" PRIMARY KEY ("id")
);

CREATE TABLE IF NOT EXISTS "ServiceFile" (
  "id" UUID NOT NULL DEFAULT gen_random_uuid(),
  "serviceId" UUID NOT NULL,
  "uploadedByUserId" UUID NOT NULL,
  "fileUrl" TEXT NOT NULL,
  "fileType" TEXT NOT NULL,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "ServiceFile_pkey" PRIMARY KEY ("id")
);

CREATE INDEX IF NOT EXISTS "Service_customerId_idx" ON "Service"("customerId");
CREATE INDEX IF NOT EXISTS "Service_createdByUserId_idx" ON "Service"("createdByUserId");
CREATE INDEX IF NOT EXISTS "Service_serviceType_idx" ON "Service"("serviceType");
CREATE INDEX IF NOT EXISTS "Service_status_idx" ON "Service"("status");
CREATE INDEX IF NOT EXISTS "Service_priority_idx" ON "Service"("priority");
CREATE INDEX IF NOT EXISTS "Service_scheduledStart_idx" ON "Service"("scheduledStart");
CREATE INDEX IF NOT EXISTS "Service_isDeleted_idx" ON "Service"("isDeleted");

CREATE UNIQUE INDEX IF NOT EXISTS "ServiceAssignment_serviceId_userId_key" ON "ServiceAssignment"("serviceId", "userId");
CREATE INDEX IF NOT EXISTS "ServiceAssignment_serviceId_idx" ON "ServiceAssignment"("serviceId");
CREATE INDEX IF NOT EXISTS "ServiceAssignment_userId_idx" ON "ServiceAssignment"("userId");

CREATE UNIQUE INDEX IF NOT EXISTS "ServiceStep_serviceId_stepKey_key" ON "ServiceStep"("serviceId", "stepKey");
CREATE INDEX IF NOT EXISTS "ServiceStep_serviceId_idx" ON "ServiceStep"("serviceId");

CREATE INDEX IF NOT EXISTS "ServiceUpdate_serviceId_createdAt_idx" ON "ServiceUpdate"("serviceId", "createdAt");
CREATE INDEX IF NOT EXISTS "ServiceUpdate_changedByUserId_idx" ON "ServiceUpdate"("changedByUserId");

CREATE INDEX IF NOT EXISTS "ServiceFile_serviceId_idx" ON "ServiceFile"("serviceId");
CREATE INDEX IF NOT EXISTS "ServiceFile_uploadedByUserId_idx" ON "ServiceFile"("uploadedByUserId");

DO $$
BEGIN
  ALTER TABLE "Service"
    ADD CONSTRAINT "Service_customerId_fkey"
    FOREIGN KEY ("customerId") REFERENCES "Client"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

DO $$
BEGIN
  ALTER TABLE "Service"
    ADD CONSTRAINT "Service_createdByUserId_fkey"
    FOREIGN KEY ("createdByUserId") REFERENCES "User"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

DO $$
BEGIN
  ALTER TABLE "Service"
    ADD CONSTRAINT "Service_warrantyParentServiceId_fkey"
    FOREIGN KEY ("warrantyParentServiceId") REFERENCES "Service"("id") ON DELETE SET NULL ON UPDATE CASCADE;
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

DO $$
BEGIN
  ALTER TABLE "ServiceAssignment"
    ADD CONSTRAINT "ServiceAssignment_serviceId_fkey"
    FOREIGN KEY ("serviceId") REFERENCES "Service"("id") ON DELETE CASCADE ON UPDATE CASCADE;
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

DO $$
BEGIN
  ALTER TABLE "ServiceAssignment"
    ADD CONSTRAINT "ServiceAssignment_userId_fkey"
    FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

DO $$
BEGIN
  ALTER TABLE "ServiceStep"
    ADD CONSTRAINT "ServiceStep_serviceId_fkey"
    FOREIGN KEY ("serviceId") REFERENCES "Service"("id") ON DELETE CASCADE ON UPDATE CASCADE;
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

DO $$
BEGIN
  ALTER TABLE "ServiceStep"
    ADD CONSTRAINT "ServiceStep_doneByUserId_fkey"
    FOREIGN KEY ("doneByUserId") REFERENCES "User"("id") ON DELETE SET NULL ON UPDATE CASCADE;
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

DO $$
BEGIN
  ALTER TABLE "ServiceUpdate"
    ADD CONSTRAINT "ServiceUpdate_serviceId_fkey"
    FOREIGN KEY ("serviceId") REFERENCES "Service"("id") ON DELETE CASCADE ON UPDATE CASCADE;
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

DO $$
BEGIN
  ALTER TABLE "ServiceUpdate"
    ADD CONSTRAINT "ServiceUpdate_changedByUserId_fkey"
    FOREIGN KEY ("changedByUserId") REFERENCES "User"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

DO $$
BEGIN
  ALTER TABLE "ServiceFile"
    ADD CONSTRAINT "ServiceFile_serviceId_fkey"
    FOREIGN KEY ("serviceId") REFERENCES "Service"("id") ON DELETE CASCADE ON UPDATE CASCADE;
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

DO $$
BEGIN
  ALTER TABLE "ServiceFile"
    ADD CONSTRAINT "ServiceFile_uploadedByUserId_fkey"
    FOREIGN KEY ("uploadedByUserId") REFERENCES "User"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;
