BEGIN;
LOCK TABLE ecf_electronic_document_attempts IN SHARE ROW EXCLUSIVE MODE;
DO $$ BEGIN
  IF EXISTS (SELECT 1 FROM ecf_electronic_document_attempts a
    JOIN ecf_electronic_documents d ON d.id = a.document_id WHERE a.company_id <> d.company_id) THEN
    RAISE EXCEPTION 'ECF_ATTEMPT_TENANT_CONFLICT_REQUIRES_REVIEW';
  END IF;
END $$;
CREATE UNIQUE INDEX ecf_attempt_tenant_document_id_key ON ecf_electronic_document_attempts(company_id, document_id, id);
ALTER TABLE ecf_electronic_document_attempts DROP CONSTRAINT ecf_electronic_document_attempts_document_id_fkey;
ALTER TABLE ecf_electronic_document_attempts ADD CONSTRAINT ecf_electronic_document_attempts_company_id_document_id_fkey
  FOREIGN KEY (company_id, document_id) REFERENCES ecf_electronic_documents(company_id, id) ON DELETE CASCADE;
CREATE TABLE ecf_evidence_receipts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL,
  document_id uuid NOT NULL,
  attempt_id uuid NOT NULL,
  source varchar(32) NOT NULL CHECK (source IN ('SYNTHETIC','INTERNAL','PROVIDER_RESPONSE','WEBHOOK')),
  event_key varchar(128) NOT NULL CHECK (length(event_key) BETWEEN 3 AND 128),
  raw_sha256 varchar(64) NOT NULL CHECK (raw_sha256 ~ '^[a-f0-9]{64}$'),
  correlation_hash varchar(64) NOT NULL CHECK (correlation_hash ~ '^[a-f0-9]{64}$'),
  operation_key_hash varchar(64) NOT NULL CHECK (operation_key_hash ~ '^[a-f0-9]{64}$'),
  document_fingerprint varchar(64) NOT NULL CHECK (document_fingerprint ~ '^[a-f0-9]{64}$'),
  request_fingerprint varchar(64) NOT NULL CHECK (request_fingerprint ~ '^[a-f0-9]{64}$'),
  trust_level varchar(32) NOT NULL CHECK (trust_level IN ('SYNTHETIC','INTERNAL','PROVIDER_DECLARED')),
  authenticity varchar(64) NOT NULL CHECK (authenticity IN ('BLOCKED_PENDING_PROVIDER_CONTRACT','TEST_ONLY_AUTHENTICATED','UNVERIFIED')),
  validation_code varchar(64) NOT NULL,
  observation_code varchar(64) NOT NULL,
  schema_sha256 varchar(64),
  http_status integer CHECK (http_status BETWEEN 100 AND 599),
  received_at timestamp(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  actor_user_id uuid NOT NULL,
  CONSTRAINT ecf_evidence_source_trust CHECK (
    (source = 'SYNTHETIC' AND trust_level = 'SYNTHETIC') OR
    (source = 'INTERNAL' AND trust_level = 'INTERNAL') OR
    (source IN ('PROVIDER_RESPONSE','WEBHOOK') AND trust_level = 'PROVIDER_DECLARED')),
  CONSTRAINT ecf_evidence_test_scope CHECK (authenticity <> 'TEST_ONLY_AUTHENTICATED' OR source = 'SYNTHETIC'),
  CONSTRAINT ecf_evidence_document_fk FOREIGN KEY (company_id, document_id)
    REFERENCES ecf_electronic_documents(company_id, id) ON DELETE RESTRICT,
  CONSTRAINT ecf_evidence_attempt_fk FOREIGN KEY (company_id, document_id, attempt_id)
    REFERENCES ecf_electronic_document_attempts(company_id, document_id, id) ON DELETE RESTRICT
);
CREATE UNIQUE INDEX ecf_evidence_tenant_source_event_key ON ecf_evidence_receipts(company_id, source, event_key);
CREATE INDEX ecf_evidence_tenant_document_received_idx ON ecf_evidence_receipts(company_id, document_id, received_at);
CREATE FUNCTION ecf_evidence_immutable() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  RAISE EXCEPTION 'ECF_EVIDENCE_APPEND_ONLY';
END $$;
CREATE TRIGGER ecf_evidence_immutable BEFORE UPDATE OR DELETE ON ecf_evidence_receipts
  FOR EACH ROW EXECUTE FUNCTION ecf_evidence_immutable();
CREATE FUNCTION ecf_evidence_freeze_document() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF (NEW.company_id, NEW.id, NEW.idempotency_key, NEW.payload_fingerprint, NEW.external_provider_id, NEW.external_document_number, NEW.document_type)
    IS DISTINCT FROM (OLD.company_id, OLD.id, OLD.idempotency_key, OLD.payload_fingerprint, OLD.external_provider_id, OLD.external_document_number, OLD.document_type)
    AND EXISTS (SELECT 1 FROM ecf_evidence_receipts WHERE company_id = OLD.company_id AND document_id = OLD.id) THEN
    RAISE EXCEPTION 'ECF_EVIDENCE_DOCUMENT_CORRELATION_IMMUTABLE';
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER ecf_evidence_freeze_document BEFORE UPDATE ON ecf_electronic_documents
  FOR EACH ROW EXECUTE FUNCTION ecf_evidence_freeze_document();
CREATE FUNCTION ecf_evidence_freeze_attempt() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF (NEW.company_id, NEW.document_id, NEW.id, NEW.idempotency_key, NEW.request_fingerprint, NEW.operation)
    IS DISTINCT FROM (OLD.company_id, OLD.document_id, OLD.id, OLD.idempotency_key, OLD.request_fingerprint, OLD.operation)
    AND EXISTS (SELECT 1 FROM ecf_evidence_receipts WHERE company_id = OLD.company_id AND attempt_id = OLD.id) THEN
    RAISE EXCEPTION 'ECF_EVIDENCE_ATTEMPT_CORRELATION_IMMUTABLE';
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER ecf_evidence_freeze_attempt BEFORE UPDATE ON ecf_electronic_document_attempts
  FOR EACH ROW EXECUTE FUNCTION ecf_evidence_freeze_attempt();
COMMIT;
