CREATE TABLE "crm_commercial_settings" (
  "id" TEXT NOT NULL DEFAULT 'global',
  "selected_whatsapp_instance_id" TEXT,
  "selected_whatsapp_instance_name" TEXT,
  "enabled" BOOLEAN NOT NULL DEFAULT false,
  "updated_by_user_id" UUID,
  "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updated_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

  CONSTRAINT "crm_commercial_settings_pkey" PRIMARY KEY ("id")
);

ALTER TABLE "crm_commercial_settings"
ADD CONSTRAINT "crm_commercial_settings_updated_by_user_id_fkey"
FOREIGN KEY ("updated_by_user_id") REFERENCES "users"("id")
ON DELETE SET NULL ON UPDATE CASCADE;
