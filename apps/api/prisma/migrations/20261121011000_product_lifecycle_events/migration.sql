-- Durable audit/tombstone independent from the physical product FK.
CREATE TABLE product_lifecycle_events (
 id UUID NOT NULL,company_id UUID NOT NULL,product_id UUID NOT NULL,
 actor_user_id UUID,operation_id VARCHAR(160),action VARCHAR(40) NOT NULL,
 details JSONB NOT NULL DEFAULT '{}',created_at TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
 CONSTRAINT product_lifecycle_events_pkey PRIMARY KEY(id)
);
CREATE UNIQUE INDEX product_lifecycle_events_company_operation_key ON product_lifecycle_events(company_id,operation_id);
CREATE INDEX product_lifecycle_events_company_id_product_id_created_at_idx ON product_lifecycle_events(company_id,product_id,created_at);
