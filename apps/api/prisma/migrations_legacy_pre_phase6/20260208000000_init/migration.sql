-- Enable UUID generation (Prisma typically uses gen_random_uuid())
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- CreateEnum
DO $$
BEGIN
    CREATE TYPE "Role" AS ENUM ('ADMIN', 'ASISTENTE', 'MARKETING', 'VENDEDOR');
EXCEPTION
    WHEN duplicate_object THEN NULL;
END $$;

-- CreateTable
CREATE TABLE IF NOT EXISTS "User" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "email" TEXT NOT NULL,
    "passwordHash" TEXT NOT NULL,
    "nombreCompleto" TEXT NOT NULL,
    "telefono" TEXT NOT NULL,
    "edad" INTEGER NOT NULL,
    "tieneHijos" BOOLEAN NOT NULL DEFAULT false,
    "estaCasado" BOOLEAN NOT NULL DEFAULT false,
    "casaPropia" BOOLEAN NOT NULL DEFAULT false,
    "vehiculo" BOOLEAN NOT NULL DEFAULT false,
    "licenciaConducir" BOOLEAN NOT NULL DEFAULT false,
    "role" "Role" NOT NULL,
    "blocked" BOOLEAN NOT NULL DEFAULT false,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "User_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX IF NOT EXISTS "User_email_key" ON "User"("email");

-- CreateTable
CREATE TABLE IF NOT EXISTS "Product" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "nombre" TEXT NOT NULL,
    "precio" NUMERIC(12,2) NOT NULL,
    "costo" NUMERIC(12,2) NOT NULL,
    "fotoUrl" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "Product_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE IF NOT EXISTS "Client" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "nombre" TEXT NOT NULL,
    "telefono" TEXT NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "Client_pkey" PRIMARY KEY ("id")
);

