-- Fiscal references must identify one local document per tenant; NULL drafts coexist.
BEGIN;
LOCK TABLE ecf_electronic_documents IN ACCESS EXCLUSIVE MODE;
DO $$ BEGIN
  IF EXISTS (SELECT 1 FROM ecf_electronic_documents WHERE external_document_number IS NOT NULL
    GROUP BY company_id,external_document_number HAVING count(*)>1)
  THEN RAISE EXCEPTION 'E34_DUPLICATE_FISCAL_REFERENCE_REQUIRES_REVIEW'; END IF;
END $$;
CREATE UNIQUE INDEX ecf_electronic_documents_company_id_external_document_number_key
  ON ecf_electronic_documents(company_id,external_document_number);
COMMIT;
