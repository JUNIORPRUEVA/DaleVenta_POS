CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE TABLE IF NOT EXISTS service_categories (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL,
  code text NOT NULL UNIQUE,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS service_categories_name_idx ON service_categories(name);

CREATE TABLE IF NOT EXISTS service_phases (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL,
  code text NOT NULL UNIQUE,
  order_index integer NOT NULL DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS service_phases_order_index_idx ON service_phases(order_index);
CREATE INDEX IF NOT EXISTS service_phases_name_idx ON service_phases(name);

CREATE TABLE IF NOT EXISTS checklist_templates (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  category_id uuid NOT NULL REFERENCES service_categories(id) ON DELETE CASCADE,
  phase_id uuid NOT NULL REFERENCES service_phases(id) ON DELETE CASCADE,
  title text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT checklist_templates_category_phase_title_key UNIQUE (category_id, phase_id, title)
);

CREATE INDEX IF NOT EXISTS checklist_templates_category_id_idx ON checklist_templates(category_id);
CREATE INDEX IF NOT EXISTS checklist_templates_phase_id_idx ON checklist_templates(phase_id);

CREATE TABLE IF NOT EXISTS checklist_items (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  template_id uuid NOT NULL REFERENCES checklist_templates(id) ON DELETE CASCADE,
  label text NOT NULL,
  is_required boolean NOT NULL DEFAULT true,
  order_index integer NOT NULL DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS checklist_items_template_id_idx ON checklist_items(template_id);
CREATE INDEX IF NOT EXISTS checklist_items_template_id_order_index_idx ON checklist_items(template_id, order_index);

CREATE TABLE IF NOT EXISTS service_checklists (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  service_order_id uuid NOT NULL REFERENCES "Service"(id) ON DELETE CASCADE,
  template_id uuid NOT NULL REFERENCES checklist_templates(id) ON DELETE CASCADE,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT service_checklists_service_order_id_template_id_key UNIQUE (service_order_id, template_id)
);

CREATE INDEX IF NOT EXISTS service_checklists_service_order_id_idx ON service_checklists(service_order_id);
CREATE INDEX IF NOT EXISTS service_checklists_template_id_idx ON service_checklists(template_id);

CREATE TABLE IF NOT EXISTS service_checklist_items (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  checklist_id uuid NOT NULL REFERENCES service_checklists(id) ON DELETE CASCADE,
  checklist_item_id uuid NOT NULL REFERENCES checklist_items(id) ON DELETE CASCADE,
  is_checked boolean NOT NULL DEFAULT false,
  checked_at timestamptz,
  checked_by uuid REFERENCES "users"(id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT service_checklist_items_checklist_id_checklist_item_id_key UNIQUE (checklist_id, checklist_item_id)
);

CREATE INDEX IF NOT EXISTS service_checklist_items_checklist_id_idx ON service_checklist_items(checklist_id);
CREATE INDEX IF NOT EXISTS service_checklist_items_checklist_item_id_idx ON service_checklist_items(checklist_item_id);
CREATE INDEX IF NOT EXISTS service_checklist_items_checked_by_idx ON service_checklist_items(checked_by);
