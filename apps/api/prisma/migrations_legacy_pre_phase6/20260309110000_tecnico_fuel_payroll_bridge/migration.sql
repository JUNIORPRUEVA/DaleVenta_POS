ALTER TABLE "vehiculos"
ADD COLUMN IF NOT EXISTS "marca" TEXT,
ADD COLUMN IF NOT EXISTS "modelo" TEXT,
ADD COLUMN IF NOT EXISTS "capacidad_tanque_litros" DECIMAL(10,2);

ALTER TABLE "PayrollEmployee"
ADD COLUMN IF NOT EXISTS "user_id" UUID;

UPDATE "PayrollEmployee" AS pe
SET "user_id" = pe."id"
WHERE pe."user_id" IS NULL
  AND EXISTS (
    SELECT 1
    FROM "users" AS u
    WHERE u."id" = pe."id"
  );

CREATE UNIQUE INDEX IF NOT EXISTS "PayrollEmployee_user_id_key"
ON "PayrollEmployee"("user_id");

CREATE INDEX IF NOT EXISTS "PayrollEmployee_user_id_idx"
ON "PayrollEmployee"("user_id");

DO $$
BEGIN
  ALTER TABLE "PayrollEmployee"
  ADD CONSTRAINT "PayrollEmployee_user_id_fkey"
  FOREIGN KEY ("user_id") REFERENCES "users"("id")
  ON DELETE SET NULL
  ON UPDATE CASCADE;
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

ALTER TABLE "PayrollEntry"
ADD COLUMN IF NOT EXISTS "pago_combustible_tecnico_id" UUID;

CREATE UNIQUE INDEX IF NOT EXISTS "PayrollEntry_pago_combustible_tecnico_id_key"
ON "PayrollEntry"("pago_combustible_tecnico_id");

CREATE INDEX IF NOT EXISTS "PayrollEntry_pago_combustible_tecnico_id_idx"
ON "PayrollEntry"("pago_combustible_tecnico_id");

DO $$
BEGIN
  ALTER TABLE "PayrollEntry"
  ADD CONSTRAINT "PayrollEntry_pago_combustible_tecnico_id_fkey"
  FOREIGN KEY ("pago_combustible_tecnico_id") REFERENCES "pagos_combustible_tecnicos"("id")
  ON DELETE SET NULL
  ON UPDATE CASCADE;
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

UPDATE "users" AS u
SET "vehiculo" = EXISTS (
  SELECT 1
  FROM "vehiculos" AS v
  WHERE v."tecnico_id_propietario" = u."id"
    AND COALESCE(v."es_empresa", false) = false
    AND COALESCE(v."activo", true) = true
);