-- Ensure extension for UUID generation
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- Create table if it does not exist with the expected minimal shape
CREATE TABLE IF NOT EXISTS "Product" (
  "id" UUID NOT NULL DEFAULT gen_random_uuid(),
  "nombre" TEXT NOT NULL,
  "categoria" TEXT NOT NULL DEFAULT '',
  "costo" NUMERIC(12,2) NOT NULL DEFAULT 0,
  "precio" NUMERIC(12,2) NOT NULL DEFAULT 0,
  "imagen" TEXT,
  CONSTRAINT "Product_pkey" PRIMARY KEY ("id")
);

-- Add required columns if the table already existed with another structure
ALTER TABLE "Product" ADD COLUMN IF NOT EXISTS "nombre" TEXT;
ALTER TABLE "Product" ADD COLUMN IF NOT EXISTS "categoria" TEXT;
ALTER TABLE "Product" ADD COLUMN IF NOT EXISTS "costo" NUMERIC(12,2);
ALTER TABLE "Product" ADD COLUMN IF NOT EXISTS "precio" NUMERIC(12,2);
ALTER TABLE "Product" ADD COLUMN IF NOT EXISTS "imagen" TEXT;

-- Migrate data from legacy columns when present
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'Product' AND column_name = 'fotoUrl'
  ) THEN
    EXECUTE 'UPDATE "Product" SET "imagen" = COALESCE("imagen", "fotoUrl") WHERE "imagen" IS NULL';
  END IF;
END $$;

-- Backfill required values and enforce minimal constraints
UPDATE "Product" SET "nombre" = COALESCE(NULLIF("nombre", ''), 'Producto') WHERE "nombre" IS NULL OR "nombre" = '';
UPDATE "Product" SET "categoria" = COALESCE(NULLIF("categoria", ''), 'General') WHERE "categoria" IS NULL OR "categoria" = '';
UPDATE "Product" SET "costo" = COALESCE("costo", 0) WHERE "costo" IS NULL;
UPDATE "Product" SET "precio" = COALESCE("precio", 0) WHERE "precio" IS NULL;

ALTER TABLE "Product" ALTER COLUMN "nombre" SET NOT NULL;
ALTER TABLE "Product" ALTER COLUMN "categoria" SET NOT NULL;
ALTER TABLE "Product" ALTER COLUMN "costo" SET NOT NULL;
ALTER TABLE "Product" ALTER COLUMN "precio" SET NOT NULL;

ALTER TABLE "Product" ALTER COLUMN "categoria" SET DEFAULT 'General';
ALTER TABLE "Product" ALTER COLUMN "costo" SET DEFAULT 0;
ALTER TABLE "Product" ALTER COLUMN "precio" SET DEFAULT 0;

-- Drop legacy columns not required by the app
ALTER TABLE "Product" DROP COLUMN IF EXISTS "sku";
ALTER TABLE "Product" DROP COLUMN IF EXISTS "stock";
ALTER TABLE "Product" DROP COLUMN IF EXISTS "creadoEn";
ALTER TABLE "Product" DROP COLUMN IF EXISTS "actualizadoEn";
ALTER TABLE "Product" DROP COLUMN IF EXISTS "eliminadoEn";
ALTER TABLE "Product" DROP COLUMN IF EXISTS "version";
ALTER TABLE "Product" DROP COLUMN IF EXISTS "actualizadoPorId";
ALTER TABLE "Product" DROP COLUMN IF EXISTS "ID del dispositivo";
ALTER TABLE "Product" DROP COLUMN IF EXISTS "fotoUrl";
ALTER TABLE "Product" DROP COLUMN IF EXISTS "categoryId";
ALTER TABLE "Product" DROP COLUMN IF EXISTS "createdAt";
ALTER TABLE "Product" DROP COLUMN IF EXISTS "updatedAt";
