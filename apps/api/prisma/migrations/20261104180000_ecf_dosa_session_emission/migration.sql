-- Emisión automática de sesiones de certificación DOSA.
--
-- Migración ADITIVA y retrocompatible:
--   * `app_config.ecf_contact_email`: correo de facturación electrónica de la
--     empresa. Se captura una sola vez y se reutiliza al pedir la sesión, para
--     no volver a pedírselo al cliente. `NOT NULL DEFAULT ''` no altera ninguna
--     fila histórica: las empresas existentes quedan con «no configurado».
--   * `ecf_dosa_certification_sessions.session_*`: metadatos de la sesión
--     emitida por el proveedor. Son columnas NULL, así que el historial previo
--     sigue siendo válido sin backfill.
--
-- No se modifica ningún dato existente y no se toca ningún otro dominio.

-- AlterTable
ALTER TABLE "app_config" ADD COLUMN "ecf_contact_email" VARCHAR(254) NOT NULL DEFAULT '';

-- AlterTable
ALTER TABLE "ecf_dosa_certification_sessions" ADD COLUMN "session_expires_at" TIMESTAMP(3);
ALTER TABLE "ecf_dosa_certification_sessions" ADD COLUMN "session_issued_at" TIMESTAMP(3);
ALTER TABLE "ecf_dosa_certification_sessions" ADD COLUMN "session_lease_until" TIMESTAMP(3);
