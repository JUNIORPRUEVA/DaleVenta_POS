-- Enforce dedup keys at DB level so older app nodes cannot insert blank keys.
CREATE OR REPLACE FUNCTION company_manual_compute_dedup_keys()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
  normalized_roles TEXT;
BEGIN
  SELECT COALESCE(string_agg(lower(trim(role_item::text)), '|' ORDER BY lower(trim(role_item::text))), '')
    INTO normalized_roles
  FROM unnest(COALESCE(NEW."targetRoles", ARRAY[]::"Role"[])) AS role_item
  WHERE trim(role_item::text) <> '';

  NEW."normalizedTitle" := trim(regexp_replace(
    lower(translate(COALESCE(NEW."title", ''), 'ÁÀÄÂáàäâÉÈËÊéèëêÍÌÏÎíìïîÓÒÖÔóòöôÚÙÜÛúùüûÑñ', 'AAAAaaaaEEEEeeeeIIIIiiiiOOOOooooUUUUuuuuNn')),
    '[^a-z0-9]+',
    ' ',
    'g'
  ));

  NEW."moduleScopeKey" := trim(regexp_replace(
    lower(translate(COALESCE(NEW."moduleKey", ''), 'ÁÀÄÂáàäâÉÈËÊéèëêÍÌÏÎíìïîÓÒÖÔóòöôÚÙÜÛúùüûÑñ', 'AAAAaaaaEEEEeeeeIIIIiiiiOOOOooooUUUUuuuuNn')),
    '[^a-z0-9]+',
    ' ',
    'g'
  ));

  NEW."targetRolesKey" := normalized_roles;

  NEW."contentHash" := md5(trim(regexp_replace(
    lower(translate(COALESCE(NEW."content", ''), 'ÁÀÄÂáàäâÉÈËÊéèëêÍÌÏÎíìïîÓÒÖÔóòöôÚÙÜÛúùüûÑñ', 'AAAAaaaaEEEEeeeeIIIIiiiiOOOOooooUUUUuuuuNn')),
    '[^a-z0-9]+',
    ' ',
    'g'
  )));

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS company_manual_set_dedup_keys_trigger ON "CompanyManualEntry";
CREATE TRIGGER company_manual_set_dedup_keys_trigger
BEFORE INSERT OR UPDATE OF "title", "moduleKey", "targetRoles", "content"
ON "CompanyManualEntry"
FOR EACH ROW
EXECUTE FUNCTION company_manual_compute_dedup_keys();

-- Backfill all rows in case legacy writers inserted empty keys.
UPDATE "CompanyManualEntry" e
SET
  "normalizedTitle" = trim(regexp_replace(lower(translate(COALESCE(e."title", ''), 'ÁÀÄÂáàäâÉÈËÊéèëêÍÌÏÎíìïîÓÒÖÔóòöôÚÙÜÛúùüûÑñ', 'AAAAaaaaEEEEeeeeIIIIiiiiOOOOooooUUUUuuuuNn')), '[^a-z0-9]+', ' ', 'g')),
  "moduleScopeKey" = trim(regexp_replace(lower(translate(COALESCE(e."moduleKey", ''), 'ÁÀÄÂáàäâÉÈËÊéèëêÍÌÏÎíìïîÓÒÖÔóòöôÚÙÜÛúùüûÑñ', 'AAAAaaaaEEEEeeeeIIIIiiiiOOOOooooUUUUuuuuNn')), '[^a-z0-9]+', ' ', 'g')),
  "targetRolesKey" = COALESCE((
    SELECT string_agg(lower(trim(role_item::text)), '|' ORDER BY lower(trim(role_item::text)))
    FROM unnest(COALESCE(e."targetRoles", ARRAY[]::"Role"[])) AS role_item
    WHERE trim(role_item::text) <> ''
  ), ''),
  "contentHash" = md5(trim(regexp_replace(lower(translate(COALESCE(e."content", ''), 'ÁÀÄÂáàäâÉÈËÊéèëêÍÌÏÎíìïîÓÒÖÔóòöôÚÙÜÛúùüûÑñ', 'AAAAaaaaEEEEeeeeIIIIiiiiOOOOooooUUUUuuuuNn')), '[^a-z0-9]+', ' ', 'g')));

-- Remove duplicates after normalization, keep newest by updatedAt then id.
WITH ranked AS (
  SELECT
    id,
    row_number() OVER (
      PARTITION BY "ownerId", "normalizedTitle", kind, audience, "moduleScopeKey", "targetRolesKey", "contentHash"
      ORDER BY "updatedAt" DESC, id DESC
    ) AS rn
  FROM "CompanyManualEntry"
)
DELETE FROM "CompanyManualEntry" e
USING ranked r
WHERE e.id = r.id
  AND r.rn > 1;
