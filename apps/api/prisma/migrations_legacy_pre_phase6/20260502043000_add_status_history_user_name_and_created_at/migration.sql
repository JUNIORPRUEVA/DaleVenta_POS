ALTER TABLE "service_order_status_history"
ADD COLUMN IF NOT EXISTS "changed_by_user_name" TEXT NULL,
ADD COLUMN IF NOT EXISTS "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP;

UPDATE "service_order_status_history" h
SET
  "changed_by_user_name" = COALESCE(NULLIF(u."nombre_completo", ''), h."changed_by_user_name"),
  "created_at" = COALESCE(h."created_at", h."changed_at")
FROM "users" u
WHERE h."changed_by_user_id" = u."id"
  AND (h."changed_by_user_name" IS NULL OR h."created_at" IS NULL);

UPDATE "service_order_status_history"
SET "created_at" = COALESCE("created_at", "changed_at")
WHERE "created_at" IS NULL;
