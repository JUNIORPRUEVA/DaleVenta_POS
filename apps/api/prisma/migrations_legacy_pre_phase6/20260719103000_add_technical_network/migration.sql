CREATE TABLE IF NOT EXISTS technical_network_applications (
  id TEXT PRIMARY KEY,
  application_code TEXT NOT NULL UNIQUE,
  full_name TEXT NOT NULL,
  identity_number TEXT NOT NULL,
  phone TEXT NOT NULL,
  whatsapp TEXT NOT NULL,
  email TEXT,
  province TEXT NOT NULL,
  municipality TEXT NOT NULL,
  sector TEXT,
  specialty TEXT NOT NULL,
  experience_level TEXT NOT NULL,
  experience_description TEXT,
  camera_skills JSONB NOT NULL DEFAULT '[]'::jsonb,
  gate_motor_skills JSONB NOT NULL DEFAULT '[]'::jsonb,
  tools_availability TEXT NOT NULL,
  tools JSONB NOT NULL DEFAULT '[]'::jsonb,
  other_tools TEXT,
  transportation TEXT NOT NULL,
  availability TEXT NOT NULL,
  availability_notes TEXT,
  can_travel BOOLEAN NOT NULL DEFAULT FALSE,
  can_work_weekends BOOLEAN NOT NULL DEFAULT FALSE,
  profile_photo_url TEXT,
  identity_front_photo_url TEXT,
  identity_back_photo_url TEXT,
  work_evidence_photo_urls JSONB NOT NULL DEFAULT '[]'::jsonb,
  reference_name TEXT,
  reference_phone TEXT,
  previous_company TEXT,
  status TEXT NOT NULL DEFAULT 'PENDING',
  rejection_reason TEXT,
  internal_notes TEXT,
  submitted_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  reviewed_at TIMESTAMPTZ,
  reviewed_by_id TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS technical_network_applications_identity_unique
  ON technical_network_applications (identity_number);

CREATE UNIQUE INDEX IF NOT EXISTS technical_network_applications_phone_unique
  ON technical_network_applications (phone);

CREATE INDEX IF NOT EXISTS technical_network_applications_status_idx
  ON technical_network_applications (status);

CREATE INDEX IF NOT EXISTS technical_network_applications_specialty_idx
  ON technical_network_applications (specialty);

CREATE TABLE IF NOT EXISTS technical_network_technicians (
  id TEXT PRIMARY KEY,
  technician_code TEXT NOT NULL UNIQUE,
  application_id TEXT UNIQUE REFERENCES technical_network_applications(id),
  full_name TEXT NOT NULL,
  identity_number TEXT NOT NULL,
  phone TEXT NOT NULL,
  whatsapp TEXT NOT NULL,
  email TEXT,
  province TEXT NOT NULL,
  municipality TEXT NOT NULL,
  sector TEXT,
  specialty TEXT NOT NULL,
  experience_level TEXT NOT NULL,
  experience_description TEXT,
  camera_skills JSONB NOT NULL DEFAULT '[]'::jsonb,
  gate_motor_skills JSONB NOT NULL DEFAULT '[]'::jsonb,
  tools_availability TEXT NOT NULL,
  tools JSONB NOT NULL DEFAULT '[]'::jsonb,
  other_tools TEXT,
  transportation TEXT NOT NULL,
  availability TEXT NOT NULL,
  availability_notes TEXT,
  can_travel BOOLEAN NOT NULL DEFAULT FALSE,
  can_work_weekends BOOLEAN NOT NULL DEFAULT FALSE,
  profile_photo_url TEXT,
  identity_document_urls JSONB NOT NULL DEFAULT '[]'::jsonb,
  work_evidence_photo_urls JSONB NOT NULL DEFAULT '[]'::jsonb,
  status TEXT NOT NULL DEFAULT 'AVAILABLE',
  is_favorite BOOLEAN NOT NULL DEFAULT FALSE,
  completed_jobs_count INTEGER NOT NULL DEFAULT 0,
  rating NUMERIC(3,2) NOT NULL DEFAULT 0,
  internal_notes TEXT,
  approved_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  approved_by_id TEXT,
  last_job_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS technical_network_technicians_identity_unique
  ON technical_network_technicians (identity_number);

CREATE UNIQUE INDEX IF NOT EXISTS technical_network_technicians_phone_unique
  ON technical_network_technicians (phone);

CREATE INDEX IF NOT EXISTS technical_network_technicians_status_idx
  ON technical_network_technicians (status);

CREATE INDEX IF NOT EXISTS technical_network_technicians_specialty_idx
  ON technical_network_technicians (specialty);

CREATE TABLE IF NOT EXISTS technical_network_jobs (
  id TEXT PRIMARY KEY,
  technician_id TEXT NOT NULL REFERENCES technical_network_technicians(id) ON DELETE CASCADE,
  type TEXT NOT NULL,
  job_date TIMESTAMPTZ NOT NULL,
  location TEXT,
  description TEXT,
  agreed_payment NUMERIC(12,2),
  status TEXT NOT NULL DEFAULT 'PENDING',
  internal_note TEXT,
  created_by_id TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS technical_network_jobs_technician_idx
  ON technical_network_jobs (technician_id);

CREATE TABLE IF NOT EXISTS technical_network_evaluations (
  id TEXT PRIMARY KEY,
  technician_id TEXT NOT NULL REFERENCES technical_network_technicians(id) ON DELETE CASCADE,
  rating INTEGER NOT NULL CHECK (rating BETWEEN 1 AND 5),
  note TEXT,
  created_by_id TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS technical_network_evaluations_technician_idx
  ON technical_network_evaluations (technician_id);
