-- Autorización de numeración otorgada por la DGII a una empresa por tipo de
-- comprobante. Tabla nueva y aditiva: no toca ninguna tabla existente.
CREATE TABLE "ecf_dgii_authorized_sequences" (
    "id" UUID NOT NULL,
    "company_id" UUID NOT NULL,
    "document_type" TEXT NOT NULL,
    "authorization_number" TEXT NOT NULL,
    "range_from" INTEGER NOT NULL,
    "range_to" INTEGER NOT NULL,
    "approved_quantity" INTEGER NOT NULL,
    "expires_at" TIMESTAMP(3),
    "evidence_id" UUID,
    "declared_by_user_id" UUID,
    "declared_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "declaration_version" TEXT NOT NULL,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "ecf_dgii_authorized_sequences_pkey" PRIMARY KEY ("id")
);

-- Una sola autorización vigente por empresa y tipo. Volver a declarar actualiza
-- la fila; el historial queda en la auditoría.
CREATE UNIQUE INDEX "ecf_dgii_authorized_sequences_company_id_document_type_key"
    ON "ecf_dgii_authorized_sequences"("company_id", "document_type");

CREATE INDEX "ecf_dgii_authorized_sequences_company_id_idx"
    ON "ecf_dgii_authorized_sequences"("company_id");

ALTER TABLE "ecf_dgii_authorized_sequences"
    ADD CONSTRAINT "ecf_dgii_authorized_sequences_company_id_fkey"
    FOREIGN KEY ("company_id") REFERENCES "companies"("id")
    ON DELETE CASCADE ON UPDATE CASCADE;
