ALTER TABLE app_config
ADD COLUMN IF NOT EXISTS legal_representative_name TEXT NOT NULL DEFAULT '',
ADD COLUMN IF NOT EXISTS legal_representative_cedula TEXT NOT NULL DEFAULT '',
ADD COLUMN IF NOT EXISTS legal_representative_role TEXT NOT NULL DEFAULT '',
ADD COLUMN IF NOT EXISTS legal_representative_nationality TEXT NOT NULL DEFAULT '',
ADD COLUMN IF NOT EXISTS legal_representative_civil_status TEXT NOT NULL DEFAULT '';
