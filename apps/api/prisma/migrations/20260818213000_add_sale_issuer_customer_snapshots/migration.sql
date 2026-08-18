ALTER TABLE "Sale"
  ADD COLUMN "issuer_name_snapshot" TEXT,
  ADD COLUMN "issuer_tax_id_snapshot" TEXT,
  ADD COLUMN "issuer_address_snapshot" TEXT,
  ADD COLUMN "issuer_phone_snapshot" TEXT,
  ADD COLUMN "issuer_email_snapshot" TEXT,
  ADD COLUMN "customer_address_snapshot" TEXT,
  ADD COLUMN "customer_phone_snapshot" TEXT;
