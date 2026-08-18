ALTER TABLE technical_network_applications
  ADD COLUMN IF NOT EXISTS manual_address TEXT,
  ADD COLUMN IF NOT EXISTS formatted_address TEXT,
  ADD COLUMN IF NOT EXISTS latitude DOUBLE PRECISION,
  ADD COLUMN IF NOT EXISTS longitude DOUBLE PRECISION,
  ADD COLUMN IF NOT EXISTS location_accuracy DOUBLE PRECISION,
  ADD COLUMN IF NOT EXISTS location_captured_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS location_source TEXT,
  ADD COLUMN IF NOT EXISTS resume_url TEXT,
  ADD COLUMN IF NOT EXISTS resume_original_name TEXT,
  ADD COLUMN IF NOT EXISTS resume_mime_type TEXT,
  ADD COLUMN IF NOT EXISTS resume_size_bytes BIGINT,
  ADD COLUMN IF NOT EXISTS consent_accepted BOOLEAN NOT NULL DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS consent_accepted_at TIMESTAMPTZ;

ALTER TABLE technical_network_technicians
  ADD COLUMN IF NOT EXISTS manual_address TEXT,
  ADD COLUMN IF NOT EXISTS formatted_address TEXT,
  ADD COLUMN IF NOT EXISTS latitude DOUBLE PRECISION,
  ADD COLUMN IF NOT EXISTS longitude DOUBLE PRECISION,
  ADD COLUMN IF NOT EXISTS location_accuracy DOUBLE PRECISION,
  ADD COLUMN IF NOT EXISTS location_captured_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS location_source TEXT,
  ADD COLUMN IF NOT EXISTS resume_url TEXT,
  ADD COLUMN IF NOT EXISTS resume_original_name TEXT,
  ADD COLUMN IF NOT EXISTS resume_mime_type TEXT,
  ADD COLUMN IF NOT EXISTS resume_size_bytes BIGINT;

CREATE INDEX IF NOT EXISTS technical_network_applications_location_idx
  ON technical_network_applications (province, municipality);

CREATE INDEX IF NOT EXISTS technical_network_applications_submitted_idx
  ON technical_network_applications (submitted_at);
