DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'product_tax_treatment') THEN
    CREATE TYPE "product_tax_treatment" AS ENUM ('INHERIT', 'TAXABLE', 'EXEMPT');
  END IF;
END
$$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'tax_price_mode') THEN
    CREATE TYPE "tax_price_mode" AS ENUM ('NO_TAX', 'TAX_ADDED', 'TAX_INCLUDED');
  END IF;
END
$$;

CREATE EXTENSION IF NOT EXISTS "btree_gist";

ALTER TABLE "companies"
  ADD COLUMN IF NOT EXISTS "tax_enabled" BOOLEAN NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS "default_tax_id" UUID,
  ADD COLUMN IF NOT EXISTS "default_tax_rate" DECIMAL(5,4) NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS "prices_include_tax" BOOLEAN NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS "ncf_enabled" BOOLEAN NOT NULL DEFAULT false;

ALTER TABLE "Product"
  ADD COLUMN IF NOT EXISTS "tax_treatment" "product_tax_treatment" NOT NULL DEFAULT 'INHERIT',
  ADD COLUMN IF NOT EXISTS "tax_rate" DECIMAL(5,4),
  ADD COLUMN IF NOT EXISTS "tax_price_mode" "tax_price_mode";

ALTER TABLE "Sale"
  ADD COLUMN IF NOT EXISTS "fiscal_tax_enabled" BOOLEAN NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS "fiscal_price_mode" "tax_price_mode" NOT NULL DEFAULT 'NO_TAX',
  ADD COLUMN IF NOT EXISTS "taxable_base" DECIMAL(12,2) NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS "tax_amount" DECIMAL(12,2) NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS "exempt_amount" DECIMAL(12,2) NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS "discount_amount" DECIMAL(12,2) NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS "fiscal_voucher_type" TEXT,
  ADD COLUMN IF NOT EXISTS "ncf" TEXT,
  ADD COLUMN IF NOT EXISTS "fiscal_customer_tax_id" TEXT,
  ADD COLUMN IF NOT EXISTS "fiscal_customer_name" TEXT;

ALTER TABLE "SaleItem"
  ADD COLUMN IF NOT EXISTS "gross_amount" DECIMAL(12,2) NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS "line_discount_amount" DECIMAL(12,2) NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS "taxable_base" DECIMAL(12,2) NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS "tax_rate" DECIMAL(5,4) NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS "tax_amount" DECIMAL(12,2) NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS "exempt_amount" DECIMAL(12,2) NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS "tax_included" BOOLEAN NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS "tax_exempt" BOOLEAN NOT NULL DEFAULT false;

ALTER TABLE "Client"
  ADD COLUMN IF NOT EXISTS "tax_id" TEXT,
  ADD COLUMN IF NOT EXISTS "business_name" TEXT,
  ADD COLUMN IF NOT EXISTS "tax_id_type" TEXT;

CREATE TABLE IF NOT EXISTS "ncf_sequences" (
  "id" UUID NOT NULL,
  "company_id" UUID NOT NULL,
  "voucher_type" TEXT NOT NULL,
  "prefix" TEXT NOT NULL,
  "start_number" INTEGER NOT NULL DEFAULT 1,
  "next_number" INTEGER NOT NULL DEFAULT 1,
  "end_number" INTEGER NOT NULL,
  "valid_until" TIMESTAMP(3),
  "active" BOOLEAN NOT NULL DEFAULT true,
  "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updated_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "ncf_sequences_pkey" PRIMARY KEY ("id")
);

ALTER TABLE "ncf_sequences"
  ADD COLUMN IF NOT EXISTS "start_number" INTEGER NOT NULL DEFAULT 1;

CREATE TABLE IF NOT EXISTS "ncf_audit_logs" (
  "id" UUID NOT NULL,
  "company_id" UUID NOT NULL,
  "sequence_id" UUID,
  "sale_id" UUID,
  "user_id" UUID,
  "ncf" TEXT NOT NULL,
  "type" TEXT NOT NULL,
  "action" TEXT NOT NULL,
  "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "ncf_audit_logs_pkey" PRIMARY KEY ("id")
);

CREATE TABLE IF NOT EXISTS "taxes" (
  "id" UUID NOT NULL,
  "company_id" UUID NOT NULL,
  "name" TEXT NOT NULL,
  "rate" DECIMAL(5,4) NOT NULL,
  "is_active" BOOLEAN NOT NULL DEFAULT true,
  "is_default" BOOLEAN NOT NULL DEFAULT false,
  "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updated_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "taxes_pkey" PRIMARY KEY ("id")
);

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'ncf_sequences_company_id_fkey'
  ) THEN
    ALTER TABLE "ncf_sequences"
      ADD CONSTRAINT "ncf_sequences_company_id_fkey"
      FOREIGN KEY ("company_id") REFERENCES "companies"("id")
      ON DELETE CASCADE ON UPDATE CASCADE;
  END IF;
END
$$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'taxes_company_id_fkey'
  ) THEN
    ALTER TABLE "taxes"
      ADD CONSTRAINT "taxes_company_id_fkey"
      FOREIGN KEY ("company_id") REFERENCES "companies"("id")
      ON DELETE CASCADE ON UPDATE CASCADE;
  END IF;
END
$$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'ncf_audit_logs_company_id_fkey'
  ) THEN
    ALTER TABLE "ncf_audit_logs"
      ADD CONSTRAINT "ncf_audit_logs_company_id_fkey"
      FOREIGN KEY ("company_id") REFERENCES "companies"("id")
      ON DELETE CASCADE ON UPDATE CASCADE;
  END IF;
END
$$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'ncf_audit_logs_sequence_id_fkey'
  ) THEN
    ALTER TABLE "ncf_audit_logs"
      ADD CONSTRAINT "ncf_audit_logs_sequence_id_fkey"
      FOREIGN KEY ("sequence_id") REFERENCES "ncf_sequences"("id")
      ON DELETE SET NULL ON UPDATE CASCADE;
  END IF;
END
$$;

CREATE UNIQUE INDEX IF NOT EXISTS "Sale_company_id_ncf_key" ON "Sale"("company_id", "ncf");
CREATE INDEX IF NOT EXISTS "Sale_company_id_fiscal_voucher_type_idx" ON "Sale"("company_id", "fiscal_voucher_type");
CREATE INDEX IF NOT EXISTS "ncf_sequences_company_id_voucher_type_prefix_idx"
  ON "ncf_sequences"("company_id", "voucher_type", "prefix");
CREATE UNIQUE INDEX IF NOT EXISTS "ncf_sequences_company_id_voucher_type_active_key"
  ON "ncf_sequences"("company_id", "voucher_type")
  WHERE "active" = true;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'ncf_sequences_no_overlap'
  ) THEN
    ALTER TABLE "ncf_sequences"
      ADD CONSTRAINT "ncf_sequences_no_overlap"
      EXCLUDE USING gist (
        "company_id" WITH =,
        "voucher_type" WITH =,
        int4range("start_number", "end_number", '[]') WITH &&
      );
  END IF;
END
$$;
CREATE INDEX IF NOT EXISTS "ncf_sequences_company_id_voucher_type_active_idx"
  ON "ncf_sequences"("company_id", "voucher_type", "active");
CREATE INDEX IF NOT EXISTS "ncf_audit_logs_company_id_ncf_idx" ON "ncf_audit_logs"("company_id", "ncf");
CREATE INDEX IF NOT EXISTS "ncf_audit_logs_company_id_type_created_at_idx"
  ON "ncf_audit_logs"("company_id", "type", "created_at");
CREATE INDEX IF NOT EXISTS "ncf_audit_logs_sale_id_idx" ON "ncf_audit_logs"("sale_id");
CREATE UNIQUE INDEX IF NOT EXISTS "taxes_company_id_name_key" ON "taxes"("company_id", "name");
CREATE INDEX IF NOT EXISTS "taxes_company_id_is_active_idx" ON "taxes"("company_id", "is_active");
CREATE INDEX IF NOT EXISTS "taxes_company_id_is_default_idx" ON "taxes"("company_id", "is_default");
