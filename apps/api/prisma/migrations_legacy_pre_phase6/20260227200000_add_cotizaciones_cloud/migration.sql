-- CreateTable
CREATE TABLE "Cotizacion" (
    "id" UUID NOT NULL,
    "createdByUserId" UUID NOT NULL,
    "customerId" UUID,
    "customerName" TEXT NOT NULL,
    "customerPhone" TEXT NOT NULL,
    "note" TEXT,
    "includeItbis" BOOLEAN NOT NULL DEFAULT false,
    "itbisRate" DECIMAL(5,4) NOT NULL DEFAULT 0.18,
    "subtotal" DECIMAL(12,2) NOT NULL,
    "itbisAmount" DECIMAL(12,2) NOT NULL,
    "total" DECIMAL(12,2) NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "Cotizacion_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "CotizacionItem" (
    "id" UUID NOT NULL,
    "cotizacionId" UUID NOT NULL,
    "productId" UUID,
    "productNameSnapshot" TEXT NOT NULL,
    "productImageSnapshot" TEXT,
    "qty" DECIMAL(12,3) NOT NULL,
    "unitPrice" DECIMAL(12,2) NOT NULL,
    "lineTotal" DECIMAL(12,2) NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "CotizacionItem_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "Cotizacion_createdByUserId_idx" ON "Cotizacion"("createdByUserId");

-- CreateIndex
CREATE INDEX "Cotizacion_customerId_idx" ON "Cotizacion"("customerId");

-- CreateIndex
CREATE INDEX "Cotizacion_customerPhone_idx" ON "Cotizacion"("customerPhone");

-- CreateIndex
CREATE INDEX "Cotizacion_createdAt_idx" ON "Cotizacion"("createdAt");

-- CreateIndex
CREATE INDEX "CotizacionItem_cotizacionId_idx" ON "CotizacionItem"("cotizacionId");

-- CreateIndex
CREATE INDEX "CotizacionItem_productId_idx" ON "CotizacionItem"("productId");

-- AddForeignKey
ALTER TABLE "Cotizacion" ADD CONSTRAINT "Cotizacion_createdByUserId_fkey" FOREIGN KEY ("createdByUserId") REFERENCES "users"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "Cotizacion" ADD CONSTRAINT "Cotizacion_customerId_fkey" FOREIGN KEY ("customerId") REFERENCES "Client"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "CotizacionItem" ADD CONSTRAINT "CotizacionItem_cotizacionId_fkey" FOREIGN KEY ("cotizacionId") REFERENCES "Cotizacion"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "CotizacionItem" ADD CONSTRAINT "CotizacionItem_productId_fkey" FOREIGN KEY ("productId") REFERENCES "Product"("id") ON DELETE SET NULL ON UPDATE CASCADE;
