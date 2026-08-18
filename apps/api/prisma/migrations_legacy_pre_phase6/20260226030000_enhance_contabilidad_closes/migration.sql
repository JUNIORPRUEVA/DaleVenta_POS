-- AlterTable
ALTER TABLE "Close"
ADD COLUMN "transferBank" TEXT,
ADD COLUMN "createdById" UUID,
ADD COLUMN "createdByName" TEXT;

-- CreateIndex
CREATE INDEX "Close_createdById_idx" ON "Close"("createdById");
