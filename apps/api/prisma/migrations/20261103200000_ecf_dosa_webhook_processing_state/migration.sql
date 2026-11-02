-- Estado de procesamiento persistido del evento de webhook.
--
-- Motivo: antes el evento se insertaba y las credenciales se guardaban despues,
-- sin dejar rastro de si ese segundo paso ocurrio. Un fallo entre ambos dejaba
-- el evento como recibido pero incompleto, y el reenvio del proveedor respondia
-- "duplicado" sin arreglarlo.
--
-- Ahora cada evento declara su estado:
--   PENDING_CREDENTIALS -> insertado, credenciales aun no guardadas
--   COMPLETE            -> credenciales guardadas (o no habia ninguna)
--
-- Un reenvio de un evento en PENDING_CREDENTIALS lo REANUDA en lugar de darlo
-- por duplicado.
--
-- Migracion aditiva:
--   * El valor por defecto inicial 'COMPLETE' rellena las filas existentes, que
--     se procesaron con el codigo anterior y no tienen credenciales pendientes.
--   * Despues se cambia el valor por defecto a 'PENDING_CREDENTIALS', que es el
--     estado correcto para cualquier insercion que no lo declare explicitamente.

ALTER TABLE "ecf_dosa_webhook_events"
    ADD COLUMN "processing_state" VARCHAR(32) NOT NULL DEFAULT 'COMPLETE',
    ADD COLUMN "credentials_stored_at" TIMESTAMP(3);

ALTER TABLE "ecf_dosa_webhook_events"
    ALTER COLUMN "processing_state" SET DEFAULT 'PENDING_CREDENTIALS';

CREATE INDEX "ecf_dosa_webhook_events_processing_state_idx"
    ON "ecf_dosa_webhook_events" ("processing_state");
