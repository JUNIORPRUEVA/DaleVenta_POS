-- Add execution reports for technical workflow (non-breaking).

-- 1) AppConfig flag
ALTER TABLE IF EXISTS app_config
  ADD COLUMN IF NOT EXISTS operations_tech_can_view_all_services boolean NOT NULL DEFAULT false;

-- 2) Execution reports
CREATE TABLE IF NOT EXISTS service_execution_reports (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  service_id uuid NOT NULL,
  technician_id uuid NOT NULL,
  phase "ServicePhaseType" NOT NULL,
  arrived_at timestamptz NULL,
  started_at timestamptz NULL,
  finished_at timestamptz NULL,
  notes text NULL,
  checklist_data jsonb NULL,
  phase_specific_data jsonb NULL,
  client_approved boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT service_execution_reports_service_fk FOREIGN KEY (service_id) REFERENCES "Service"(id) ON DELETE CASCADE,
  CONSTRAINT service_execution_reports_technician_fk FOREIGN KEY (technician_id) REFERENCES users(id) ON DELETE RESTRICT
);

CREATE UNIQUE INDEX IF NOT EXISTS service_execution_reports_service_technician_uq
  ON service_execution_reports(service_id, technician_id);

CREATE INDEX IF NOT EXISTS service_execution_reports_service_idx
  ON service_execution_reports(service_id);

CREATE INDEX IF NOT EXISTS service_execution_reports_technician_idx
  ON service_execution_reports(technician_id);

CREATE INDEX IF NOT EXISTS service_execution_reports_updated_idx
  ON service_execution_reports(updated_at);

-- 3) Execution changes
CREATE TABLE IF NOT EXISTS service_execution_changes (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  service_id uuid NOT NULL,
  execution_report_id uuid NOT NULL,
  created_by_user_id uuid NOT NULL,
  type text NOT NULL,
  description text NOT NULL,
  quantity numeric(12,3) NULL,
  extra_cost numeric(12,2) NULL,
  client_approved boolean NULL,
  note text NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT service_execution_changes_service_fk FOREIGN KEY (service_id) REFERENCES "Service"(id) ON DELETE CASCADE,
  CONSTRAINT service_execution_changes_report_fk FOREIGN KEY (execution_report_id) REFERENCES service_execution_reports(id) ON DELETE CASCADE,
  CONSTRAINT service_execution_changes_created_by_fk FOREIGN KEY (created_by_user_id) REFERENCES users(id) ON DELETE RESTRICT
);

CREATE INDEX IF NOT EXISTS service_execution_changes_service_created_idx
  ON service_execution_changes(service_id, created_at);

CREATE INDEX IF NOT EXISTS service_execution_changes_report_idx
  ON service_execution_changes(execution_report_id);

CREATE INDEX IF NOT EXISTS service_execution_changes_created_by_idx
  ON service_execution_changes(created_by_user_id);
