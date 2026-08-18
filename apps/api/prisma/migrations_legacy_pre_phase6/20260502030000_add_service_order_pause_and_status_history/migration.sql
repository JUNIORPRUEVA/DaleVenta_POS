ALTER TYPE "service_order_status"
ADD VALUE IF NOT EXISTS 'en_pausa';

ALTER TABLE "service_orders"
ADD COLUMN IF NOT EXISTS "last_status_changed_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
ADD COLUMN IF NOT EXISTS "last_status_changed_by_user_id" UUID NULL;

CREATE TABLE IF NOT EXISTS "service_order_status_history" (
  "id" UUID NOT NULL DEFAULT gen_random_uuid(),
  "service_order_id" UUID NOT NULL,
  "previous_status" "service_order_status" NULL,
  "next_status" "service_order_status" NOT NULL,
  "changed_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "changed_by_user_id" UUID NULL,
  "note" TEXT NULL,
  CONSTRAINT "service_order_status_history_pkey" PRIMARY KEY ("id")
);

CREATE INDEX IF NOT EXISTS "service_orders_last_status_changed_at_idx"
  ON "service_orders"("last_status_changed_at");
CREATE INDEX IF NOT EXISTS "service_orders_last_status_changed_by_user_id_idx"
  ON "service_orders"("last_status_changed_by_user_id");
CREATE INDEX IF NOT EXISTS "service_orders_status_last_status_changed_at_idx"
  ON "service_orders"("status", "last_status_changed_at");

CREATE INDEX IF NOT EXISTS "service_order_status_history_service_order_id_idx"
  ON "service_order_status_history"("service_order_id");
CREATE INDEX IF NOT EXISTS "service_order_status_history_service_order_id_changed_at_idx"
  ON "service_order_status_history"("service_order_id", "changed_at");
CREATE INDEX IF NOT EXISTS "service_order_status_history_changed_by_user_id_idx"
  ON "service_order_status_history"("changed_by_user_id");

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'service_orders_last_status_changed_by_user_id_fkey'
  ) THEN
    ALTER TABLE "service_orders"
      ADD CONSTRAINT "service_orders_last_status_changed_by_user_id_fkey"
      FOREIGN KEY ("last_status_changed_by_user_id") REFERENCES "users"("id")
      ON DELETE SET NULL ON UPDATE CASCADE;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'service_order_status_history_service_order_id_fkey'
  ) THEN
    ALTER TABLE "service_order_status_history"
      ADD CONSTRAINT "service_order_status_history_service_order_id_fkey"
      FOREIGN KEY ("service_order_id") REFERENCES "service_orders"("id")
      ON DELETE CASCADE ON UPDATE CASCADE;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'service_order_status_history_changed_by_user_id_fkey'
  ) THEN
    ALTER TABLE "service_order_status_history"
      ADD CONSTRAINT "service_order_status_history_changed_by_user_id_fkey"
      FOREIGN KEY ("changed_by_user_id") REFERENCES "users"("id")
      ON DELETE SET NULL ON UPDATE CASCADE;
  END IF;
END $$;

UPDATE "service_orders"
SET "last_status_changed_at" = COALESCE("updated_at", "created_at"),
    "last_status_changed_by_user_id" = COALESCE("last_status_changed_by_user_id", "created_by")
WHERE "last_status_changed_at" IS NULL OR "last_status_changed_by_user_id" IS NULL;

INSERT INTO "service_order_status_history" (
  "service_order_id",
  "previous_status",
  "next_status",
  "changed_at",
  "changed_by_user_id",
  "note"
)
SELECT
  so."id",
  NULL,
  so."status",
  COALESCE(so."last_status_changed_at", so."created_at"),
  COALESCE(so."last_status_changed_by_user_id", so."created_by"),
  'Estado inicial migrado'
FROM "service_orders" so
WHERE NOT EXISTS (
  SELECT 1
  FROM "service_order_status_history" h
  WHERE h."service_order_id" = so."id"
);
