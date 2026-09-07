CREATE EXTENSION IF NOT EXISTS "pgcrypto";

CREATE TABLE IF NOT EXISTS "telemetry_outbox" (
  "id" UUID NOT NULL DEFAULT gen_random_uuid(),
  "event_id" UUID NOT NULL,
  "schema_version" INTEGER NOT NULL DEFAULT 1,
  "company_id" UUID NOT NULL,
  "event_type" VARCHAR(80) NOT NULL,
  "payload_json" JSONB NOT NULL,
  "status" VARCHAR(32) NOT NULL DEFAULT 'PENDING',
  "attempt_count" INTEGER NOT NULL DEFAULT 0,
  "next_attempt_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "occurred_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "sent_at" TIMESTAMP(3),
  "last_error" VARCHAR(1800),
  "locked_at" TIMESTAMP(3),
  "locked_by" VARCHAR(120),
  "dedupe_key" VARCHAR(240),
  "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updated_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "telemetry_outbox_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX IF NOT EXISTS "telemetry_outbox_event_id_key"
  ON "telemetry_outbox"("event_id");

CREATE UNIQUE INDEX IF NOT EXISTS "telemetry_outbox_dedupe_key_key"
  ON "telemetry_outbox"("dedupe_key")
  WHERE "dedupe_key" IS NOT NULL;

CREATE INDEX IF NOT EXISTS "telemetry_outbox_company_id_occurred_at_idx"
  ON "telemetry_outbox"("company_id", "occurred_at");

CREATE INDEX IF NOT EXISTS "telemetry_outbox_status_next_attempt_at_idx"
  ON "telemetry_outbox"("status", "next_attempt_at");

CREATE INDEX IF NOT EXISTS "telemetry_outbox_locked_at_idx"
  ON "telemetry_outbox"("locked_at");

CREATE INDEX IF NOT EXISTS "telemetry_outbox_event_type_idx"
  ON "telemetry_outbox"("event_type");

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'telemetry_outbox_company_id_fkey'
  ) THEN
    ALTER TABLE "telemetry_outbox"
      ADD CONSTRAINT "telemetry_outbox_company_id_fkey"
      FOREIGN KEY ("company_id") REFERENCES "companies"("id")
      ON DELETE CASCADE ON UPDATE CASCADE;
  END IF;
END $$;
