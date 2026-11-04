ALTER TYPE "ecf_audit_action" ADD VALUE IF NOT EXISTS 'INTENT_PROVIDER_RECONCILED';

-- One reconciliation per intent; the original attribution remains immutable.
CREATE UNIQUE INDEX IF NOT EXISTS "ecf_intent_provider_reconciliation_once"
  ON "ecf_audit_logs" ("company_id", "target_id")
  WHERE "action" = 'INTENT_PROVIDER_RECONCILED'::"ecf_audit_action"
    AND "target_type" = 'DOSA_CERTIFICATION_INTENT';
