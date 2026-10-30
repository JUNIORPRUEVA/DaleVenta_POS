-- Versioned operation identity; no document or history is deleted.
BEGIN;
LOCK TABLE "ecf_electronic_documents", "ecf_electronic_document_attempts" IN ACCESS EXCLUSIVE MODE;

-- Abort rather than merge previously divergent operations or rewrite unknown keys.
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM "ecf_electronic_documents"
    WHERE source_id IS NOT NULL
    GROUP BY company_id, document_type, source_type, source_id HAVING count(*) > 1
  ) THEN RAISE EXCEPTION 'ECF_LEGACY_OPERATION_CONFLICT'; END IF;
  IF EXISTS (
    SELECT 1 FROM "ecf_electronic_documents"
    WHERE (source_id IS NOT NULL AND (source_type IS NULL OR source_type NOT IN ('SALE','COTIZACION','MANUAL')))
      OR idempotency_key NOT LIKE 'ecf:' || company_id::text || ':' || document_type::text || ':%'
  ) THEN RAISE EXCEPTION 'ECF_LEGACY_IDENTITY_REQUIRES_REVIEW'; END IF;
  IF EXISTS (
    SELECT 1 FROM "ecf_electronic_document_attempts" a
    JOIN "ecf_electronic_documents" d ON d.id = a.document_id
    WHERE a.company_id <> d.company_id OR a.idempotency_key <> d.idempotency_key
  ) THEN RAISE EXCEPTION 'ECF_ATTEMPT_INTEGRITY_REQUIRES_REVIEW'; END IF;
END $$;

-- Source-less legacy operations retain a recoverable request identity: document UUID.
CREATE TEMP TABLE ecf_operation_keys ON COMMIT DROP AS
SELECT id, company_id,
  'ecf:v2:' || company_id::text || ':' || document_type::text || ':' ||
  CASE WHEN source_id IS NOT NULL THEN 'SOURCE:' || source_type || ':' || source_id::text
       ELSE 'REQUEST:' || id::text END AS new_key
FROM "ecf_electronic_documents";

UPDATE "ecf_electronic_document_attempts" a SET idempotency_key = k.new_key
FROM ecf_operation_keys k WHERE a.document_id = k.id AND a.company_id = k.company_id;
UPDATE "ecf_electronic_documents" d SET idempotency_key = k.new_key
FROM ecf_operation_keys k WHERE d.id = k.id AND d.company_id = k.company_id;

CREATE INDEX "ecf_electronic_documents_company_id_payload_fingerprint_idx"
  ON "ecf_electronic_documents"("company_id", "payload_fingerprint");
DROP INDEX "ecf_electronic_documents_company_id_payload_fingerprint_key";
COMMIT;
