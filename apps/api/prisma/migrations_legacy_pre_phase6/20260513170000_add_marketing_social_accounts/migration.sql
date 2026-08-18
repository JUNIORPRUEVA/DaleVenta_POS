DO $$ BEGIN
  CREATE TYPE "marketing_social_account_type" AS ENUM ('FACEBOOK','INSTAGRAM','WHATSAPP');
EXCEPTION WHEN duplicate_object THEN null;
END $$;

CREATE TABLE IF NOT EXISTS "marketing_social_accounts" (
  "id" UUID NOT NULL DEFAULT gen_random_uuid(),
  "company_id" UUID NOT NULL,
  "type" "marketing_social_account_type" NOT NULL,
  "account_name" TEXT NOT NULL,
  "username" TEXT,
  "password_encrypted" TEXT,
  "profile_link" TEXT,
  "whatsapp_number" TEXT,
  "whatsapp_wa_link" TEXT,
  "observations" TEXT,
  "avatar_url" TEXT,
  "is_active" BOOLEAN NOT NULL DEFAULT true,
  "created_by_user_id" UUID,
  "updated_by_user_id" UUID,
  "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updated_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "deleted_at" TIMESTAMP(3),
  CONSTRAINT "marketing_social_accounts_pkey" PRIMARY KEY ("id")
);

CREATE INDEX IF NOT EXISTS "marketing_social_accounts_company_id_type_is_active_idx"
  ON "marketing_social_accounts"("company_id", "type", "is_active");
CREATE INDEX IF NOT EXISTS "marketing_social_accounts_company_id_updated_at_idx"
  ON "marketing_social_accounts"("company_id", "updated_at");
CREATE INDEX IF NOT EXISTS "marketing_social_accounts_company_id_deleted_at_idx"
  ON "marketing_social_accounts"("company_id", "deleted_at");

DO $$ BEGIN
  ALTER TABLE "marketing_social_accounts"
  ADD CONSTRAINT "marketing_social_accounts_created_by_user_id_fkey"
  FOREIGN KEY ("created_by_user_id") REFERENCES "users"("id")
  ON DELETE SET NULL ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN null;
END $$;

DO $$ BEGIN
  ALTER TABLE "marketing_social_accounts"
  ADD CONSTRAINT "marketing_social_accounts_updated_by_user_id_fkey"
  FOREIGN KEY ("updated_by_user_id") REFERENCES "users"("id")
  ON DELETE SET NULL ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN null;
END $$;
