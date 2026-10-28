-- APPYRA Guardian AI — estados de entrega reales (aditivo y compatible).
--
-- Motivo: un HTTP 200 de Meta solo significa "aceptado" (sent). Los estados
-- delivered/read llegan por webhook. Se añade READ y se guarda el último estado
-- del proveedor, el instante de lectura y el destinatario administrativo de la
-- alerta (necesario para enviar sin volver a leer la configuración global).
--
-- Todas las columnas son NULLables: las filas existentes siguen siendo válidas.

ALTER TYPE "GuardianAlertState" ADD VALUE IF NOT EXISTS 'READ';

ALTER TABLE "guardian_alerts"
    ADD COLUMN IF NOT EXISTS "recipient_number" VARCHAR(32),
    ADD COLUMN IF NOT EXISTS "last_provider_status" VARCHAR(20),
    ADD COLUMN IF NOT EXISTS "read_at" TIMESTAMP(3);

CREATE INDEX IF NOT EXISTS "guardian_alerts_provider_message_id_idx"
    ON "guardian_alerts"("provider_message_id");
