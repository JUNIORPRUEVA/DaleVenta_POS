-- Ensure legacy SaleItem columns do not break inserts from current Prisma model

ALTER TABLE "SaleItem" ALTER COLUMN "unitPriceSold" SET DEFAULT 0;
ALTER TABLE "SaleItem" ALTER COLUMN "unitCostSnapshot" SET DEFAULT 0;
ALTER TABLE "SaleItem" ALTER COLUMN "lineTotal" SET DEFAULT 0;
ALTER TABLE "SaleItem" ALTER COLUMN "lineCost" SET DEFAULT 0;
ALTER TABLE "SaleItem" ALTER COLUMN "lineProfit" SET DEFAULT 0;

UPDATE "SaleItem" SET "unitPriceSold" = 0 WHERE "unitPriceSold" IS NULL;
UPDATE "SaleItem" SET "unitCostSnapshot" = 0 WHERE "unitCostSnapshot" IS NULL;
UPDATE "SaleItem" SET "lineTotal" = 0 WHERE "lineTotal" IS NULL;
UPDATE "SaleItem" SET "lineCost" = 0 WHERE "lineCost" IS NULL;
UPDATE "SaleItem" SET "lineProfit" = 0 WHERE "lineProfit" IS NULL;
