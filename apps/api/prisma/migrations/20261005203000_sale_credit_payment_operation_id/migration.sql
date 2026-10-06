ALTER TABLE "sale_credit_payments"
ADD COLUMN "operation_id" TEXT;

CREATE UNIQUE INDEX "sale_credit_payments_company_operation_key"
ON "sale_credit_payments"("company_id", "operation_id");
