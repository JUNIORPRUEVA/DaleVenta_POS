-- Habilita (opt-in) registrar ventas sin comprobante electronico desde el POS.
-- Aditivo y con valor por defecto `false`: ninguna empresa existente cambia de
-- comportamiento y ninguna venta historica se ve afectada.
ALTER TABLE "ecf_company_configurations"
    ADD COLUMN "allow_sales_without_ecf" BOOLEAN NOT NULL DEFAULT false;

-- Registro de las ventas que se registraron sin comprobante electronico. Es
-- evidencia, no un permiso: guarda motivo, usuario y venta de cada excepcion.
CREATE TABLE "ecf_sales_without_document" (
    "id" UUID NOT NULL,
    "company_id" UUID NOT NULL,
    "sale_id" UUID NOT NULL,
    "reason" TEXT NOT NULL,
    "expected_document_type" TEXT,
    "registered_by_user_id" UUID,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "ecf_sales_without_document_pkey" PRIMARY KEY ("id")
);

-- Una fila por venta: registrar dos veces la misma excepcion es un error.
CREATE UNIQUE INDEX "ecf_sales_without_document_company_id_sale_id_key"
    ON "ecf_sales_without_document"("company_id", "sale_id");

CREATE INDEX "ecf_sales_without_document_company_id_created_at_idx"
    ON "ecf_sales_without_document"("company_id", "created_at");

ALTER TABLE "ecf_sales_without_document"
    ADD CONSTRAINT "ecf_sales_without_document_company_id_fkey"
    FOREIGN KEY ("company_id") REFERENCES "companies"("id")
    ON DELETE CASCADE ON UPDATE CASCADE;
