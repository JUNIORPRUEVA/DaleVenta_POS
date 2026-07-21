CREATE TABLE "purchase_invoices" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "supplier_id" UUID NOT NULL,
    "purchase_order_id" UUID,
    "invoice_number" TEXT,
    "invoice_date" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "amount" DECIMAL(12,2),
    "currency" TEXT NOT NULL DEFAULT 'DOP',
    "file_name" TEXT NOT NULL,
    "file_url" TEXT NOT NULL,
    "storage_key" TEXT NOT NULL,
    "mime_type" TEXT NOT NULL,
    "file_size" INTEGER NOT NULL,
    "notes" TEXT,
    "uploaded_by" UUID NOT NULL,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "deleted_at" TIMESTAMP(3),

    CONSTRAINT "purchase_invoices_pkey" PRIMARY KEY ("id")
);

CREATE INDEX "purchase_invoices_supplier_id_idx" ON "purchase_invoices"("supplier_id");
CREATE INDEX "purchase_invoices_purchase_order_id_idx" ON "purchase_invoices"("purchase_order_id");
CREATE INDEX "purchase_invoices_invoice_date_idx" ON "purchase_invoices"("invoice_date");
CREATE INDEX "purchase_invoices_deleted_at_idx" ON "purchase_invoices"("deleted_at");

ALTER TABLE "purchase_invoices"
    ADD CONSTRAINT "purchase_invoices_supplier_id_fkey"
    FOREIGN KEY ("supplier_id") REFERENCES "suppliers"("id")
    ON DELETE RESTRICT ON UPDATE CASCADE;

ALTER TABLE "purchase_invoices"
    ADD CONSTRAINT "purchase_invoices_purchase_order_id_fkey"
    FOREIGN KEY ("purchase_order_id") REFERENCES "purchase_orders"("id")
    ON DELETE SET NULL ON UPDATE CASCADE;

ALTER TABLE "purchase_invoices"
    ADD CONSTRAINT "purchase_invoices_uploaded_by_fkey"
    FOREIGN KEY ("uploaded_by") REFERENCES "users"("id")
    ON DELETE RESTRICT ON UPDATE CASCADE;
