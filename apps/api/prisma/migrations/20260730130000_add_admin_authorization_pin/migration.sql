ALTER TABLE "app_config"
ADD COLUMN IF NOT EXISTS "admin_authorization_pin_hash" TEXT;
