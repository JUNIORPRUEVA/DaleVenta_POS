-- e-CF (E31/E34) numbering ranges. Purely additive: no existing table or column is
-- touched, so the historical UAT data and the E32 single-use slot stay untouched.

-- CreateTable
CREATE TABLE "ecf_sequences" (
    "id" UUID NOT NULL,
    "company_id" UUID NOT NULL,
    "document_type" TEXT NOT NULL,
    "prefix" TEXT NOT NULL,
    "start_number" INTEGER NOT NULL DEFAULT 1,
    "next_number" INTEGER NOT NULL DEFAULT 1,
    "end_number" INTEGER NOT NULL,
    "valid_until" TIMESTAMP(3),
    "active" BOOLEAN NOT NULL DEFAULT true,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "ecf_sequences_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "ecf_sequence_audit_logs" (
    "id" UUID NOT NULL,
    "company_id" UUID NOT NULL,
    "sequence_id" UUID,
    "document_id" UUID,
    "user_id" UUID,
    "operation_key" TEXT,
    "encf" TEXT NOT NULL,
    "type" TEXT NOT NULL,
    "action" TEXT NOT NULL,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "ecf_sequence_audit_logs_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
-- Only the ACTIVE range is unique: inactive history must survive a renewal.
CREATE UNIQUE INDEX "ecf_sequences_active_company_type_prefix_key" ON "ecf_sequences"("company_id", "document_type", "prefix") WHERE "active";

-- CreateIndex
CREATE INDEX "ecf_sequences_company_id_document_type_active_idx" ON "ecf_sequences"("company_id", "document_type", "active");

-- CreateIndex
CREATE INDEX "ecf_sequence_audit_logs_company_id_encf_idx" ON "ecf_sequence_audit_logs"("company_id", "encf");

-- CreateIndex (one allocation per operation key: a retry reuses, never re-allocates)
CREATE UNIQUE INDEX "ecf_sequence_audit_logs_company_id_operation_key_key" ON "ecf_sequence_audit_logs"("company_id", "operation_key");

-- CreateIndex
CREATE INDEX "ecf_sequence_audit_logs_company_id_type_created_at_idx" ON "ecf_sequence_audit_logs"("company_id", "type", "created_at");

-- CreateIndex
CREATE INDEX "ecf_sequence_audit_logs_document_id_idx" ON "ecf_sequence_audit_logs"("document_id");

-- AddForeignKey
ALTER TABLE "ecf_sequences" ADD CONSTRAINT "ecf_sequences_company_id_fkey" FOREIGN KEY ("company_id") REFERENCES "companies"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "ecf_sequence_audit_logs" ADD CONSTRAINT "ecf_sequence_audit_logs_company_id_fkey" FOREIGN KEY ("company_id") REFERENCES "companies"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "ecf_sequence_audit_logs" ADD CONSTRAINT "ecf_sequence_audit_logs_sequence_id_fkey" FOREIGN KEY ("sequence_id") REFERENCES "ecf_sequences"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- No-reuse is a database guarantee, not only application logic: the range
-- identity is immutable and next_number can never go backwards. A consumed
-- e-NCF therefore cannot be handed out again even by a defective caller.
CREATE FUNCTION ecf_sequence_guard() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.company_id <> OLD.company_id
     OR NEW.document_type <> OLD.document_type
     OR NEW.prefix <> OLD.prefix THEN
    RAISE EXCEPTION 'ecf_sequence_identity_immutable';
  END IF;
  IF NEW.next_number < OLD.next_number THEN
    RAISE EXCEPTION 'ecf_sequence_consumption_irreversible';
  END IF;
  IF NEW.end_number < OLD.next_number - 1 THEN
    RAISE EXCEPTION 'ecf_sequence_range_below_consumed_frontier';
  END IF;
  RETURN NEW;
END $$;

CREATE TRIGGER ecf_sequence_guard
  BEFORE UPDATE ON ecf_sequences
  FOR EACH ROW EXECUTE FUNCTION ecf_sequence_guard();

-- The allocation ledger is append-only: an entry is evidence of consumption.
CREATE FUNCTION ecf_sequence_audit_immutable() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  RAISE EXCEPTION 'ecf_sequence_audit_append_only';
END $$;

CREATE TRIGGER ecf_sequence_audit_immutable
  BEFORE UPDATE ON ecf_sequence_audit_logs
  FOR EACH ROW EXECUTE FUNCTION ecf_sequence_audit_immutable();
