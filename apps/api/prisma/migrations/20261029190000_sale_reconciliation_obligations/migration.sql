-- APPYRA/FullPOS: obligaciones de conciliación por cobros declarados.
--
-- Migración ADITIVA: crea una tabla nueva. No altera ni borra ninguna tabla,
-- columna ni fila existente, por lo que las versiones 145–148 siguen
-- funcionando sin cambios y el rollback consiste en no usar la tabla.

CREATE TABLE "sale_reconciliation_obligations" (
    "id" UUID NOT NULL,
    "company_id" UUID NOT NULL,
    "client_request_id" VARCHAR(128) NOT NULL,
    "declaration_hash" VARCHAR(64) NOT NULL,
    "total_declared" DECIMAL(12,2) NOT NULL,
    "currency" VARCHAR(8) NOT NULL DEFAULT 'DOP',
    "payment_method" VARCHAR(32) NOT NULL DEFAULT 'cash',
    "declared_at_utc" TIMESTAMP(3) NOT NULL,
    "declared_by_user_id" TEXT,
    "declared_by_role" VARCHAR(32),
    "note" TEXT,
    "operation_fingerprint" VARCHAR(64),
    "attempt_payload" JSONB,
    "status" VARCHAR(24) NOT NULL DEFAULT 'PENDING',
    "resolved_at" TIMESTAMP(3),
    "resolved_by_user_id" TEXT,
    "resolution_note" TEXT,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "sale_reconciliation_obligations_pkey" PRIMARY KEY ("id")
);

-- Idempotencia: el reenvío exacto de la misma declaración no duplica.
CREATE UNIQUE INDEX "sale_reconciliation_obligations_company_id_client_reques_key"
    ON "sale_reconciliation_obligations" ("company_id", "client_request_id", "declaration_hash");

CREATE INDEX "sale_reconciliation_obligations_company_id_status_created_at_idx"
    ON "sale_reconciliation_obligations" ("company_id", "status", "created_at");

CREATE INDEX "sale_reconciliation_obligations_company_id_client_request_id_idx"
    ON "sale_reconciliation_obligations" ("company_id", "client_request_id");
