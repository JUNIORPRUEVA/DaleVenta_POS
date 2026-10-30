BEGIN;
CREATE TABLE ecf_sandbox_e32_trials (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), company_id uuid NOT NULL, document_id uuid NOT NULL,
 slot varchar(80) NOT NULL UNIQUE, mode varchar(16) NOT NULL CHECK (mode IN ('SANDBOX','MOCK_ONLY')),
 state varchar(32) NOT NULL DEFAULT 'PREPARED' CHECK (state IN ('PREPARED','CLAIMED','UNKNOWN_RESULT','RESPONSE_RECORDED')),
 manifest jsonb NOT NULL, manifest_fingerprint varchar(64) NOT NULL CHECK (manifest_fingerprint ~ '^[a-f0-9]{64}$'),
 payload jsonb NOT NULL, payload_fingerprint varchar(64) NOT NULL CHECK (payload_fingerprint ~ '^[a-f0-9]{64}$'),
 created_at timestamp(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
 CHECK ((mode='SANDBOX' AND slot='FIRST_E32_SANDBOX') OR (mode='MOCK_ONLY' AND slot='MOCK_ONLY:'||company_id::text)),
 CONSTRAINT ecf_sandbox_e32_trials_company_id_document_id_fkey FOREIGN KEY (company_id,document_id) REFERENCES ecf_electronic_documents(company_id,id) ON DELETE RESTRICT,
 UNIQUE(company_id,id), UNIQUE(company_id,document_id)
);
CREATE TABLE ecf_sandbox_e32_trial_events (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), company_id uuid NOT NULL, trial_id uuid NOT NULL,
 kind varchar(32) NOT NULL, safe_code varchar(64) NOT NULL, body_sha256 varchar(64), http_status integer,
 created_at timestamp(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
 CONSTRAINT ecf_sandbox_e32_trial_events_company_id_trial_id_fkey FOREIGN KEY (company_id,trial_id) REFERENCES ecf_sandbox_e32_trials(company_id,id) ON DELETE RESTRICT
);
CREATE INDEX ecf_sandbox_e32_trial_events_company_id_trial_id_idx ON ecf_sandbox_e32_trial_events(company_id,trial_id);
CREATE FUNCTION ecf_e32_trial_guard() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
 IF TG_OP='DELETE' THEN RAISE EXCEPTION 'E32_TRIAL_APPEND_ONLY'; END IF;
 IF TG_OP='INSERT' THEN
   IF NEW.state<>'PREPARED' THEN RAISE EXCEPTION 'E32_TRIAL_INITIAL_STATE_INVALID'; END IF;
 ELSE
   IF (NEW.id,NEW.company_id,NEW.document_id,NEW.slot,NEW.mode,NEW.manifest,NEW.manifest_fingerprint,NEW.payload,NEW.payload_fingerprint,NEW.created_at)
     IS DISTINCT FROM (OLD.id,OLD.company_id,OLD.document_id,OLD.slot,OLD.mode,OLD.manifest,OLD.manifest_fingerprint,OLD.payload,OLD.payload_fingerprint,OLD.created_at)
   THEN RAISE EXCEPTION 'E32_TRIAL_IDENTITY_IMMUTABLE'; END IF;
   IF NOT ((OLD.state='PREPARED' AND NEW.state='CLAIMED') OR (OLD.state='CLAIMED' AND NEW.state IN ('UNKNOWN_RESULT','RESPONSE_RECORDED')))
   THEN RAISE EXCEPTION 'E32_TRIAL_ALREADY_CONSUMED'; END IF;
 END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER ecf_e32_trial_guard BEFORE INSERT OR UPDATE OR DELETE ON ecf_sandbox_e32_trials FOR EACH ROW EXECUTE FUNCTION ecf_e32_trial_guard();
CREATE FUNCTION ecf_e32_trial_history() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
 INSERT INTO ecf_sandbox_e32_trial_events(company_id,trial_id,kind,safe_code) VALUES(NEW.company_id,NEW.id,NEW.state,'LOCAL_'||NEW.state);
 RETURN NEW;
END $$;
CREATE TRIGGER ecf_e32_trial_history AFTER INSERT OR UPDATE ON ecf_sandbox_e32_trials FOR EACH ROW EXECUTE FUNCTION ecf_e32_trial_history();
CREATE TRIGGER ecf_e32_trial_events_immutable BEFORE UPDATE OR DELETE ON ecf_sandbox_e32_trial_events FOR EACH ROW EXECUTE FUNCTION ecf_evidence_immutable();
COMMIT;
