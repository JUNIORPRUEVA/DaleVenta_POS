-- Narrow, audited exception for proven legacy TEST documents only.
-- Non-NULL environments, numbering rows and authorizations remain immutable.
CREATE OR REPLACE FUNCTION ecf_preserve_environment() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.environment IS NOT DISTINCT FROM OLD.environment THEN RETURN NEW; END IF;
  IF TG_TABLE_NAME = 'ecf_electronic_documents' THEN
    IF OLD.environment IS NULL AND NEW.environment = 'SANDBOX'
       AND OLD.payload_summary #>> '{controlledTest,environment}' = 'TEST'
       AND OLD.payload_summary #>> '{controlledTest,correlated}' = 'true'
       AND NEW.status = OLD.status
       AND EXISTS (
         SELECT 1 FROM ecf_electronic_document_status_logs l
         WHERE l.company_id = OLD.company_id AND l.document_id = OLD.id
           AND l.status_before = OLD.status AND l.status_after = OLD.status
           AND l.reason_code = 'LEGACY_TEST_ENVIRONMENT_CLASSIFIED'
           AND l.metadata->>'transactionId' = txid_current()::text
           AND l.metadata->>'documentFingerprint' = OLD.payload_fingerprint
           AND l.metadata->>'environment' = 'SANDBOX'
           AND l.metadata->>'evidenceSha256' = OLD.payload_summary #>> '{controlledTest,responseSha256}'
           AND l.metadata->>'evidencePlan' = OLD.payload_summary #>> '{controlledTest,plan}'
           AND l.metadata->>'manifestHash' ~ '^[0-9a-f]{64}$'
       ) THEN RETURN NEW;
    END IF;
  END IF;
  RAISE EXCEPTION 'ECF_ENVIRONMENT_IMMUTABLE';
END $$;
