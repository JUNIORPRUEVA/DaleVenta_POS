-- Additive opt-in activity collection. No license, company or historical event updates.
CREATE TABLE "company_usage_pulses" (
  "id" UUID NOT NULL,
  "company_id" UUID NOT NULL,
  "session_id" UUID NOT NULL,
  "stream_id" UUID NOT NULL,
  "sequence" INTEGER NOT NULL CHECK ("sequence" > 0),
  "observed_at" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "active_from" TIMESTAMPTZ(3),
  "active" BOOLEAN NOT NULL,
  "platform" VARCHAR(16) NOT NULL,
  "app_version" VARCHAR(80) NOT NULL,
  CONSTRAINT "company_usage_pulses_pkey" PRIMARY KEY ("id"),
  CONSTRAINT "company_usage_pulses_company_id_fkey" FOREIGN KEY ("company_id") REFERENCES "companies"("id") ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT "company_usage_pulses_interval_check" CHECK ("active_from" IS NULL OR ("active_from" <= "observed_at" AND "active_from" >= "observed_at" - INTERVAL '30 seconds'))
);
CREATE UNIQUE INDEX "company_usage_pulses_stream_sequence_key" ON "company_usage_pulses"("company_id", "session_id", "stream_id", "sequence");
CREATE INDEX "company_usage_pulses_company_id_observed_at_idx" ON "company_usage_pulses"("company_id", "observed_at");
CREATE INDEX "company_usage_pulses_observed_at_idx" ON "company_usage_pulses"("observed_at");
