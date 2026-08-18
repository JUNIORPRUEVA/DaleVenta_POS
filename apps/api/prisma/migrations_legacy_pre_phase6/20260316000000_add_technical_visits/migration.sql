-- Create technical visit reports linked to Service orders (LEVANTAMIENTO)

CREATE TABLE IF NOT EXISTS "technical_visits" (
  "id" UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  "order_id" UUID NOT NULL,
  "technician_id" UUID NOT NULL,
  "report_description" TEXT NOT NULL,
  "installation_notes" TEXT NOT NULL,
  "estimated_products" JSONB NOT NULL DEFAULT '[]'::jsonb,
  "photos" JSONB NOT NULL DEFAULT '[]'::jsonb,
  "videos" JSONB NOT NULL DEFAULT '[]'::jsonb,
  "visit_date" TIMESTAMP NOT NULL DEFAULT now(),
  "created_at" TIMESTAMP NOT NULL DEFAULT now(),
  "updated_at" TIMESTAMP NOT NULL DEFAULT now(),
  CONSTRAINT "technical_visits_order_id_key" UNIQUE ("order_id"),
  CONSTRAINT "technical_visits_order_id_fkey" FOREIGN KEY ("order_id") REFERENCES "Service"("id") ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT "technical_visits_technician_id_fkey" FOREIGN KEY ("technician_id") REFERENCES "users"("id") ON DELETE RESTRICT ON UPDATE CASCADE
);

CREATE INDEX IF NOT EXISTS "technical_visits_order_id_idx" ON "technical_visits"("order_id");
CREATE INDEX IF NOT EXISTS "technical_visits_technician_id_idx" ON "technical_visits"("technician_id");
CREATE INDEX IF NOT EXISTS "technical_visits_visit_date_idx" ON "technical_visits"("visit_date");
