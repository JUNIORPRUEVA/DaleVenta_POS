-- Sales module revamp: multi-item tickets with commissions

-- CreateEnum
DO $$
BEGIN
    CREATE TYPE "SaleStatus" AS ENUM ('DRAFT', 'CONFIRMED', 'CANCELLED');
EXCEPTION
    WHEN duplicate_object THEN NULL;
END $$;

-- Drop old single-product Sale table if it exists
DROP TABLE IF EXISTS "Sale" CASCADE;

-- Alter Client: phone optional + extra fields
ALTER TABLE "Client"
    ALTER COLUMN "telefono" DROP NOT NULL,
    ADD COLUMN IF NOT EXISTS "email" TEXT,
    ADD COLUMN IF NOT EXISTS "direccion" TEXT,
    ADD COLUMN IF NOT EXISTS "notas" TEXT;

-- CreateTable Sale
CREATE TABLE IF NOT EXISTS "Sale" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "sellerId" UUID NOT NULL,
    "clientId" UUID,
    "status" "SaleStatus" NOT NULL DEFAULT 'DRAFT',
    "note" TEXT,
    "soldAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "subtotal" NUMERIC(12,2) NOT NULL DEFAULT 0,
    "totalCost" NUMERIC(12,2) NOT NULL DEFAULT 0,
    "profit" NUMERIC(12,2) NOT NULL DEFAULT 0,
    "commission" NUMERIC(12,2) NOT NULL DEFAULT 0,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT "Sale_pkey" PRIMARY KEY ("id")
);

-- Indexes for Sale
CREATE INDEX IF NOT EXISTS "Sale_sellerId_idx" ON "Sale"("sellerId");
CREATE INDEX IF NOT EXISTS "Sale_soldAt_idx" ON "Sale"("soldAt");
CREATE INDEX IF NOT EXISTS "Sale_status_idx" ON "Sale"("status");

-- Foreign keys for Sale
DO $$
BEGIN
    ALTER TABLE "Sale" ADD CONSTRAINT "Sale_sellerId_fkey" FOREIGN KEY ("sellerId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;
EXCEPTION
    WHEN duplicate_object THEN NULL;
END $$;

DO $$
BEGIN
    ALTER TABLE "Sale" ADD CONSTRAINT "Sale_clientId_fkey" FOREIGN KEY ("clientId") REFERENCES "Client"("id") ON DELETE SET NULL ON UPDATE CASCADE;
EXCEPTION
    WHEN duplicate_object THEN NULL;
END $$;

-- CreateTable SaleItem
CREATE TABLE IF NOT EXISTS "SaleItem" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "saleId" UUID NOT NULL,
    "productId" UUID NOT NULL,
    "qty" INTEGER NOT NULL,
    "unitPriceSold" NUMERIC(12,2) NOT NULL,
    "unitCostSnapshot" NUMERIC(12,2) NOT NULL,
    "lineTotal" NUMERIC(12,2) NOT NULL,
    "lineCost" NUMERIC(12,2) NOT NULL,
    "lineProfit" NUMERIC(12,2) NOT NULL,
    CONSTRAINT "SaleItem_pkey" PRIMARY KEY ("id")
);

-- Indexes for SaleItem
CREATE INDEX IF NOT EXISTS "SaleItem_saleId_idx" ON "SaleItem"("saleId");
CREATE INDEX IF NOT EXISTS "SaleItem_productId_idx" ON "SaleItem"("productId");

-- Foreign keys for SaleItem
DO $$
BEGIN
    ALTER TABLE "SaleItem" ADD CONSTRAINT "SaleItem_saleId_fkey" FOREIGN KEY ("saleId") REFERENCES "Sale"("id") ON DELETE CASCADE ON UPDATE CASCADE;
EXCEPTION
    WHEN duplicate_object THEN NULL;
END $$;

DO $$
BEGIN
    ALTER TABLE "SaleItem" ADD CONSTRAINT "SaleItem_productId_fkey" FOREIGN KEY ("productId") REFERENCES "Product"("id") ON DELETE CASCADE ON UPDATE CASCADE;
EXCEPTION
    WHEN duplicate_object THEN NULL;
END $$;
