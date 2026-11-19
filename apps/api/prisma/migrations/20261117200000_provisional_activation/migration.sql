-- Activacion provisional: el plan entra en vigor al subir el comprobante, pero
-- queda pendiente de verificacion. Se guarda el estado anterior para poder
-- revertir sin tocar periodos ya pagados.

CREATE TYPE "license_activation_state" AS ENUM ('NONE', 'PROVISIONAL', 'CONFIRMED', 'REVERTED', 'EXPIRED_REVIEW');

ALTER TABLE "license_payment_orders"
  ADD COLUMN "activation_state" "license_activation_state" NOT NULL DEFAULT 'NONE',
  ADD COLUMN "provisional_until" TIMESTAMP(3),
  ADD COLUMN "license_snapshot" JSONB;

CREATE INDEX "license_payment_orders_activation_state_provisional_until_idx"
  ON "license_payment_orders"("activation_state", "provisional_until");
