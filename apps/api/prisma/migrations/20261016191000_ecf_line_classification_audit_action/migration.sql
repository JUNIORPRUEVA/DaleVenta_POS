-- Valor de auditoría para la clasificación fiscal supervisada (F1).
--
-- Aditivo y de una sola sentencia: el enum gana un valor y nada más. No se usa
-- dentro de esta misma migración, así que PostgreSQL lo acepta sin problema
-- (`ADD VALUE` no puede usarse en la misma transacción que lo consume).

-- AlterEnum
ALTER TYPE "ecf_audit_action" ADD VALUE 'LINE_CLASSIFICATION_CONFIRMED';
