ALTER TABLE "CotizacionItem"
ADD COLUMN IF NOT EXISTS "originalUnitPriceSnapshot" DECIMAL(12, 2);
