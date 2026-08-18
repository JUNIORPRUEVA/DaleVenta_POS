-- Add Service.orderNumber (short human-friendly order identifier)

ALTER TABLE "Service"
  ADD COLUMN IF NOT EXISTS "orderNumber" TEXT;

-- Unique index (allows multiple NULLs)
CREATE UNIQUE INDEX IF NOT EXISTS "Service_orderNumber_key" ON "Service"("orderNumber");
