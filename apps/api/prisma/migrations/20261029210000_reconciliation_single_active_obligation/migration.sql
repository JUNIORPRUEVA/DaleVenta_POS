-- APPYRA/FullPOS: UNA sola obligación activa por operación + rastro de cada
-- declaración (actor, importe, nota).
--
-- Motivo: antes, dos encargados (o dos dispositivos) declarando dinero recibido
-- para el MISMO `clientRequestId` creaban obligaciones PENDING independientes y
-- el importe pendiente quedaba duplicado. Ahora:
--   * la operación tiene UNA obligación activa (PENDING);
--   * cada declaración o rectificación queda en
--     `sale_reconciliation_declaration_events` (append-only, con actor, importe
--     anterior y nuevo, nota y hora).
--
-- Migración ADITIVA en lo estructural (tabla nueva + columnas con valor por
-- defecto). El único UPDATE marca como SUPERSEDED las filas PENDING duplicadas
-- que ya existieran para una misma operación: no se borra ninguna fila y siguen
-- consultables como evidencia.

-- 1) Rastro append-only de declaraciones.
CREATE TABLE "sale_reconciliation_declaration_events" (
    "id" UUID NOT NULL,
    "company_id" UUID NOT NULL,
    "obligation_id" UUID NOT NULL,
    "client_request_id" VARCHAR(128) NOT NULL,
    "declaration_hash" VARCHAR(64) NOT NULL,
    "kind" VARCHAR(32) NOT NULL,
    "total_declared" DECIMAL(12,2) NOT NULL,
    "previous_total" DECIMAL(12,2),
    "actor_user_id" TEXT,
    "actor_role" VARCHAR(32),
    "note" TEXT,
    "declared_at_utc" TIMESTAMP(3) NOT NULL,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "sale_reconciliation_declaration_events_pkey" PRIMARY KEY ("id")
);

CREATE INDEX "sale_reconciliation_declaration_events_company_id_client_reque_idx"
    ON "sale_reconciliation_declaration_events" ("company_id", "client_request_id", "created_at");

CREATE INDEX "sale_reconciliation_declaration_events_obligation_id_created_at_idx"
    ON "sale_reconciliation_declaration_events" ("obligation_id", "created_at");

-- 2) Contadores de la obligación.
ALTER TABLE "sale_reconciliation_obligations"
    ADD COLUMN IF NOT EXISTS "declaration_count" INTEGER NOT NULL DEFAULT 1,
    ADD COLUMN IF NOT EXISTS "version" INTEGER NOT NULL DEFAULT 1,
    ADD COLUMN IF NOT EXISTS "last_declared_at_utc" TIMESTAMP(3);

UPDATE "sale_reconciliation_obligations"
   SET "last_declared_at_utc" = "declared_at_utc"
 WHERE "last_declared_at_utc" IS NULL;

-- 3) Antes de imponer la unicidad: las obligaciones PENDING duplicadas de una
--    misma operación se marcan SUPERSEDED (la más antigua conserva el importe;
--    las demás se quedan como evidencia, sin saldo pendiente).
WITH ranked AS (
    SELECT "id",
           ROW_NUMBER() OVER (
               PARTITION BY "company_id", "client_request_id"
               ORDER BY "created_at" ASC, "id" ASC
           ) AS position
      FROM "sale_reconciliation_obligations"
     WHERE "status" = 'PENDING'
)
UPDATE "sale_reconciliation_obligations" o
   SET "status" = 'SUPERSEDED',
       "resolution_note" = COALESCE(
           o."resolution_note",
           'Marcada como duplicada al pasar a una sola obligación activa por operación'
       ),
       "updated_at" = CURRENT_TIMESTAMP
  FROM ranked
 WHERE o."id" = ranked."id" AND ranked.position > 1;

-- 4) UNA sola obligación activa por operación (índice parcial).
CREATE UNIQUE INDEX IF NOT EXISTS "sale_reconciliation_obligations_active_operation_key"
    ON "sale_reconciliation_obligations" ("company_id", "client_request_id")
    WHERE "status" = 'PENDING';
