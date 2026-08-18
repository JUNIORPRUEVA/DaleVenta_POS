ALTER TABLE users
ADD COLUMN IF NOT EXISTS "workContractJobTitle" TEXT,
ADD COLUMN IF NOT EXISTS "workContractSalary" TEXT,
ADD COLUMN IF NOT EXISTS "workContractPaymentFrequency" TEXT,
ADD COLUMN IF NOT EXISTS "workContractPaymentMethod" TEXT,
ADD COLUMN IF NOT EXISTS "workContractWorkSchedule" TEXT,
ADD COLUMN IF NOT EXISTS "workContractWorkLocation" TEXT,
ADD COLUMN IF NOT EXISTS "workContractCustomClauses" TEXT,
ADD COLUMN IF NOT EXISTS "workContractStartDate" TIMESTAMP(3);
