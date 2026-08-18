CREATE TYPE "order_document_flow_status" AS ENUM (
  'pending_preparation',
  'ready_for_review',
  'ready_for_finalization',
  'approved',
  'rejected',
  'sent'
);

CREATE TABLE "order_document_flows" (
  "id" UUID NOT NULL,
  "order_id" UUID NOT NULL,
  "status" "order_document_flow_status" NOT NULL DEFAULT 'pending_preparation',
  "invoice_draft_json" JSONB,
  "warranty_draft_json" JSONB,
  "invoice_final_url" TEXT,
  "warranty_final_url" TEXT,
  "prepared_by" UUID,
  "approved_by" UUID,
  "sent_at" TIMESTAMP(3),
  "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updated_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

  CONSTRAINT "order_document_flows_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX "order_document_flows_order_id_key" ON "order_document_flows"("order_id");
CREATE INDEX "order_document_flows_status_idx" ON "order_document_flows"("status");
CREATE INDEX "order_document_flows_prepared_by_idx" ON "order_document_flows"("prepared_by");
CREATE INDEX "order_document_flows_approved_by_idx" ON "order_document_flows"("approved_by");
CREATE INDEX "order_document_flows_sent_at_idx" ON "order_document_flows"("sent_at");

ALTER TABLE "order_document_flows"
  ADD CONSTRAINT "order_document_flows_order_id_fkey"
  FOREIGN KEY ("order_id") REFERENCES "service_orders"("id") ON DELETE CASCADE ON UPDATE CASCADE;

ALTER TABLE "order_document_flows"
  ADD CONSTRAINT "order_document_flows_prepared_by_fkey"
  FOREIGN KEY ("prepared_by") REFERENCES "users"("id") ON DELETE SET NULL ON UPDATE CASCADE;

ALTER TABLE "order_document_flows"
  ADD CONSTRAINT "order_document_flows_approved_by_fkey"
  FOREIGN KEY ("approved_by") REFERENCES "users"("id") ON DELETE SET NULL ON UPDATE CASCADE;