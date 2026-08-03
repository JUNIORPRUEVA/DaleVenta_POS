ALTER TABLE "Sale"
ADD COLUMN IF NOT EXISTS "client_request_id" TEXT;

CREATE UNIQUE INDEX IF NOT EXISTS "Sale_company_id_client_request_id_key"
ON "Sale"("company_id", "client_request_id");
