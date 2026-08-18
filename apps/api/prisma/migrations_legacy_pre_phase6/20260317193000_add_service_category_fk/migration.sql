ALTER TABLE "Service"
ADD COLUMN "category_id" UUID;

INSERT INTO service_categories (id, name, code, created_at, updated_at)
VALUES
  (gen_random_uuid(), 'Cámaras', 'cameras', now(), now()),
  (gen_random_uuid(), 'Motores de puertones', 'gate_motor', now(), now()),
  (gen_random_uuid(), 'Alarma', 'alarm', now(), now()),
  (gen_random_uuid(), 'Cerco eléctrico', 'electric_fence', now(), now()),
  (gen_random_uuid(), 'Intercom', 'intercom', now(), now()),
  (gen_random_uuid(), 'Punto de ventas', 'pos', now(), now())
ON CONFLICT (code)
DO UPDATE SET
  name = EXCLUDED.name,
  updated_at = now();

WITH distinct_categories AS (
  SELECT DISTINCT trim("category") AS name
  FROM "Service"
  WHERE trim("category") <> ''
)
INSERT INTO service_categories (id, name, code, created_at, updated_at)
SELECT
  gen_random_uuid(),
  dc.name,
  lower(
    regexp_replace(
      regexp_replace(
        translate(
          dc.name,
          'ÁÀÄÂáàäâÉÈËÊéèëêÍÌÏÎíìïîÓÒÖÔóòöôÚÙÜÛúùüûÑñ',
          'AAAAaaaaEEEEeeeeIIIIiiiiOOOOooooUUUUuuuuNn'
        ),
        '[^a-zA-Z0-9]+',
        '_',
        'g'
      ),
      '(^_+|_+$)',
      '',
      'g'
    )
  ),
  now(),
  now()
FROM distinct_categories dc
ON CONFLICT (code)
DO UPDATE SET
  name = EXCLUDED.name,
  updated_at = now();

UPDATE "Service" s
SET
  "category_id" = sc.id,
  "category" = sc.code
FROM service_categories sc
WHERE s."category_id" IS NULL
  AND sc.code = lower(
    regexp_replace(
      regexp_replace(
        translate(
          trim(s."category"),
          'ÁÀÄÂáàäâÉÈËÊéèëêÍÌÏÎíìïîÓÒÖÔóòöôÚÙÜÛúùüûÑñ',
          'AAAAaaaaEEEEeeeeIIIIiiiiOOOOooooUUUUuuuuNn'
        ),
        '[^a-zA-Z0-9]+',
        '_',
        'g'
      ),
      '(^_+|_+$)',
      '',
      'g'
    )
  );

CREATE INDEX "Service_category_id_idx" ON "Service"("category_id");

ALTER TABLE "Service"
ADD CONSTRAINT "Service_category_id_fkey"
FOREIGN KEY ("category_id") REFERENCES service_categories(id)
ON DELETE SET NULL
ON UPDATE CASCADE;
