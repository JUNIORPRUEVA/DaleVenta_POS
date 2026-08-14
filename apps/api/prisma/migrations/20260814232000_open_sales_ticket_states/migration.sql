CREATE TABLE "open_sales_ticket_states" (
  "company_id" UUID NOT NULL,
  "active_ticket_id" TEXT,
  "tickets" JSONB NOT NULL DEFAULT '[]',
  "updated_by_user_id" UUID,
  "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updated_at" TIMESTAMP(3) NOT NULL,

  CONSTRAINT "open_sales_ticket_states_pkey" PRIMARY KEY ("company_id"),
  CONSTRAINT "open_sales_ticket_states_company_id_fkey"
    FOREIGN KEY ("company_id") REFERENCES "companies"("id")
    ON DELETE CASCADE ON UPDATE CASCADE
);

CREATE INDEX "open_sales_ticket_states_updated_at_idx"
  ON "open_sales_ticket_states"("updated_at");
