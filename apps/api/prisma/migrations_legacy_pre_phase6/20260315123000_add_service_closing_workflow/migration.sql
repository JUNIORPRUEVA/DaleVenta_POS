-- Automated service closing workflow: invoice + warranty + approvals + optional signature

DO $$
BEGIN
  CREATE TYPE "ServiceClosingApprovalStatus" AS ENUM ('PENDING', 'APPROVED', 'REJECTED');
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

DO $$
BEGIN
  CREATE TYPE "ServiceClosingSignatureStatus" AS ENUM ('PENDING', 'SIGNED', 'SKIPPED');
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

CREATE TABLE IF NOT EXISTS "ServiceClosing" (
  "id" uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "serviceId" uuid NOT NULL UNIQUE,

  "invoiceData" jsonb NULL,
  "warrantyData" jsonb NULL,

  "invoiceDraftFileId" uuid NULL,
  "warrantyDraftFileId" uuid NULL,
  "invoiceApprovedFileId" uuid NULL,
  "warrantyApprovedFileId" uuid NULL,
  "invoiceFinalFileId" uuid NULL,
  "warrantyFinalFileId" uuid NULL,

  "approvalStatus" "ServiceClosingApprovalStatus" NOT NULL DEFAULT 'PENDING',
  "approvedByUserId" uuid NULL,
  "approvedAt" timestamptz NULL,
  "rejectedByUserId" uuid NULL,
  "rejectedAt" timestamptz NULL,
  "rejectReason" text NULL,

  "signatureStatus" "ServiceClosingSignatureStatus" NOT NULL DEFAULT 'PENDING',
  "signatureFileId" uuid NULL,
  "signedAt" timestamptz NULL,

  "sentToTechnicianAt" timestamptz NULL,
  "sentToClientAt" timestamptz NULL,

  "createdAt" timestamptz NOT NULL DEFAULT now(),
  "updatedAt" timestamptz NOT NULL DEFAULT now(),

  CONSTRAINT "ServiceClosing_service_fk" FOREIGN KEY ("serviceId") REFERENCES "Service"("id") ON DELETE CASCADE,
  CONSTRAINT "ServiceClosing_approved_by_fk" FOREIGN KEY ("approvedByUserId") REFERENCES users("id") ON DELETE SET NULL,
  CONSTRAINT "ServiceClosing_rejected_by_fk" FOREIGN KEY ("rejectedByUserId") REFERENCES users("id") ON DELETE SET NULL,

  CONSTRAINT "ServiceClosing_signature_file_fk" FOREIGN KEY ("signatureFileId") REFERENCES "ServiceFile"("id") ON DELETE SET NULL,
  CONSTRAINT "ServiceClosing_invoice_draft_file_fk" FOREIGN KEY ("invoiceDraftFileId") REFERENCES "ServiceFile"("id") ON DELETE SET NULL,
  CONSTRAINT "ServiceClosing_warranty_draft_file_fk" FOREIGN KEY ("warrantyDraftFileId") REFERENCES "ServiceFile"("id") ON DELETE SET NULL,
  CONSTRAINT "ServiceClosing_invoice_approved_file_fk" FOREIGN KEY ("invoiceApprovedFileId") REFERENCES "ServiceFile"("id") ON DELETE SET NULL,
  CONSTRAINT "ServiceClosing_warranty_approved_file_fk" FOREIGN KEY ("warrantyApprovedFileId") REFERENCES "ServiceFile"("id") ON DELETE SET NULL,
  CONSTRAINT "ServiceClosing_invoice_final_file_fk" FOREIGN KEY ("invoiceFinalFileId") REFERENCES "ServiceFile"("id") ON DELETE SET NULL,
  CONSTRAINT "ServiceClosing_warranty_final_file_fk" FOREIGN KEY ("warrantyFinalFileId") REFERENCES "ServiceFile"("id") ON DELETE SET NULL
);

CREATE INDEX IF NOT EXISTS "ServiceClosing_serviceId_idx" ON "ServiceClosing"("serviceId");
CREATE INDEX IF NOT EXISTS "ServiceClosing_approvalStatus_idx" ON "ServiceClosing"("approvalStatus");
CREATE INDEX IF NOT EXISTS "ServiceClosing_signatureStatus_idx" ON "ServiceClosing"("signatureStatus");
CREATE INDEX IF NOT EXISTS "ServiceClosing_approvedAt_idx" ON "ServiceClosing"("approvedAt");
CREATE INDEX IF NOT EXISTS "ServiceClosing_signedAt_idx" ON "ServiceClosing"("signedAt");
