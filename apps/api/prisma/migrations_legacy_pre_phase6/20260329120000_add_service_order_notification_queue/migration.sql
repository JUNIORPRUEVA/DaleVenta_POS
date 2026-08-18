CREATE EXTENSION IF NOT EXISTS pgcrypto;

DO $$
BEGIN
  CREATE TYPE "NotificationContentType" AS ENUM ('TEXT', 'DOCUMENT');
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

DO $$
BEGIN
  CREATE TYPE "ServiceOrderNotificationJobKind" AS ENUM ('THIRTY_MINUTES_BEFORE');
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

DO $$
BEGIN
  CREATE TYPE "ServiceOrderNotificationJobStatus" AS ENUM (
    'PENDING',
    'PROCESSING',
    'COMPLETED',
    'FAILED',
    'CANCELLED'
  );
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

ALTER TABLE notification_outbox
  ADD COLUMN IF NOT EXISTS content_type "NotificationContentType" NOT NULL DEFAULT 'TEXT',
  ADD COLUMN IF NOT EXISTS media_base64 TEXT,
  ADD COLUMN IF NOT EXISTS media_file_name TEXT,
  ADD COLUMN IF NOT EXISTS media_mime_type TEXT;

ALTER TABLE service_orders
  ADD COLUMN IF NOT EXISTS scheduled_for TIMESTAMP(3),
  ADD COLUMN IF NOT EXISTS technician_confirmed_at TIMESTAMP(3),
  ADD COLUMN IF NOT EXISTS technician_confirmed_by UUID;

CREATE INDEX IF NOT EXISTS service_orders_scheduled_for_idx
  ON service_orders (scheduled_for);

CREATE INDEX IF NOT EXISTS service_orders_technician_confirmed_by_idx
  ON service_orders (technician_confirmed_by);

DO $$
BEGIN
  ALTER TABLE service_orders
    ADD CONSTRAINT service_orders_technician_confirmed_by_fkey
    FOREIGN KEY (technician_confirmed_by) REFERENCES users(id)
    ON DELETE SET NULL ON UPDATE CASCADE;
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

CREATE TABLE IF NOT EXISTS service_order_notification_jobs (
  id UUID NOT NULL DEFAULT gen_random_uuid(),
  order_id UUID NOT NULL,
  kind "ServiceOrderNotificationJobKind" NOT NULL,
  status "ServiceOrderNotificationJobStatus" NOT NULL DEFAULT 'PENDING',
  dedupe_key TEXT NOT NULL,
  run_at TIMESTAMP(3) NOT NULL,
  payload JSONB,
  attempts INTEGER NOT NULL DEFAULT 0,
  locked_at TIMESTAMP(3),
  locked_by TEXT,
  last_error TEXT,
  completed_at TIMESTAMP(3),
  created_at TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT service_order_notification_jobs_pkey PRIMARY KEY (id)
);

CREATE UNIQUE INDEX IF NOT EXISTS service_order_notification_jobs_dedupe_key_key
  ON service_order_notification_jobs (dedupe_key);

CREATE INDEX IF NOT EXISTS service_order_notification_jobs_order_id_idx
  ON service_order_notification_jobs (order_id);

CREATE INDEX IF NOT EXISTS service_order_notification_jobs_status_run_at_idx
  ON service_order_notification_jobs (status, run_at);

CREATE INDEX IF NOT EXISTS service_order_notification_jobs_locked_at_idx
  ON service_order_notification_jobs (locked_at);

DO $$
BEGIN
  ALTER TABLE service_order_notification_jobs
    ADD CONSTRAINT service_order_notification_jobs_order_id_fkey
    FOREIGN KEY (order_id) REFERENCES service_orders(id)
    ON DELETE CASCADE ON UPDATE CASCADE;
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

CREATE OR REPLACE FUNCTION set_service_order_notification_jobs_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = CURRENT_TIMESTAMP;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_service_order_notification_jobs_updated_at ON service_order_notification_jobs;

CREATE TRIGGER trg_service_order_notification_jobs_updated_at
BEFORE UPDATE ON service_order_notification_jobs
FOR EACH ROW
EXECUTE FUNCTION set_service_order_notification_jobs_updated_at();