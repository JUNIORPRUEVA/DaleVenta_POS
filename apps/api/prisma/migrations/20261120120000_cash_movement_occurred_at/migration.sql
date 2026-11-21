-- Keep receipt time intact. Legacy rows have no client occurrence evidence.
ALTER TABLE "cash_movements" ADD COLUMN "occurred_at" TIMESTAMP(3);
