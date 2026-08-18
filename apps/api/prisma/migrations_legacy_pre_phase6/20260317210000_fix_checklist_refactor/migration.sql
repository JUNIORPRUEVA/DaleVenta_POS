CREATE EXTENSION IF NOT EXISTS pgcrypto;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_type
    WHERE typname = 'ChecklistTemplateType'
  ) THEN
    CREATE TYPE "ChecklistTemplateType" AS ENUM (
      'HERRAMIENTAS',
      'PRODUCTOS',
      'INSTALACION'
    );
  END IF;
END $$;

ALTER TABLE checklist_templates
ADD COLUMN IF NOT EXISTS type "ChecklistTemplateType";

UPDATE checklist_templates ct
SET type = CASE
  WHEN lower(sp.code) = 'herramientas' THEN 'HERRAMIENTAS'::"ChecklistTemplateType"
  WHEN lower(sp.code) = 'productos' THEN 'PRODUCTOS'::"ChecklistTemplateType"
  WHEN lower(sp.code) = 'instalacion' THEN 'INSTALACION'::"ChecklistTemplateType"
  WHEN lower(ct.title) LIKE '%herramient%' THEN 'HERRAMIENTAS'::"ChecklistTemplateType"
  WHEN lower(ct.title) LIKE '%producto%' THEN 'PRODUCTOS'::"ChecklistTemplateType"
  ELSE 'INSTALACION'::"ChecklistTemplateType"
END
FROM service_phases sp
WHERE sp.id = ct.phase_id
  AND ct.type IS NULL;

UPDATE checklist_templates
SET type = 'INSTALACION'::"ChecklistTemplateType"
WHERE type IS NULL;

ALTER TABLE checklist_templates
ALTER COLUMN type SET NOT NULL;

DROP INDEX IF EXISTS checklist_templates_category_id_phase_id_title_key;

ALTER TABLE checklist_templates
DROP CONSTRAINT IF EXISTS checklist_templates_category_phase_title_key;

CREATE UNIQUE INDEX IF NOT EXISTS checklist_templates_category_id_phase_id_type_key
  ON checklist_templates (category_id, phase_id, type);

CREATE TABLE IF NOT EXISTS checklist_executions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  service_order_id uuid NOT NULL REFERENCES "Service"(id) ON DELETE CASCADE,
  template_id uuid NOT NULL REFERENCES checklist_templates(id) ON DELETE CASCADE,
  checklist_item_id uuid NOT NULL REFERENCES checklist_items(id) ON DELETE CASCADE,
  is_checked boolean NOT NULL DEFAULT false,
  checked_at timestamp(3),
  checked_by uuid REFERENCES users(id) ON DELETE SET NULL,
  created_at timestamp(3) NOT NULL DEFAULT now(),
  updated_at timestamp(3) NOT NULL DEFAULT now(),
  CONSTRAINT checklist_executions_service_order_id_checklist_item_id_key UNIQUE (service_order_id, checklist_item_id)
);

INSERT INTO checklist_executions (
  id,
  service_order_id,
  template_id,
  checklist_item_id,
  is_checked,
  checked_at,
  checked_by,
  created_at,
  updated_at
)
SELECT
  sci.id,
  sc.service_order_id,
  sc.template_id,
  sci.checklist_item_id,
  sci.is_checked,
  sci.checked_at,
  sci.checked_by,
  sci.created_at,
  sci.updated_at
FROM service_checklist_items sci
INNER JOIN service_checklists sc ON sc.id = sci.checklist_id
ON CONFLICT (service_order_id, checklist_item_id) DO NOTHING;

CREATE INDEX IF NOT EXISTS checklist_executions_service_order_id_idx
  ON checklist_executions (service_order_id);
CREATE INDEX IF NOT EXISTS checklist_executions_template_id_idx
  ON checklist_executions (template_id);
CREATE INDEX IF NOT EXISTS checklist_executions_checklist_item_id_idx
  ON checklist_executions (checklist_item_id);
CREATE INDEX IF NOT EXISTS checklist_executions_checked_by_idx
  ON checklist_executions (checked_by);

DROP TABLE IF EXISTS service_checklist_items;
DROP TABLE IF EXISTS service_checklists;