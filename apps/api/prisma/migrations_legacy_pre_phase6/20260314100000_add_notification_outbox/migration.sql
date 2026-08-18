-- Notification Outbox (WhatsApp via Evolution)

CREATE EXTENSION IF NOT EXISTS pgcrypto;

DO $$
BEGIN
  CREATE TYPE "NotificationChannel" AS ENUM ('WHATSAPP');
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

DO $$
BEGIN
  CREATE TYPE "NotificationStatus" AS ENUM ('PENDING', 'SENDING', 'SENT', 'FAILED');
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

CREATE TABLE IF NOT EXISTS notification_outbox (
  id UUID NOT NULL DEFAULT gen_random_uuid(),
  channel "NotificationChannel" NOT NULL DEFAULT 'WHATSAPP',
  status "NotificationStatus" NOT NULL DEFAULT 'PENDING',
  template_key TEXT NOT NULL,
  dedupe_key TEXT,
  message_text TEXT NOT NULL,
  payload JSONB,
  recipient_user_id UUID,
  to_number TEXT NOT NULL,
  to_number_normalized TEXT NOT NULL DEFAULT '',
  attempts INTEGER NOT NULL DEFAULT 0,
  next_attempt_at TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  locked_at TIMESTAMP(3),
  locked_by TEXT,
  last_error TEXT,
  last_status_code INTEGER,
  sent_at TIMESTAMP(3),
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT notification_outbox_pkey PRIMARY KEY (id)
);

CREATE UNIQUE INDEX IF NOT EXISTS notification_outbox_dedupe_key_key
  ON notification_outbox (dedupe_key);

CREATE INDEX IF NOT EXISTS notification_outbox_status_next_attempt_idx
  ON notification_outbox (status, next_attempt_at);

CREATE INDEX IF NOT EXISTS notification_outbox_locked_at_idx
  ON notification_outbox (locked_at);

CREATE INDEX IF NOT EXISTS notification_outbox_recipient_user_id_idx
  ON notification_outbox (recipient_user_id);

DO $$
BEGIN
  ALTER TABLE notification_outbox
    ADD CONSTRAINT notification_outbox_recipient_user_id_fkey
    FOREIGN KEY (recipient_user_id) REFERENCES users(id)
    ON DELETE SET NULL ON UPDATE CASCADE;
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;
