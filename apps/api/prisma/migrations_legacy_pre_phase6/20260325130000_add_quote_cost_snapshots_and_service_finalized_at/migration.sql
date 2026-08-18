ALTER TABLE "service_orders"
  ADD COLUMN IF NOT EXISTS "finalized_at" TIMESTAMP(3);

CREATE INDEX IF NOT EXISTS "service_orders_finalized_at_idx" ON "service_orders"("finalized_at");

UPDATE "service_orders"
SET "finalized_at" = "updated_at"
WHERE "status" = 'finalizado' AND "finalized_at" IS NULL;

ALTER TABLE "CotizacionItem"
  ADD COLUMN IF NOT EXISTS "costUnitSnapshot" DECIMAL(12,2),
  ADD COLUMN IF NOT EXISTS "subtotalCost" DECIMAL(12,2),
  ADD COLUMN IF NOT EXISTS "profit" DECIMAL(12,2);

ALTER TABLE "Cotizacion"
  ADD COLUMN IF NOT EXISTS "subtotalCost" DECIMAL(12,2),
  ADD COLUMN IF NOT EXISTS "totalCost" DECIMAL(12,2),
  ADD COLUMN IF NOT EXISTS "totalProfit" DECIMAL(12,2);

UPDATE "CotizacionItem" ci
SET
  "costUnitSnapshot" = p."costo",
  "subtotalCost" = (ci."qty" * p."costo"),
  "profit" = (ci."lineTotal" - (ci."qty" * p."costo"))
FROM "Product" p
WHERE ci."productId" = p."id"
  AND ci."costUnitSnapshot" IS NULL;

WITH quote_costs AS (
  SELECT
    ci."cotizacionId" AS id,
    SUM(ci."subtotalCost") AS subtotal_cost,
    SUM(ci."profit") AS total_profit,
    COUNT(*) AS line_count,
    COUNT(ci."costUnitSnapshot") AS line_count_with_cost
  FROM "CotizacionItem" ci
  GROUP BY ci."cotizacionId"
)
UPDATE "Cotizacion" c
SET
  "subtotalCost" = qc.subtotal_cost,
  "totalCost" = qc.subtotal_cost,
  "totalProfit" = qc.total_profit
FROM quote_costs qc
WHERE c."id" = qc.id
  AND qc.line_count = qc.line_count_with_cost;