ALTER TABLE "Cotizacion"
  ADD COLUMN IF NOT EXISTS "fiscal_tax_enabled" BOOLEAN NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS "fiscal_price_mode" "tax_price_mode" NOT NULL DEFAULT 'NO_TAX',
  ADD COLUMN IF NOT EXISTS "taxable_base" DECIMAL(12,2) NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS "tax_amount" DECIMAL(12,2) NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS "exempt_amount" DECIMAL(12,2) NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS "discount_amount" DECIMAL(12,2) NOT NULL DEFAULT 0;

ALTER TABLE "CotizacionItem"
  ADD COLUMN IF NOT EXISTS "tax_treatment" "product_tax_treatment" NOT NULL DEFAULT 'INHERIT',
  ADD COLUMN IF NOT EXISTS "tax_price_mode" "tax_price_mode" NOT NULL DEFAULT 'NO_TAX',
  ADD COLUMN IF NOT EXISTS "gross_amount" DECIMAL(12,2) NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS "line_discount_amount" DECIMAL(12,2) NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS "taxable_base" DECIMAL(12,2) NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS "tax_rate" DECIMAL(5,4) NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS "tax_amount" DECIMAL(12,2) NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS "exempt_amount" DECIMAL(12,2) NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS "tax_included" BOOLEAN NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS "tax_exempt" BOOLEAN NOT NULL DEFAULT false;

UPDATE "Cotizacion"
SET
  "fiscal_tax_enabled" = COALESCE("fiscal_tax_enabled", false),
  "fiscal_price_mode" = CASE WHEN "includeItbis" THEN 'TAX_ADDED'::"tax_price_mode" ELSE "fiscal_price_mode" END,
  "tax_amount" = CASE WHEN "includeItbis" THEN "itbisAmount" ELSE "tax_amount" END,
  "taxable_base" = CASE WHEN "includeItbis" THEN "subtotal" ELSE "taxable_base" END,
  "exempt_amount" = CASE WHEN "includeItbis" THEN 0 ELSE "subtotal" END
WHERE "fiscal_tax_enabled" = false;

UPDATE "CotizacionItem"
SET
  "gross_amount" = CASE WHEN "gross_amount" = 0 THEN "lineTotal" ELSE "gross_amount" END,
  "taxable_base" = CASE WHEN "taxable_base" = 0 AND "tax_exempt" = false THEN "lineTotal" ELSE "taxable_base" END,
  "exempt_amount" = CASE WHEN "taxable_base" = 0 AND "tax_amount" = 0 THEN "lineTotal" ELSE "exempt_amount" END;
