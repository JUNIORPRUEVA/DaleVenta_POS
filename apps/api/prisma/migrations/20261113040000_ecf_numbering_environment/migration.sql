-- Existing numbering was declared as DGII authorization, with no environment.
-- Preserve it in production. Never copy or rewind it into TEST automatically.
ALTER TABLE "ecf_sequences" ADD COLUMN "environment" "ecf_environment" NOT NULL DEFAULT 'PRODUCTION';
ALTER TABLE "ecf_dgii_authorized_sequences" ADD COLUMN "environment" "ecf_environment" NOT NULL DEFAULT 'PRODUCTION';
ALTER TABLE "ecf_sequence_audit_logs" ADD COLUMN "environment" "ecf_environment" NOT NULL DEFAULT 'PRODUCTION';
-- Legacy documents remain explicitly unclassified until evidence is reviewed.
ALTER TABLE "ecf_electronic_documents" ADD COLUMN "environment" "ecf_environment";

DROP INDEX "ecf_sequences_active_company_type_prefix_key";
CREATE UNIQUE INDEX "ecf_sequences_active_company_env_type_prefix_key"
  ON "ecf_sequences" ("company_id", "environment", "document_type", "prefix") WHERE "active";
DROP INDEX "ecf_dgii_authorized_sequences_company_id_document_type_key";
CREATE UNIQUE INDEX "ecf_dgii_authorized_sequences_company_env_type_key"
  ON "ecf_dgii_authorized_sequences" ("company_id", "document_type", "environment");
DROP INDEX "ecf_sequence_audit_logs_company_id_operation_key_key";
CREATE UNIQUE INDEX "ecf_sequence_audit_logs_company_env_operation_key"
  ON "ecf_sequence_audit_logs" ("company_id", "environment", "operation_key");
DROP INDEX "ecf_electronic_documents_company_id_external_document_number_ke";
CREATE UNIQUE INDEX "ecf_electronic_documents_company_env_external_number_key"
  ON "ecf_electronic_documents" ("company_id", "environment", "external_document_number");
-- Retain the legacy uniqueness guarantee even though NULL environments do not
-- participate in the new composite uniqueness constraint.
CREATE UNIQUE INDEX "ecf_documents_legacy_external_number_key"
  ON "ecf_electronic_documents" ("company_id", "external_document_number") WHERE "environment" IS NULL;

CREATE FUNCTION ecf_preserve_environment() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.environment IS DISTINCT FROM OLD.environment THEN
    RAISE EXCEPTION 'ECF_ENVIRONMENT_IMMUTABLE';
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER ecf_document_environment_immutable BEFORE UPDATE OF environment ON ecf_electronic_documents
  FOR EACH ROW EXECUTE FUNCTION ecf_preserve_environment();
CREATE TRIGGER ecf_sequence_environment_immutable BEFORE UPDATE OF environment ON ecf_sequences
  FOR EACH ROW EXECUTE FUNCTION ecf_preserve_environment();
CREATE TRIGGER ecf_authorization_environment_immutable BEFORE UPDATE OF environment ON ecf_dgii_authorized_sequences
  FOR EACH ROW EXECUTE FUNCTION ecf_preserve_environment();
