ALTER TABLE "CompanyManualEntry"
  ADD COLUMN IF NOT EXISTS "starterKey" TEXT,
  ADD COLUMN IF NOT EXISTS "normalizedTitle" TEXT NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS "contentHash" TEXT NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS "moduleScopeKey" TEXT NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS "targetRolesKey" TEXT NOT NULL DEFAULT '';

-- Stable key for built-in starter entries.
UPDATE "CompanyManualEntry"
SET "starterKey" = CASE
  WHEN "title" = 'Atencion y registro correcto del cliente' THEN 'starter-clientes-registro-correcto'
  WHEN "title" = 'Politica base de cotizaciones y precios' THEN 'starter-cotizaciones-politica-base-precios'
  WHEN "title" = 'Responsabilidad al actualizar estados y datos' THEN 'starter-general-responsabilidad-actualizacion'
  WHEN "title" = 'Guia rapida de uso de modulos principales' THEN 'starter-general-guia-rapida-modulos'
  ELSE "starterKey"
END
WHERE "starterKey" IS NULL;

-- Backfill deterministic dedupe fields.
UPDATE "CompanyManualEntry" e
SET
  "normalizedTitle" = trim(regexp_replace(lower(translate(coalesce(e."title", ''), 'ÁÀÄÂáàäâÉÈËÊéèëêÍÌÏÎíìïîÓÒÖÔóòöôÚÙÜÛúùüûÑñ', 'AAAAaaaaEEEEeeeeIIIIiiiiOOOOooooUUUUuuuuNn')), '[^a-z0-9]+', ' ', 'g')),
  "moduleScopeKey" = trim(regexp_replace(lower(translate(coalesce(e."moduleKey", ''), 'ÁÀÄÂáàäâÉÈËÊéèëêÍÌÏÎíìïîÓÒÖÔóòöôÚÙÜÛúùüûÑñ', 'AAAAaaaaEEEEeeeeIIIIiiiiOOOOooooUUUUuuuuNn')), '[^a-z0-9]+', ' ', 'g')),
  "contentHash" = md5(trim(regexp_replace(lower(translate(coalesce(e."content", ''), 'ÁÀÄÂáàäâÉÈËÊéèëêÍÌÏÎíìïîÓÒÖÔóòöôÚÙÜÛúùüûÑñ', 'AAAAaaaaEEEEeeeeIIIIiiiiOOOOooooUUUUuuuuNn')), '[^a-z0-9]+', ' ', 'g'))),
  "targetRolesKey" = coalesce((
    SELECT string_agg(r::text, '|' ORDER BY r::text)
    FROM unnest(coalesce(e."targetRoles", ARRAY[]::"Role"[])) r
  ), '');

-- Remove exact duplicates, keep most recently updated record.
WITH ranked AS (
  SELECT
    "id",
    row_number() OVER (
      PARTITION BY
        "ownerId",
        "normalizedTitle",
        "kind",
        "audience",
        "moduleScopeKey",
        "targetRolesKey",
        "contentHash"
      ORDER BY "updatedAt" DESC, "createdAt" DESC, "id" DESC
    ) AS rn
  FROM "CompanyManualEntry"
)
DELETE FROM "CompanyManualEntry" e
USING ranked r
WHERE e."id" = r."id"
  AND r.rn > 1;

CREATE INDEX IF NOT EXISTS "CompanyManualEntry_ownerId_normalizedTitle_idx"
  ON "CompanyManualEntry"("ownerId", "normalizedTitle");

CREATE UNIQUE INDEX IF NOT EXISTS "company_manual_owner_starter_key_unique"
  ON "CompanyManualEntry"("ownerId", "starterKey");

CREATE UNIQUE INDEX IF NOT EXISTS "company_manual_dedup_unique"
  ON "CompanyManualEntry"(
    "ownerId",
    "normalizedTitle",
    "kind",
    "audience",
    "moduleScopeKey",
    "targetRolesKey",
    "contentHash"
  );
