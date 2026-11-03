-- Auditoría de la ASISTENCIA autorizada (empresa → FULLTECH).
--
-- Por qué: sin registro, ni la empresa ni FULLTECH pueden demostrar quién
-- consultó un expediente ajeno, cuándo y con qué alcance. Es la contrapartida
-- necesaria de haber abierto el acceso bajo concesión.
--
-- Aditivo: solo añade valores al enum existente. No renombra ni elimina nada,
-- así que los registros históricos siguen siendo válidos.

ALTER TYPE "ecf_audit_action" ADD VALUE IF NOT EXISTS 'SUPPORT_GRANT_CREATED';
ALTER TYPE "ecf_audit_action" ADD VALUE IF NOT EXISTS 'SUPPORT_GRANT_REVOKED';
ALTER TYPE "ecf_audit_action" ADD VALUE IF NOT EXISTS 'SUPPORT_GRANT_EXPIRED';
ALTER TYPE "ecf_audit_action" ADD VALUE IF NOT EXISTS 'SUPPORT_ACCESS_GRANTED';
ALTER TYPE "ecf_audit_action" ADD VALUE IF NOT EXISTS 'SUPPORT_ACCESS_DENIED';
