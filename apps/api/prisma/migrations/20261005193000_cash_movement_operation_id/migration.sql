ALTER TABLE "cash_movements"
ADD COLUMN "operation_id" TEXT;

CREATE UNIQUE INDEX "cash_movements_company_operation_key"
ON "cash_movements"("company_id", "operation_id");
