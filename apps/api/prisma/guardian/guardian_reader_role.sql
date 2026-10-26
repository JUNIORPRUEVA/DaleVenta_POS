-- APPYRA Guardian AI — rol de solo lectura para el diagnóstico IA.
--
-- NO es una migración de Prisma: crea un rol con credenciales y debe ejecutarse
-- manualmente por un DBA en cada entorno, con una contraseña propia.
--
-- Uso (UAT/DEV, nunca producción sin autorización):
--   psql -h <host> -U <admin> -d <db> -v reader_password="'...'" -f guardian_reader_role.sql
--
-- Principios:
--   * SELECT únicamente sobre tablas necesarias para diagnóstico.
--   * Ningún privilegio sobre escritura, secuencias ni DDL.
--   * statement_timeout por sesión para acotar consultas costosas.

BEGIN;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'guardian_reader') THEN
    CREATE ROLE guardian_reader LOGIN;
  END IF;
END
$$;

-- La contraseña se pasa como variable psql (fuera de comillas dólar para que
-- psql la interpole). Nunca se escribe en el repositorio.
ALTER ROLE guardian_reader LOGIN PASSWORD :'reader_password';

-- Sin privilegios heredados.
ALTER ROLE guardian_reader NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT NOREPLICATION BYPASSRLS;

GRANT CONNECT ON DATABASE :"dbname" TO guardian_reader;
GRANT USAGE ON SCHEMA public TO guardian_reader;

-- Lectura mínima para diagnóstico de negocio (sin datos fiscales sensibles).
GRANT SELECT ON
  companies,
  cash_sessions,
  "Sale",
  "SaleItem",
  telemetry_outbox,
  guardian_incidents,
  guardian_incident_groups,
  guardian_diagnoses,
  guardian_evidences,
  guardian_alerts,
  guardian_alert_attempts
TO guardian_reader;

-- Límites de ejecución por sesión.
ALTER ROLE guardian_reader SET statement_timeout = '5000ms';
ALTER ROLE guardian_reader SET idle_in_transaction_session_timeout = '10000ms';

-- Defensa en profundidad: revocar explícitamente cualquier escritura.
REVOKE INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER ON ALL TABLES IN SCHEMA public FROM guardian_reader;
REVOKE CREATE ON SCHEMA public FROM guardian_reader;

-- Reaplicar los SELECT necesarios (el REVOKE anterior los quita).
GRANT SELECT ON
  companies,
  cash_sessions,
  "Sale",
  "SaleItem",
  telemetry_outbox,
  guardian_incidents,
  guardian_incident_groups,
  guardian_diagnoses,
  guardian_evidences,
  guardian_alerts,
  guardian_alert_attempts
TO guardian_reader;

COMMIT;
