CREATE TABLE IF NOT EXISTS "deposit_banks" (
  "id" UUID NOT NULL DEFAULT gen_random_uuid(),
  "company_id" UUID NOT NULL,
  "name" TEXT NOT NULL,
  "active" BOOLEAN NOT NULL DEFAULT true,
  "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updated_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "deposit_banks_pkey" PRIMARY KEY ("id")
);

CREATE TABLE IF NOT EXISTS "deposit_bank_accounts" (
  "id" UUID NOT NULL DEFAULT gen_random_uuid(),
  "bank_id" UUID NOT NULL,
  "label" TEXT NOT NULL,
  "account_number" TEXT,
  "active" BOOLEAN NOT NULL DEFAULT true,
  "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updated_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "deposit_bank_accounts_pkey" PRIMARY KEY ("id")
);

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'deposit_banks_company_id_fkey') THEN
    ALTER TABLE "deposit_banks"
      ADD CONSTRAINT "deposit_banks_company_id_fkey"
      FOREIGN KEY ("company_id") REFERENCES "companies"("id")
      ON DELETE CASCADE ON UPDATE CASCADE;
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'deposit_bank_accounts_bank_id_fkey') THEN
    ALTER TABLE "deposit_bank_accounts"
      ADD CONSTRAINT "deposit_bank_accounts_bank_id_fkey"
      FOREIGN KEY ("bank_id") REFERENCES "deposit_banks"("id")
      ON DELETE CASCADE ON UPDATE CASCADE;
  END IF;
END $$;

CREATE UNIQUE INDEX IF NOT EXISTS "deposit_banks_company_id_name_key"
  ON "deposit_banks"("company_id", "name");

CREATE INDEX IF NOT EXISTS "deposit_banks_company_id_active_idx"
  ON "deposit_banks"("company_id", "active");

CREATE UNIQUE INDEX IF NOT EXISTS "deposit_bank_accounts_bank_id_label_key"
  ON "deposit_bank_accounts"("bank_id", "label");

CREATE INDEX IF NOT EXISTS "deposit_bank_accounts_bank_id_active_idx"
  ON "deposit_bank_accounts"("bank_id", "active");
