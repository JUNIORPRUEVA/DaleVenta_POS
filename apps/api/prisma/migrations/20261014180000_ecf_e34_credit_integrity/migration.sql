BEGIN;
LOCK TABLE ecf_electronic_documents IN ACCESS EXCLUSIVE MODE;
DO $$ BEGIN
  IF EXISTS (SELECT 1 FROM ecf_electronic_documents d JOIN ecf_electronic_documents o
    ON o.id=d.original_document_id WHERE d.company_id<>o.company_id OR d.id=o.id)
  THEN RAISE EXCEPTION 'E34_EXISTING_RELATION_REQUIRES_REVIEW'; END IF;
END $$;

ALTER TABLE ecf_electronic_documents ADD COLUMN fiscal_snapshot JSONB;
CREATE UNIQUE INDEX ecf_electronic_documents_company_id_id_key ON ecf_electronic_documents(company_id,id);
ALTER TABLE ecf_electronic_documents DROP CONSTRAINT ecf_electronic_documents_original_document_id_fkey;
ALTER TABLE ecf_electronic_documents ADD CONSTRAINT ecf_electronic_documents_company_id_original_document_id_fkey
  FOREIGN KEY(company_id,original_document_id) REFERENCES ecf_electronic_documents(company_id,id) ON DELETE RESTRICT ON UPDATE CASCADE;
ALTER TABLE ecf_electronic_documents ADD CONSTRAINT ecf_no_self_reference CHECK(original_document_id IS DISTINCT FROM id);
ALTER TABLE ecf_electronic_documents ADD CONSTRAINT ecf_snapshot_shape CHECK(fiscal_snapshot IS NULL OR (
  jsonb_typeof(fiscal_snapshot)='object' AND fiscal_snapshot ?& ARRAY['total','currency','issueDate','issuerRnc','encf','evidenceRef','evidenceHash']
  AND fiscal_snapshot->>'currency'='DOP' AND fiscal_snapshot->>'total' ~ '^[0-9]+(\.[0-9]{1,2})?$'
  AND fiscal_snapshot->>'evidenceHash' ~ '^[0-9a-f]{64}$') IS TRUE);

CREATE TYPE ecf_credit_reservation_state AS ENUM('RESERVED','UNKNOWN_RESULT','APPLIED','REJECTED','CANCELLED');
CREATE TABLE ecf_credit_reservations (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(), company_id UUID NOT NULL,
  original_document_id UUID NOT NULL, credit_document_id UUID NOT NULL,
  amount NUMERIC(20,2) NOT NULL CHECK(amount>0),
  state ecf_credit_reservation_state NOT NULL DEFAULT 'RESERVED',
  request_fingerprint VARCHAR(64) NOT NULL CHECK(request_fingerprint ~ '^[0-9a-f]{64}$'),
  created_at TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP, updated_at TIMESTAMP(3) NOT NULL,
  CONSTRAINT ecf_credit_reservations_company_id_id_key UNIQUE(company_id,id),
  CONSTRAINT ecf_credit_reservations_company_id_credit_document_id_key UNIQUE(company_id,credit_document_id),
  CONSTRAINT ecf_credit_reservations_company_id_original_document_id_fkey FOREIGN KEY(company_id,original_document_id)
    REFERENCES ecf_electronic_documents(company_id,id) ON DELETE RESTRICT ON UPDATE CASCADE,
  CONSTRAINT ecf_credit_reservations_company_id_credit_document_id_fkey FOREIGN KEY(company_id,credit_document_id)
    REFERENCES ecf_electronic_documents(company_id,id) ON DELETE RESTRICT ON UPDATE CASCADE,
  CHECK(original_document_id<>credit_document_id)
);
CREATE INDEX ecf_credit_reservations_company_id_original_document_id_state_idx
  ON ecf_credit_reservations(company_id,original_document_id,state);
CREATE TABLE ecf_credit_reservation_events (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(), company_id UUID NOT NULL, reservation_id UUID NOT NULL,
  state_before ecf_credit_reservation_state, state_after ecf_credit_reservation_state NOT NULL,
  reason_code VARCHAR(64) NOT NULL, actor_user_id UUID, created_at TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT ecf_credit_reservation_events_company_id_reservation_id_fkey FOREIGN KEY(company_id,reservation_id)
    REFERENCES ecf_credit_reservations(company_id,id) ON DELETE RESTRICT ON UPDATE CASCADE
);
CREATE INDEX ecf_credit_reservation_events_company_id_reservation_id_created_at_idx
  ON ecf_credit_reservation_events(company_id,reservation_id,created_at);

CREATE FUNCTION ecf_protect_document_snapshot() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF TG_OP='DELETE' THEN
    IF OLD.fiscal_snapshot IS NOT NULL OR EXISTS (SELECT 1 FROM ecf_credit_reservations
      WHERE company_id=OLD.company_id AND (original_document_id=OLD.id OR credit_document_id=OLD.id))
    THEN RAISE EXCEPTION 'E34_DOCUMENT_HISTORY_IMMUTABLE'; END IF;
    RETURN OLD;
  END IF;
  IF OLD.fiscal_snapshot IS NOT NULL AND (NEW.fiscal_snapshot IS DISTINCT FROM OLD.fiscal_snapshot
    OR NEW.external_document_number IS DISTINCT FROM OLD.external_document_number
    OR NEW.external_provider_id IS DISTINCT FROM OLD.external_provider_id
    OR NEW.company_id<>OLD.company_id OR NEW.document_type<>OLD.document_type)
  THEN RAISE EXCEPTION 'E34_FISCAL_SNAPSHOT_IMMUTABLE'; END IF;
  IF EXISTS (SELECT 1 FROM ecf_credit_reservations WHERE company_id=OLD.company_id AND credit_document_id=OLD.id)
    AND (NEW.payload_summary IS DISTINCT FROM OLD.payload_summary OR NEW.payload_fingerprint<>OLD.payload_fingerprint
      OR NEW.original_document_id IS DISTINCT FROM OLD.original_document_id OR NEW.company_id<>OLD.company_id
      OR NEW.document_type<>OLD.document_type OR NEW.idempotency_key<>OLD.idempotency_key)
  THEN RAISE EXCEPTION 'E34_RESERVED_PAYLOAD_IMMUTABLE'; END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER ecf_protect_document_snapshot BEFORE UPDATE OR DELETE ON ecf_electronic_documents
  FOR EACH ROW EXECUTE FUNCTION ecf_protect_document_snapshot();

CREATE FUNCTION ecf_protect_credit_reservation() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE original ecf_electronic_documents%ROWTYPE; note ecf_electronic_documents%ROWTYPE; used NUMERIC;
BEGIN
  IF TG_OP='DELETE' THEN RAISE EXCEPTION 'E34_RESERVATION_HISTORY_IMMUTABLE'; END IF;
  IF TG_OP='UPDATE' THEN
    IF (NEW.company_id,NEW.original_document_id,NEW.credit_document_id,NEW.amount,NEW.request_fingerprint)
      IS DISTINCT FROM (OLD.company_id,OLD.original_document_id,OLD.credit_document_id,OLD.amount,OLD.request_fingerprint)
    THEN RAISE EXCEPTION 'E34_RESERVATION_IDENTITY_IMMUTABLE'; END IF;
    IF NEW.state<>OLD.state AND (OLD.state NOT IN ('RESERVED','UNKNOWN_RESULT') OR NEW.state='RESERVED'
      OR (OLD.state='UNKNOWN_RESULT' AND NEW.state='CANCELLED'))
    THEN RAISE EXCEPTION 'E34_RESERVATION_TRANSITION_INVALID'; END IF;
  ELSIF NEW.state<>'RESERVED' THEN RAISE EXCEPTION 'E34_INITIAL_RESERVATION_STATE_INVALID'; END IF;
  SELECT * INTO original FROM ecf_electronic_documents WHERE company_id=NEW.company_id AND id=NEW.original_document_id FOR UPDATE;
  SELECT * INTO note FROM ecf_electronic_documents WHERE company_id=NEW.company_id AND id=NEW.credit_document_id;
  IF original.id IS NULL OR note.id IS NULL OR original.document_type NOT IN ('E31','E32') OR note.document_type<>'E34'
    OR note.original_document_id IS DISTINCT FROM original.id
  THEN RAISE EXCEPTION 'E34_REFERENCE_INVALID'; END IF;
  IF TG_OP='INSERT' AND (original.status<>'DGII_ACCEPTED' OR original.fiscal_snapshot IS NULL
    OR original.external_document_number IS DISTINCT FROM original.fiscal_snapshot->>'encf'
    OR original.external_provider_id IS NULL OR (original.fiscal_snapshot->>'total')::numeric<=0
    OR note.status NOT IN ('LOCAL_VALIDATED','READY_TO_SEND')
    OR note.payload_summary->>'currency' IS DISTINCT FROM original.fiscal_snapshot->>'currency'
    OR note.payload_summary->'reference'->>'originalENcf' IS DISTINCT FROM original.external_document_number
    OR note.payload_summary->'reference'->>'originalIssueDate' IS DISTINCT FROM original.fiscal_snapshot->>'issueDate'
    OR (note.payload_summary->>'total')::numeric IS DISTINCT FROM NEW.amount)
  THEN RAISE EXCEPTION 'E34_ORIGINAL_OR_AMOUNT_UNVERIFIED'; END IF;
  IF TG_OP='INSERT' AND NOT EXISTS (SELECT 1 FROM ecf_electronic_document_status_logs
    WHERE company_id=NEW.company_id AND document_id=original.id AND status_after='DGII_ACCEPTED'
      AND metadata->>'evidenceHash'=original.fiscal_snapshot->>'evidenceHash'
      AND metadata->>'evidenceRef'=original.fiscal_snapshot->>'evidenceRef')
  THEN RAISE EXCEPTION 'E34_ORIGINAL_EVIDENCE_REQUIRED'; END IF;
  IF NEW.state IN ('APPLIED','REJECTED') AND (note.status::text IS DISTINCT FROM
    CASE WHEN NEW.state='APPLIED' THEN 'DGII_ACCEPTED' ELSE 'DGII_REJECTED' END
    OR note.fiscal_snapshot IS NULL OR (note.fiscal_snapshot->>'total')::numeric IS DISTINCT FROM NEW.amount
    OR note.fiscal_snapshot->>'currency' IS DISTINCT FROM original.fiscal_snapshot->>'currency'
    OR note.fiscal_snapshot->>'issuerRnc' IS DISTINCT FROM original.fiscal_snapshot->>'issuerRnc'
    OR note.external_document_number IS DISTINCT FROM note.fiscal_snapshot->>'encf'
    OR NOT EXISTS (SELECT 1 FROM ecf_electronic_document_status_logs WHERE company_id=NEW.company_id AND document_id=note.id
      AND status_after=note.status AND metadata->>'evidenceHash'=note.fiscal_snapshot->>'evidenceHash'
      AND metadata->>'evidenceRef'=note.fiscal_snapshot->>'evidenceRef'))
  THEN RAISE EXCEPTION 'E34_OUTCOME_EVIDENCE_REQUIRED'; END IF;
  IF NEW.state='CANCELLED' AND note.status NOT IN ('LOCAL_VALIDATED','READY_TO_SEND','CANCELLED')
  THEN RAISE EXCEPTION 'E34_SUBMITTED_CANNOT_RELEASE'; END IF;
  IF original.fiscal_snapshot IS NULL THEN RAISE EXCEPTION 'E34_ORIGINAL_EVIDENCE_REQUIRED'; END IF;
  SELECT COALESCE(sum(amount),0) INTO used FROM ecf_credit_reservations
    WHERE company_id=NEW.company_id AND original_document_id=NEW.original_document_id AND id<>NEW.id
      AND state IN ('RESERVED','UNKNOWN_RESULT','APPLIED');
  IF NEW.state IN ('RESERVED','UNKNOWN_RESULT','APPLIED') THEN used := used + NEW.amount; END IF;
  IF used > (original.fiscal_snapshot->>'total')::numeric THEN RAISE EXCEPTION 'E34_FISCAL_BALANCE_EXCEEDED'; END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER ecf_protect_credit_reservation BEFORE INSERT OR UPDATE OR DELETE ON ecf_credit_reservations
  FOR EACH ROW EXECUTE FUNCTION ecf_protect_credit_reservation();

CREATE FUNCTION ecf_record_credit_event() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF TG_OP='INSERT' OR NEW.state IS DISTINCT FROM OLD.state THEN
    INSERT INTO ecf_credit_reservation_events(company_id,reservation_id,state_before,state_after,reason_code,actor_user_id)
    VALUES(NEW.company_id,NEW.id,CASE WHEN TG_OP='INSERT' THEN NULL ELSE OLD.state END,
      NEW.state,'LOCAL_'||NEW.state::text,NULLIF(current_setting('fullpos.ecf_actor',true),'')::uuid);
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER ecf_record_credit_event AFTER INSERT OR UPDATE ON ecf_credit_reservations
  FOR EACH ROW EXECUTE FUNCTION ecf_record_credit_event();

CREATE FUNCTION ecf_credit_events_append_only() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN RAISE EXCEPTION 'E34_CREDIT_EVENTS_APPEND_ONLY'; END $$;
CREATE TRIGGER ecf_credit_events_append_only BEFORE UPDATE OR DELETE ON ecf_credit_reservation_events
  FOR EACH ROW EXECUTE FUNCTION ecf_credit_events_append_only();
COMMIT;
