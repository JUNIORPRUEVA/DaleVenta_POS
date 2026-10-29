-- APPYRA Guardian AI — Fase 1.2: integridad referencial de alertas.
--
-- Aditivo: solo agrega una restricción FK que faltaba. No modifica columnas ni
-- elimina datos. Las alertas huérfanas de UAT se sanearon aparte, con respaldo
-- previo (`pg_dump`) y conteos registrados antes/después.
--
-- Efecto: al eliminar un incidente (o su empresa en cascada) sus alertas y sus
-- intentos desaparecen con él, evitando registros huérfanos.

ALTER TABLE "guardian_alerts"
  ADD CONSTRAINT "guardian_alerts_incident_id_fkey"
  FOREIGN KEY ("incident_id") REFERENCES "guardian_incidents"("id")
  ON DELETE CASCADE ON UPDATE CASCADE;
