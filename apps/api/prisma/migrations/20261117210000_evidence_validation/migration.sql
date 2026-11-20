-- Resultado de las validaciones del comprobante y quien reviso el pago.
-- `validation` guarda las comprobaciones aplicadas antes de activar.

ALTER TABLE "license_payment_orders"
  ADD COLUMN "validation" JSONB,
  ADD COLUMN "reviewed_by" VARCHAR(120),
  ADD COLUMN "reviewed_at" TIMESTAMP(3),
  ADD COLUMN "review_note" VARCHAR(500);
