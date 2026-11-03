-- Eventos recibidos del webhook de DOSA (`empresa.conectada`).
--
-- Guarda el payload REDACTADO: las credenciales del evento nunca se persisten.
-- La idempotencia la impone el índice único (company_id, dedupe_key): un
-- reintento del proveedor no crea una segunda fila ni reprocesa nada.
--
-- NO aplicada a UAT ni producción. Se valida en base desechable.

-- CreateTable
CREATE TABLE "ecf_dosa_webhook_events" (
    "id" UUID NOT NULL,
    "company_id" UUID NOT NULL,
    "dedupe_key" VARCHAR(128) NOT NULL,
    "event_type" VARCHAR(64) NOT NULL,
    "postulacion_id" VARCHAR(128),
    "estado_certificacion" VARCHAR(64),
    "raw_body_sha256" VARCHAR(64) NOT NULL,
    "payload_summary" JSONB NOT NULL,
    "signature_status" VARCHAR(48) NOT NULL,
    "received_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "ecf_dosa_webhook_events_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "ecf_dosa_webhook_events_company_id_dedupe_key_key" ON "ecf_dosa_webhook_events"("company_id", "dedupe_key");

-- CreateIndex
CREATE INDEX "ecf_dosa_webhook_events_company_id_received_at_idx" ON "ecf_dosa_webhook_events"("company_id", "received_at");

-- AddForeignKey
ALTER TABLE "ecf_dosa_webhook_events" ADD CONSTRAINT "ecf_dosa_webhook_events_company_id_fkey" FOREIGN KEY ("company_id") REFERENCES "companies"("id") ON DELETE CASCADE ON UPDATE CASCADE;
