-- Work Scheduling: perfiles de horarios, reglas de cobertura, rotación de día libre, excepciones, calendario semanal y auditoría

CREATE EXTENSION IF NOT EXISTS pgcrypto;

DO $$
BEGIN
  CREATE TYPE "WorkShiftKind" AS ENUM ('NORMAL', 'REDUCED', 'SPECIAL');
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

DO $$
BEGIN
  CREATE TYPE "WorkAssignmentStatus" AS ENUM ('WORK', 'DAY_OFF', 'EXCEPTION_OFF');
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

DO $$
BEGIN
  CREATE TYPE "WorkScheduleExceptionType" AS ENUM ('HOLIDAY', 'VACATION', 'SICK', 'LEAVE', 'LICENSE', 'ABSENCE', 'BLOCKED_DAY');
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

DO $$
BEGIN
  CREATE TYPE "WorkWeekScheduleStatus" AS ENUM ('GENERATED');
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

DO $$
BEGIN
  CREATE TYPE "WorkScheduleAuditAction" AS ENUM (
    'GENERATE_WEEK',
    'REGENERATE_WEEK',
    'UPDATE_SETTINGS',
    'UPDATE_EMPLOYEE_CONFIG',
    'CREATE_EXCEPTION',
    'UPDATE_EXCEPTION',
    'DELETE_EXCEPTION',
    'MANUAL_MOVE_DAY_OFF',
    'MANUAL_SWAP_DAY_OFF'
  );
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

CREATE TABLE IF NOT EXISTS work_schedule_profiles (
  id UUID NOT NULL DEFAULT gen_random_uuid(),
  name TEXT NOT NULL,
  is_default BOOLEAN NOT NULL DEFAULT false,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT work_schedule_profiles_pkey PRIMARY KEY (id)
);

CREATE INDEX IF NOT EXISTS work_schedule_profiles_is_default_idx
  ON work_schedule_profiles (is_default);

CREATE TABLE IF NOT EXISTS work_schedule_profile_days (
  id UUID NOT NULL DEFAULT gen_random_uuid(),
  profile_id UUID NOT NULL,
  weekday INTEGER NOT NULL,
  is_working BOOLEAN NOT NULL DEFAULT true,
  kind "WorkShiftKind" NOT NULL DEFAULT 'NORMAL',
  start_minute INTEGER NOT NULL,
  end_minute INTEGER NOT NULL,
  CONSTRAINT work_schedule_profile_days_pkey PRIMARY KEY (id)
);

CREATE UNIQUE INDEX IF NOT EXISTS work_schedule_profile_days_profile_weekday_key
  ON work_schedule_profile_days (profile_id, weekday);

CREATE INDEX IF NOT EXISTS work_schedule_profile_days_weekday_idx
  ON work_schedule_profile_days (weekday);

CREATE TABLE IF NOT EXISTS work_coverage_rules (
  id UUID NOT NULL DEFAULT gen_random_uuid(),
  role "Role" NOT NULL,
  weekday INTEGER NOT NULL,
  min_required INTEGER NOT NULL DEFAULT 0,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT work_coverage_rules_pkey PRIMARY KEY (id)
);

CREATE UNIQUE INDEX IF NOT EXISTS work_coverage_rules_role_weekday_key
  ON work_coverage_rules (role, weekday);

CREATE INDEX IF NOT EXISTS work_coverage_rules_weekday_idx
  ON work_coverage_rules (weekday);

CREATE TABLE IF NOT EXISTS work_employee_configs (
  id UUID NOT NULL DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL,
  enabled BOOLEAN NOT NULL DEFAULT true,
  schedule_profile_id UUID,
  preferred_day_off_weekday INTEGER,
  fixed_day_off_weekday INTEGER,
  disallowed_day_off_weekdays INTEGER[] NOT NULL DEFAULT '{}',
  unavailable_weekdays INTEGER[] NOT NULL DEFAULT '{}',
  notes TEXT,
  last_assigned_day_off_weekday INTEGER,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT work_employee_configs_pkey PRIMARY KEY (id)
);

CREATE UNIQUE INDEX IF NOT EXISTS work_employee_configs_user_id_key
  ON work_employee_configs (user_id);

CREATE INDEX IF NOT EXISTS work_employee_configs_enabled_idx
  ON work_employee_configs (enabled);

CREATE INDEX IF NOT EXISTS work_employee_configs_schedule_profile_id_idx
  ON work_employee_configs (schedule_profile_id);

CREATE TABLE IF NOT EXISTS work_schedule_exceptions (
  id UUID NOT NULL DEFAULT gen_random_uuid(),
  user_id UUID,
  type "WorkScheduleExceptionType" NOT NULL,
  date_from TIMESTAMP(3) NOT NULL,
  date_to TIMESTAMP(3) NOT NULL,
  note TEXT,
  created_by_id UUID,
  created_by_name TEXT,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT work_schedule_exceptions_pkey PRIMARY KEY (id)
);

CREATE INDEX IF NOT EXISTS work_schedule_exceptions_user_id_idx
  ON work_schedule_exceptions (user_id);

CREATE INDEX IF NOT EXISTS work_schedule_exceptions_type_idx
  ON work_schedule_exceptions (type);

CREATE INDEX IF NOT EXISTS work_schedule_exceptions_date_range_idx
  ON work_schedule_exceptions (date_from, date_to);

CREATE TABLE IF NOT EXISTS work_week_schedules (
  id UUID NOT NULL DEFAULT gen_random_uuid(),
  week_start_date TIMESTAMP(3) NOT NULL,
  status "WorkWeekScheduleStatus" NOT NULL DEFAULT 'GENERATED',
  generated_by_id UUID,
  generated_by_name TEXT,
  generated_at TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  warnings JSONB,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT work_week_schedules_pkey PRIMARY KEY (id)
);

CREATE UNIQUE INDEX IF NOT EXISTS work_week_schedules_week_start_date_key
  ON work_week_schedules (week_start_date);

CREATE INDEX IF NOT EXISTS work_week_schedules_generated_at_idx
  ON work_week_schedules (generated_at);

CREATE TABLE IF NOT EXISTS work_day_assignments (
  id UUID NOT NULL DEFAULT gen_random_uuid(),
  week_schedule_id UUID NOT NULL,
  user_id UUID NOT NULL,
  date TIMESTAMP(3) NOT NULL,
  weekday INTEGER NOT NULL,
  status "WorkAssignmentStatus" NOT NULL,
  start_minute INTEGER,
  end_minute INTEGER,
  manual_override BOOLEAN NOT NULL DEFAULT false,
  note TEXT,
  conflict_flags JSONB,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT work_day_assignments_pkey PRIMARY KEY (id)
);

CREATE UNIQUE INDEX IF NOT EXISTS work_day_assignments_unique_key
  ON work_day_assignments (week_schedule_id, user_id, date);

CREATE INDEX IF NOT EXISTS work_day_assignments_week_schedule_id_idx
  ON work_day_assignments (week_schedule_id);

CREATE INDEX IF NOT EXISTS work_day_assignments_user_id_idx
  ON work_day_assignments (user_id);

CREATE INDEX IF NOT EXISTS work_day_assignments_date_idx
  ON work_day_assignments (date);

CREATE INDEX IF NOT EXISTS work_day_assignments_weekday_idx
  ON work_day_assignments (weekday);

CREATE TABLE IF NOT EXISTS work_schedule_audit_logs (
  id UUID NOT NULL DEFAULT gen_random_uuid(),
  action "WorkScheduleAuditAction" NOT NULL,
  actor_user_id UUID,
  actor_user_name TEXT,
  target_user_id UUID,
  week_start_date TIMESTAMP(3),
  date_affected TIMESTAMP(3),
  reason TEXT,
  before JSONB,
  after JSONB,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT work_schedule_audit_logs_pkey PRIMARY KEY (id)
);

CREATE INDEX IF NOT EXISTS work_schedule_audit_logs_action_idx
  ON work_schedule_audit_logs (action);

CREATE INDEX IF NOT EXISTS work_schedule_audit_logs_actor_user_id_idx
  ON work_schedule_audit_logs (actor_user_id);

CREATE INDEX IF NOT EXISTS work_schedule_audit_logs_target_user_id_idx
  ON work_schedule_audit_logs (target_user_id);

CREATE INDEX IF NOT EXISTS work_schedule_audit_logs_week_start_date_idx
  ON work_schedule_audit_logs (week_start_date);

CREATE INDEX IF NOT EXISTS work_schedule_audit_logs_created_at_idx
  ON work_schedule_audit_logs ("createdAt");

-- Foreign keys (idempotentes)
DO $$
BEGIN
  ALTER TABLE work_schedule_profile_days
    ADD CONSTRAINT work_schedule_profile_days_profile_id_fkey
    FOREIGN KEY (profile_id) REFERENCES work_schedule_profiles(id) ON DELETE CASCADE ON UPDATE CASCADE;
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

DO $$
BEGIN
  ALTER TABLE work_employee_configs
    ADD CONSTRAINT work_employee_configs_user_id_fkey
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE ON UPDATE CASCADE;
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

DO $$
BEGIN
  ALTER TABLE work_employee_configs
    ADD CONSTRAINT work_employee_configs_schedule_profile_id_fkey
    FOREIGN KEY (schedule_profile_id) REFERENCES work_schedule_profiles(id) ON DELETE SET NULL ON UPDATE CASCADE;
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

DO $$
BEGIN
  ALTER TABLE work_schedule_exceptions
    ADD CONSTRAINT work_schedule_exceptions_user_id_fkey
    FOREIGN KEY (user_id) REFERENCES work_employee_configs(user_id) ON DELETE CASCADE ON UPDATE CASCADE;
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

DO $$
BEGIN
  ALTER TABLE work_day_assignments
    ADD CONSTRAINT work_day_assignments_week_schedule_id_fkey
    FOREIGN KEY (week_schedule_id) REFERENCES work_week_schedules(id) ON DELETE CASCADE ON UPDATE CASCADE;
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

DO $$
BEGIN
  ALTER TABLE work_day_assignments
    ADD CONSTRAINT work_day_assignments_user_id_fkey
    FOREIGN KEY (user_id) REFERENCES work_employee_configs(user_id) ON DELETE CASCADE ON UPDATE CASCADE;
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;
