CREATE TYPE "purchase_order_status" AS ENUM (
  'DRAFT',
  'PENDING_APPROVAL',
  'APPROVED',
  'SENT',
  'PARTIALLY_RECEIVED',
  'RECEIVED',
  'CANCELLED'
);

CREATE TABLE "suppliers" (
  "id" UUID NOT NULL DEFAULT gen_random_uuid(),
  "business_id" UUID,
  "commercial_name" TEXT NOT NULL,
  "legal_name" TEXT,
  "tax_id" TEXT,
  "contact_name" TEXT,
  "phone" TEXT,
  "whatsapp" TEXT,
  "email" TEXT,
  "address" TEXT,
  "city" TEXT,
  "country" TEXT,
  "website" TEXT,
  "payment_terms" TEXT,
  "estimated_delivery_days" INTEGER,
  "notes" TEXT,
  "logo" TEXT,
  "is_active" BOOLEAN NOT NULL DEFAULT true,
  "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updated_at" TIMESTAMP(3) NOT NULL,
  "deleted_at" TIMESTAMP(3),
  CONSTRAINT "suppliers_pkey" PRIMARY KEY ("id")
);

CREATE TABLE "purchase_order_sequences" (
  "scope" TEXT NOT NULL,
  "next_value" INTEGER NOT NULL DEFAULT 1,
  "updated_at" TIMESTAMP(3) NOT NULL,
  CONSTRAINT "purchase_order_sequences_pkey" PRIMARY KEY ("scope")
);

CREATE TABLE "purchase_orders" (
  "id" UUID NOT NULL DEFAULT gen_random_uuid(),
  "business_id" UUID,
  "branch_id" UUID,
  "order_number" TEXT NOT NULL,
  "supplier_id" UUID,
  "status" "purchase_order_status" NOT NULL DEFAULT 'DRAFT',
  "order_date" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "expected_delivery_date" TIMESTAMP(3),
  "subtotal" DECIMAL(12,2) NOT NULL DEFAULT 0,
  "discount" DECIMAL(12,2) NOT NULL DEFAULT 0,
  "shipping_cost" DECIMAL(12,2) NOT NULL DEFAULT 0,
  "additional_cost" DECIMAL(12,2) NOT NULL DEFAULT 0,
  "tax" DECIMAL(12,2) NOT NULL DEFAULT 0,
  "total" DECIMAL(12,2) NOT NULL DEFAULT 0,
  "payment_terms" TEXT,
  "payment_method" TEXT,
  "shipping_method" TEXT,
  "notes" TEXT,
  "supplier_instructions" TEXT,
  "created_by" UUID NOT NULL,
  "approved_by" UUID,
  "approved_at" TIMESTAMP(3),
  "sent_at" TIMESTAMP(3),
  "cancelled_at" TIMESTAMP(3),
  "cancellation_reason" TEXT,
  "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updated_at" TIMESTAMP(3) NOT NULL,
  "deleted_at" TIMESTAMP(3),
  CONSTRAINT "purchase_orders_pkey" PRIMARY KEY ("id")
);

CREATE TABLE "purchase_order_items" (
  "id" UUID NOT NULL DEFAULT gen_random_uuid(),
  "purchase_order_id" UUID NOT NULL,
  "product_id" UUID,
  "external_product_id" UUID,
  "product_name_snapshot" TEXT NOT NULL,
  "product_code_snapshot" TEXT,
  "description_snapshot" TEXT,
  "image_snapshot" TEXT,
  "quantity" DECIMAL(12,3) NOT NULL,
  "received_quantity" DECIMAL(12,3) NOT NULL DEFAULT 0,
  "pending_quantity" DECIMAL(12,3) NOT NULL DEFAULT 0,
  "unit_cost" DECIMAL(12,2) NOT NULL,
  "actual_unit_cost" DECIMAL(12,2),
  "subtotal" DECIMAL(12,2) NOT NULL,
  "supplier_id" UUID,
  "notes" TEXT,
  "create_inventory_product_on_receipt" BOOLEAN NOT NULL DEFAULT false,
  "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updated_at" TIMESTAMP(3) NOT NULL,
  CONSTRAINT "purchase_order_items_pkey" PRIMARY KEY ("id")
);

CREATE TABLE "purchase_receipts" (
  "id" UUID NOT NULL DEFAULT gen_random_uuid(),
  "purchase_order_id" UUID NOT NULL,
  "supplier_invoice_number" TEXT,
  "receipt_date" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "notes" TEXT,
  "invoice_image" TEXT,
  "received_by" UUID NOT NULL,
  "inventory_updated" BOOLEAN NOT NULL DEFAULT false,
  "inventory_updated_at" TIMESTAMP(3),
  "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "purchase_receipts_pkey" PRIMARY KEY ("id")
);

CREATE TABLE "purchase_receipt_items" (
  "id" UUID NOT NULL DEFAULT gen_random_uuid(),
  "purchase_receipt_id" UUID NOT NULL,
  "purchase_order_item_id" UUID NOT NULL,
  "quantity_received" DECIMAL(12,3) NOT NULL,
  "unit_cost" DECIMAL(12,2) NOT NULL,
  "condition" TEXT,
  "notes" TEXT,
  "inventory_movement_id" UUID,
  "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "purchase_receipt_items_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX "purchase_orders_order_number_key" ON "purchase_orders"("order_number");
CREATE UNIQUE INDEX "purchase_receipt_items_purchase_receipt_id_purchase_order_item_id_key" ON "purchase_receipt_items"("purchase_receipt_id", "purchase_order_item_id");
CREATE INDEX "suppliers_business_id_idx" ON "suppliers"("business_id");
CREATE INDEX "suppliers_commercial_name_idx" ON "suppliers"("commercial_name");
CREATE INDEX "suppliers_is_active_idx" ON "suppliers"("is_active");
CREATE INDEX "purchase_orders_supplier_id_idx" ON "purchase_orders"("supplier_id");
CREATE INDEX "purchase_orders_status_idx" ON "purchase_orders"("status");
CREATE INDEX "purchase_orders_order_date_idx" ON "purchase_orders"("order_date");
CREATE INDEX "purchase_orders_created_by_idx" ON "purchase_orders"("created_by");
CREATE INDEX "purchase_orders_deleted_at_idx" ON "purchase_orders"("deleted_at");
CREATE INDEX "purchase_order_items_purchase_order_id_idx" ON "purchase_order_items"("purchase_order_id");
CREATE INDEX "purchase_order_items_product_id_idx" ON "purchase_order_items"("product_id");
CREATE INDEX "purchase_order_items_supplier_id_idx" ON "purchase_order_items"("supplier_id");
CREATE INDEX "purchase_receipts_purchase_order_id_idx" ON "purchase_receipts"("purchase_order_id");
CREATE INDEX "purchase_receipts_received_by_idx" ON "purchase_receipts"("received_by");
CREATE INDEX "purchase_receipt_items_purchase_order_item_id_idx" ON "purchase_receipt_items"("purchase_order_item_id");

ALTER TABLE "purchase_orders" ADD CONSTRAINT "purchase_orders_supplier_id_fkey" FOREIGN KEY ("supplier_id") REFERENCES "suppliers"("id") ON DELETE SET NULL ON UPDATE CASCADE;
ALTER TABLE "purchase_orders" ADD CONSTRAINT "purchase_orders_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "users"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
ALTER TABLE "purchase_orders" ADD CONSTRAINT "purchase_orders_approved_by_fkey" FOREIGN KEY ("approved_by") REFERENCES "users"("id") ON DELETE SET NULL ON UPDATE CASCADE;
ALTER TABLE "purchase_order_items" ADD CONSTRAINT "purchase_order_items_purchase_order_id_fkey" FOREIGN KEY ("purchase_order_id") REFERENCES "purchase_orders"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "purchase_order_items" ADD CONSTRAINT "purchase_order_items_product_id_fkey" FOREIGN KEY ("product_id") REFERENCES "Product"("id") ON DELETE SET NULL ON UPDATE CASCADE;
ALTER TABLE "purchase_order_items" ADD CONSTRAINT "purchase_order_items_supplier_id_fkey" FOREIGN KEY ("supplier_id") REFERENCES "suppliers"("id") ON DELETE SET NULL ON UPDATE CASCADE;
ALTER TABLE "purchase_receipts" ADD CONSTRAINT "purchase_receipts_purchase_order_id_fkey" FOREIGN KEY ("purchase_order_id") REFERENCES "purchase_orders"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "purchase_receipts" ADD CONSTRAINT "purchase_receipts_received_by_fkey" FOREIGN KEY ("received_by") REFERENCES "users"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
ALTER TABLE "purchase_receipt_items" ADD CONSTRAINT "purchase_receipt_items_purchase_receipt_id_fkey" FOREIGN KEY ("purchase_receipt_id") REFERENCES "purchase_receipts"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "purchase_receipt_items" ADD CONSTRAINT "purchase_receipt_items_purchase_order_item_id_fkey" FOREIGN KEY ("purchase_order_item_id") REFERENCES "purchase_order_items"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
