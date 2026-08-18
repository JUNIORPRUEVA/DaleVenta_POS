CREATE EXTENSION IF NOT EXISTS pgcrypto;

DO $$
BEGIN
	IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'Role') THEN
		CREATE TYPE "Role" AS ENUM ('ADMIN', 'ASISTENTE', 'MARKETING', 'VENDEDOR', 'TECNICO');
	END IF;
END $$;

DO $$
BEGIN
	IF EXISTS (SELECT 1 FROM pg_type WHERE typname = 'Role') THEN
		IF NOT EXISTS (
			SELECT 1 FROM pg_enum e
			JOIN pg_type t ON t.oid = e.enumtypid
			WHERE t.typname = 'Role' AND e.enumlabel = 'ADMIN'
		) THEN
			ALTER TYPE "Role" ADD VALUE 'ADMIN';
		END IF;

		IF NOT EXISTS (
			SELECT 1 FROM pg_enum e
			JOIN pg_type t ON t.oid = e.enumtypid
			WHERE t.typname = 'Role' AND e.enumlabel = 'ASISTENTE'
		) THEN
			ALTER TYPE "Role" ADD VALUE 'ASISTENTE';
		END IF;

		IF NOT EXISTS (
			SELECT 1 FROM pg_enum e
			JOIN pg_type t ON t.oid = e.enumtypid
			WHERE t.typname = 'Role' AND e.enumlabel = 'MARKETING'
		) THEN
			ALTER TYPE "Role" ADD VALUE 'MARKETING';
		END IF;

		IF NOT EXISTS (
			SELECT 1 FROM pg_enum e
			JOIN pg_type t ON t.oid = e.enumtypid
			WHERE t.typname = 'Role' AND e.enumlabel = 'VENDEDOR'
		) THEN
			ALTER TYPE "Role" ADD VALUE 'VENDEDOR';
		END IF;

		IF NOT EXISTS (
			SELECT 1 FROM pg_enum e
			JOIN pg_type t ON t.oid = e.enumtypid
			WHERE t.typname = 'Role' AND e.enumlabel = 'TECNICO'
		) THEN
			ALTER TYPE "Role" ADD VALUE 'TECNICO';
		END IF;
	END IF;
END $$;

DO $$
BEGIN
	IF to_regclass('public.users') IS NULL AND to_regclass('public."User"') IS NOT NULL THEN
		ALTER TABLE "User" RENAME TO users;
	END IF;
END $$;

CREATE TABLE IF NOT EXISTS users (
	"id" UUID PRIMARY KEY DEFAULT gen_random_uuid(),
	"email" TEXT NOT NULL,
	"passwordHash" TEXT NOT NULL,
	"nombreCompleto" TEXT NOT NULL,
	"telefono" TEXT NOT NULL,
	"telefonoFamiliar" TEXT,
	"cedula" TEXT,
	"fotoCedulaUrl" TEXT,
	"fotoLicenciaUrl" TEXT,
	"fotoPersonalUrl" TEXT,
	"edad" INTEGER NOT NULL DEFAULT 0,
	"tieneHijos" BOOLEAN NOT NULL DEFAULT false,
	"estaCasado" BOOLEAN NOT NULL DEFAULT false,
	"casaPropia" BOOLEAN NOT NULL DEFAULT false,
	"vehiculo" BOOLEAN NOT NULL DEFAULT false,
	"licenciaConducir" BOOLEAN NOT NULL DEFAULT false,
	"role" "Role" NOT NULL DEFAULT 'ADMIN',
	"blocked" BOOLEAN NOT NULL DEFAULT false,
	"createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
	"updatedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP
);

ALTER TABLE users ADD COLUMN IF NOT EXISTS "id" UUID DEFAULT gen_random_uuid();
ALTER TABLE users ADD COLUMN IF NOT EXISTS "email" TEXT;
ALTER TABLE users ADD COLUMN IF NOT EXISTS "passwordHash" TEXT;
ALTER TABLE users ADD COLUMN IF NOT EXISTS "nombreCompleto" TEXT;
ALTER TABLE users ADD COLUMN IF NOT EXISTS "telefono" TEXT;
ALTER TABLE users ADD COLUMN IF NOT EXISTS "telefonoFamiliar" TEXT;
ALTER TABLE users ADD COLUMN IF NOT EXISTS "cedula" TEXT;
ALTER TABLE users ADD COLUMN IF NOT EXISTS "fotoCedulaUrl" TEXT;
ALTER TABLE users ADD COLUMN IF NOT EXISTS "fotoLicenciaUrl" TEXT;
ALTER TABLE users ADD COLUMN IF NOT EXISTS "fotoPersonalUrl" TEXT;
ALTER TABLE users ADD COLUMN IF NOT EXISTS "edad" INTEGER;
ALTER TABLE users ADD COLUMN IF NOT EXISTS "tieneHijos" BOOLEAN DEFAULT false;
ALTER TABLE users ADD COLUMN IF NOT EXISTS "estaCasado" BOOLEAN DEFAULT false;
ALTER TABLE users ADD COLUMN IF NOT EXISTS "casaPropia" BOOLEAN DEFAULT false;
ALTER TABLE users ADD COLUMN IF NOT EXISTS "vehiculo" BOOLEAN DEFAULT false;
ALTER TABLE users ADD COLUMN IF NOT EXISTS "licenciaConducir" BOOLEAN DEFAULT false;
ALTER TABLE users ADD COLUMN IF NOT EXISTS "role" "Role";
ALTER TABLE users ADD COLUMN IF NOT EXISTS "blocked" BOOLEAN DEFAULT false;
ALTER TABLE users ADD COLUMN IF NOT EXISTS "createdAt" TIMESTAMP(3) DEFAULT CURRENT_TIMESTAMP;
ALTER TABLE users ADD COLUMN IF NOT EXISTS "updatedAt" TIMESTAMP(3) DEFAULT CURRENT_TIMESTAMP;

UPDATE users SET "passwordHash" = '' WHERE "passwordHash" IS NULL;
UPDATE users SET "nombreCompleto" = COALESCE("nombreCompleto", '') WHERE "nombreCompleto" IS NULL;
UPDATE users SET "telefono" = COALESCE("telefono", '') WHERE "telefono" IS NULL;
UPDATE users SET "edad" = 0 WHERE "edad" IS NULL;
UPDATE users SET "tieneHijos" = false WHERE "tieneHijos" IS NULL;
UPDATE users SET "estaCasado" = false WHERE "estaCasado" IS NULL;
UPDATE users SET "casaPropia" = false WHERE "casaPropia" IS NULL;
UPDATE users SET "vehiculo" = false WHERE "vehiculo" IS NULL;
UPDATE users SET "licenciaConducir" = false WHERE "licenciaConducir" IS NULL;
UPDATE users SET "role" = 'ADMIN'::"Role" WHERE "role" IS NULL;
UPDATE users SET "blocked" = false WHERE "blocked" IS NULL;
UPDATE users SET "createdAt" = CURRENT_TIMESTAMP WHERE "createdAt" IS NULL;
UPDATE users SET "updatedAt" = CURRENT_TIMESTAMP WHERE "updatedAt" IS NULL;

ALTER TABLE users ALTER COLUMN "id" SET DEFAULT gen_random_uuid();
ALTER TABLE users ALTER COLUMN "email" SET NOT NULL;
ALTER TABLE users ALTER COLUMN "passwordHash" SET NOT NULL;
ALTER TABLE users ALTER COLUMN "nombreCompleto" SET NOT NULL;
ALTER TABLE users ALTER COLUMN "telefono" SET NOT NULL;
ALTER TABLE users ALTER COLUMN "edad" SET NOT NULL;
ALTER TABLE users ALTER COLUMN "tieneHijos" SET NOT NULL;
ALTER TABLE users ALTER COLUMN "estaCasado" SET NOT NULL;
ALTER TABLE users ALTER COLUMN "casaPropia" SET NOT NULL;
ALTER TABLE users ALTER COLUMN "vehiculo" SET NOT NULL;
ALTER TABLE users ALTER COLUMN "licenciaConducir" SET NOT NULL;
ALTER TABLE users ALTER COLUMN "role" SET NOT NULL;
ALTER TABLE users ALTER COLUMN "blocked" SET NOT NULL;
ALTER TABLE users ALTER COLUMN "createdAt" SET NOT NULL;
ALTER TABLE users ALTER COLUMN "updatedAt" SET NOT NULL;

DO $$
BEGIN
	IF NOT EXISTS (
		SELECT 1
		FROM pg_constraint
		WHERE conname = 'users_pkey'
			AND conrelid = 'users'::regclass
	) THEN
		ALTER TABLE users ADD CONSTRAINT users_pkey PRIMARY KEY ("id");
	END IF;
END $$;

CREATE UNIQUE INDEX IF NOT EXISTS "users_email_key" ON users("email");
CREATE UNIQUE INDEX IF NOT EXISTS "users_cedula_key" ON users("cedula");
