-- APPYRA Guardian AI — estados de entrega con evidencia del proveedor.
--
-- ADITIVO Y COMPATIBLE: se añaden valores nuevos al enum y dos columnas
-- nulables. Los estados existentes conservan EXACTAMENTE su significado:
--   PENDING   -> esperando turno de envío
--   SENDING   -> reclamada por un worker
--   SENT      -> enviada sin id de proveedor (uso historico, no se reescribe)
--   DELIVERED -> entrega confirmada por webhook
--   FAILED_PERMANENT / DEAD -> fallo terminal
--
-- Nuevos:
--   QUEUED   -> encolada en el outbox local; el proveedor aun no la recibio
--   ACCEPTED -> el proveedor confirmo la recepcion con un id de mensaje
--   READ     -> el destinatario la abrio (webhook de lectura)
--
-- No hay BEGIN/COMMIT a propósito: `ALTER TYPE ... ADD VALUE` no puede usar el
-- valor nuevo dentro de la misma transaccion en la que se crea.

ALTER TYPE "GuardianAlertState" ADD VALUE IF NOT EXISTS 'QUEUED';
ALTER TYPE "GuardianAlertState" ADD VALUE IF NOT EXISTS 'ACCEPTED';
ALTER TYPE "GuardianAlertState" ADD VALUE IF NOT EXISTS 'READ';

ALTER TABLE "guardian_alerts" ADD COLUMN IF NOT EXISTS "accepted_at" TIMESTAMP(3);
ALTER TABLE "guardian_alerts" ADD COLUMN IF NOT EXISTS "read_at" TIMESTAMP(3);
