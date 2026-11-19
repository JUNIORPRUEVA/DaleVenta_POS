-- Analisis (solo asesor) del comprobante: fecha, importe, banco y referencia.
-- No cambia el estado de la orden ni activa nada por si solo.

ALTER TABLE "license_payment_evidence"
  ADD COLUMN "extracted" JSONB,
  ADD COLUMN "extracted_at" TIMESTAMP(3),
  ADD COLUMN "extracted_source" VARCHAR(32);
