-- Add Evolution API settings to global app_config

ALTER TABLE app_config
  ADD COLUMN IF NOT EXISTS evolution_api_base_url TEXT NOT NULL DEFAULT '';

ALTER TABLE app_config
  ADD COLUMN IF NOT EXISTS evolution_api_instance_name TEXT NOT NULL DEFAULT '';

ALTER TABLE app_config
  ADD COLUMN IF NOT EXISTS evolution_api_api_key TEXT;
