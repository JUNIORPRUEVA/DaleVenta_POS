-- CreateEnum
DO $$
BEGIN
    CREATE TYPE "PunchType" AS ENUM ('ENTRADA_LABOR', 'SALIDA_LABOR', 'SALIDA_PERMISO', 'ENTRADA_PERMISO', 'SALIDA_ALMUERZO', 'ENTRADA_ALMUERZO');
EXCEPTION
    WHEN duplicate_object THEN NULL;
END $$;

-- CreateTable
CREATE TABLE IF NOT EXISTS "Punch" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "userId" UUID NOT NULL,
    "type" "PunchType" NOT NULL,
    "timestamp" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT "Punch_pkey" PRIMARY KEY ("id")
);

-- Indexes
CREATE INDEX IF NOT EXISTS "Punch_userId_idx" ON "Punch"("userId");
CREATE INDEX IF NOT EXISTS "Punch_timestamp_idx" ON "Punch"("timestamp");

-- ForeignKeys
DO $$
BEGIN
    ALTER TABLE "Punch" ADD CONSTRAINT "Punch_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;
EXCEPTION
    WHEN duplicate_object THEN NULL;
END $$;
