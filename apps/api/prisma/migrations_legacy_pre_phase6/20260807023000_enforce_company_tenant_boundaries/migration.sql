DO $$
DECLARE
  table_name text;
  invalid_count integer;
  tenant_tables text[] := ARRAY[
    'Product',
    'suppliers',
    'purchase_invoices',
    'purchase_orders',
    'Client',
    'Sale',
    'sale_credit_payments',
    'cashbox_daily',
    'cash_sessions',
    'cash_movements',
    'Close',
    'DepositOrder',
    'FiscalInvoice',
    'PayableService',
    'PayablePayment',
    'PayrollEmployee',
    'PayrollPeriod',
    'PayrollEmployeeConfig',
    'PayrollEntry',
    'PayrollEmployeePeriodStatus',
    'payroll_service_commission_requests',
    'warranty_product_configs',
    'Cotizacion',
    'work_schedule_profiles',
    'work_coverage_rules',
    'work_week_schedules',
    'work_schedule_audit_logs',
    'ai_assistant_conversation_turns',
    'ai_assistant_memories'
  ];
BEGIN
  FOREACH table_name IN ARRAY tenant_tables LOOP
    EXECUTE format('SELECT COUNT(*) FROM %I WHERE company_id IS NULL', table_name)
      INTO invalid_count;
    IF invalid_count > 0 THEN
      RAISE EXCEPTION 'Cannot enforce tenant boundary: table % has % row(s) without company_id', table_name, invalid_count;
    END IF;

    EXECUTE format(
      'SELECT COUNT(*) FROM %I t LEFT JOIN companies c ON c.id = t.company_id WHERE c.id IS NULL',
      table_name
    ) INTO invalid_count;
    IF invalid_count > 0 THEN
      RAISE EXCEPTION 'Cannot enforce tenant boundary: table % has % row(s) with invalid company_id', table_name, invalid_count;
    END IF;
  END LOOP;
END $$;

ALTER TABLE "Product" ALTER COLUMN "company_id" SET NOT NULL;
ALTER TABLE "suppliers" ALTER COLUMN "company_id" SET NOT NULL;
ALTER TABLE "purchase_invoices" ALTER COLUMN "company_id" SET NOT NULL;
ALTER TABLE "purchase_orders" ALTER COLUMN "company_id" SET NOT NULL;
ALTER TABLE "Client" ALTER COLUMN "company_id" SET NOT NULL;
ALTER TABLE "Sale" ALTER COLUMN "company_id" SET NOT NULL;
ALTER TABLE "sale_credit_payments" ALTER COLUMN "company_id" SET NOT NULL;
ALTER TABLE "cashbox_daily" ALTER COLUMN "company_id" SET NOT NULL;
ALTER TABLE "cash_sessions" ALTER COLUMN "company_id" SET NOT NULL;
ALTER TABLE "cash_movements" ALTER COLUMN "company_id" SET NOT NULL;
ALTER TABLE "Close" ALTER COLUMN "company_id" SET NOT NULL;
ALTER TABLE "DepositOrder" ALTER COLUMN "company_id" SET NOT NULL;
ALTER TABLE "FiscalInvoice" ALTER COLUMN "company_id" SET NOT NULL;
ALTER TABLE "PayableService" ALTER COLUMN "company_id" SET NOT NULL;
ALTER TABLE "PayablePayment" ALTER COLUMN "company_id" SET NOT NULL;
ALTER TABLE "PayrollEmployee" ALTER COLUMN "company_id" SET NOT NULL;
ALTER TABLE "PayrollPeriod" ALTER COLUMN "company_id" SET NOT NULL;
ALTER TABLE "PayrollEmployeeConfig" ALTER COLUMN "company_id" SET NOT NULL;
ALTER TABLE "PayrollEntry" ALTER COLUMN "company_id" SET NOT NULL;
ALTER TABLE "PayrollEmployeePeriodStatus" ALTER COLUMN "company_id" SET NOT NULL;
ALTER TABLE "payroll_service_commission_requests" ALTER COLUMN "company_id" SET NOT NULL;
ALTER TABLE "warranty_product_configs" ALTER COLUMN "company_id" SET NOT NULL;
ALTER TABLE "Cotizacion" ALTER COLUMN "company_id" SET NOT NULL;
ALTER TABLE "work_schedule_profiles" ALTER COLUMN "company_id" SET NOT NULL;
ALTER TABLE "work_coverage_rules" ALTER COLUMN "company_id" SET NOT NULL;
ALTER TABLE "work_week_schedules" ALTER COLUMN "company_id" SET NOT NULL;
ALTER TABLE "work_schedule_audit_logs" ALTER COLUMN "company_id" SET NOT NULL;
ALTER TABLE "ai_assistant_conversation_turns" ALTER COLUMN "company_id" SET NOT NULL;
ALTER TABLE "ai_assistant_memories" ALTER COLUMN "company_id" SET NOT NULL;

ALTER TABLE "work_coverage_rules" DROP CONSTRAINT IF EXISTS "work_coverage_rules_role_weekday_key";
ALTER TABLE "work_week_schedules" DROP CONSTRAINT IF EXISTS "work_week_schedules_week_start_date_key";

CREATE UNIQUE INDEX IF NOT EXISTS "work_coverage_rules_company_id_role_weekday_key"
  ON "work_coverage_rules"("company_id", "role", "weekday");
CREATE UNIQUE INDEX IF NOT EXISTS "work_week_schedules_company_id_week_start_date_key"
  ON "work_week_schedules"("company_id", "week_start_date");

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'Product_company_id_fkey') THEN
    ALTER TABLE "Product" ADD CONSTRAINT "Product_company_id_fkey" FOREIGN KEY ("company_id") REFERENCES "companies"("id") ON DELETE CASCADE ON UPDATE CASCADE;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'suppliers_company_id_fkey') THEN
    ALTER TABLE "suppliers" ADD CONSTRAINT "suppliers_company_id_fkey" FOREIGN KEY ("company_id") REFERENCES "companies"("id") ON DELETE CASCADE ON UPDATE CASCADE;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'purchase_invoices_company_id_fkey') THEN
    ALTER TABLE "purchase_invoices" ADD CONSTRAINT "purchase_invoices_company_id_fkey" FOREIGN KEY ("company_id") REFERENCES "companies"("id") ON DELETE CASCADE ON UPDATE CASCADE;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'purchase_orders_company_id_fkey') THEN
    ALTER TABLE "purchase_orders" ADD CONSTRAINT "purchase_orders_company_id_fkey" FOREIGN KEY ("company_id") REFERENCES "companies"("id") ON DELETE CASCADE ON UPDATE CASCADE;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'Client_company_id_fkey') THEN
    ALTER TABLE "Client" ADD CONSTRAINT "Client_company_id_fkey" FOREIGN KEY ("company_id") REFERENCES "companies"("id") ON DELETE CASCADE ON UPDATE CASCADE;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'Sale_company_id_fkey') THEN
    ALTER TABLE "Sale" ADD CONSTRAINT "Sale_company_id_fkey" FOREIGN KEY ("company_id") REFERENCES "companies"("id") ON DELETE CASCADE ON UPDATE CASCADE;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'sale_credit_payments_company_id_fkey') THEN
    ALTER TABLE "sale_credit_payments" ADD CONSTRAINT "sale_credit_payments_company_id_fkey" FOREIGN KEY ("company_id") REFERENCES "companies"("id") ON DELETE CASCADE ON UPDATE CASCADE;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'cashbox_daily_company_id_fkey') THEN
    ALTER TABLE "cashbox_daily" ADD CONSTRAINT "cashbox_daily_company_id_fkey" FOREIGN KEY ("company_id") REFERENCES "companies"("id") ON DELETE CASCADE ON UPDATE CASCADE;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'cash_sessions_company_id_fkey') THEN
    ALTER TABLE "cash_sessions" ADD CONSTRAINT "cash_sessions_company_id_fkey" FOREIGN KEY ("company_id") REFERENCES "companies"("id") ON DELETE CASCADE ON UPDATE CASCADE;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'cash_movements_company_id_fkey') THEN
    ALTER TABLE "cash_movements" ADD CONSTRAINT "cash_movements_company_id_fkey" FOREIGN KEY ("company_id") REFERENCES "companies"("id") ON DELETE CASCADE ON UPDATE CASCADE;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'Close_company_id_fkey') THEN
    ALTER TABLE "Close" ADD CONSTRAINT "Close_company_id_fkey" FOREIGN KEY ("company_id") REFERENCES "companies"("id") ON DELETE CASCADE ON UPDATE CASCADE;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'DepositOrder_company_id_fkey') THEN
    ALTER TABLE "DepositOrder" ADD CONSTRAINT "DepositOrder_company_id_fkey" FOREIGN KEY ("company_id") REFERENCES "companies"("id") ON DELETE CASCADE ON UPDATE CASCADE;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'FiscalInvoice_company_id_fkey') THEN
    ALTER TABLE "FiscalInvoice" ADD CONSTRAINT "FiscalInvoice_company_id_fkey" FOREIGN KEY ("company_id") REFERENCES "companies"("id") ON DELETE CASCADE ON UPDATE CASCADE;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'PayableService_company_id_fkey') THEN
    ALTER TABLE "PayableService" ADD CONSTRAINT "PayableService_company_id_fkey" FOREIGN KEY ("company_id") REFERENCES "companies"("id") ON DELETE CASCADE ON UPDATE CASCADE;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'PayablePayment_company_id_fkey') THEN
    ALTER TABLE "PayablePayment" ADD CONSTRAINT "PayablePayment_company_id_fkey" FOREIGN KEY ("company_id") REFERENCES "companies"("id") ON DELETE CASCADE ON UPDATE CASCADE;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'PayrollEmployee_company_id_fkey') THEN
    ALTER TABLE "PayrollEmployee" ADD CONSTRAINT "PayrollEmployee_company_id_fkey" FOREIGN KEY ("company_id") REFERENCES "companies"("id") ON DELETE CASCADE ON UPDATE CASCADE;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'PayrollPeriod_company_id_fkey') THEN
    ALTER TABLE "PayrollPeriod" ADD CONSTRAINT "PayrollPeriod_company_id_fkey" FOREIGN KEY ("company_id") REFERENCES "companies"("id") ON DELETE CASCADE ON UPDATE CASCADE;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'PayrollEmployeeConfig_company_id_fkey') THEN
    ALTER TABLE "PayrollEmployeeConfig" ADD CONSTRAINT "PayrollEmployeeConfig_company_id_fkey" FOREIGN KEY ("company_id") REFERENCES "companies"("id") ON DELETE CASCADE ON UPDATE CASCADE;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'PayrollEntry_company_id_fkey') THEN
    ALTER TABLE "PayrollEntry" ADD CONSTRAINT "PayrollEntry_company_id_fkey" FOREIGN KEY ("company_id") REFERENCES "companies"("id") ON DELETE CASCADE ON UPDATE CASCADE;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'PayrollEmployeePeriodStatus_company_id_fkey') THEN
    ALTER TABLE "PayrollEmployeePeriodStatus" ADD CONSTRAINT "PayrollEmployeePeriodStatus_company_id_fkey" FOREIGN KEY ("company_id") REFERENCES "companies"("id") ON DELETE CASCADE ON UPDATE CASCADE;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'payroll_service_commission_requests_company_id_fkey') THEN
    ALTER TABLE "payroll_service_commission_requests" ADD CONSTRAINT "payroll_service_commission_requests_company_id_fkey" FOREIGN KEY ("company_id") REFERENCES "companies"("id") ON DELETE CASCADE ON UPDATE CASCADE;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'warranty_product_configs_company_id_fkey') THEN
    ALTER TABLE "warranty_product_configs" ADD CONSTRAINT "warranty_product_configs_company_id_fkey" FOREIGN KEY ("company_id") REFERENCES "companies"("id") ON DELETE CASCADE ON UPDATE CASCADE;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'Cotizacion_company_id_fkey') THEN
    ALTER TABLE "Cotizacion" ADD CONSTRAINT "Cotizacion_company_id_fkey" FOREIGN KEY ("company_id") REFERENCES "companies"("id") ON DELETE CASCADE ON UPDATE CASCADE;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'work_schedule_profiles_company_id_fkey') THEN
    ALTER TABLE "work_schedule_profiles" ADD CONSTRAINT "work_schedule_profiles_company_id_fkey" FOREIGN KEY ("company_id") REFERENCES "companies"("id") ON DELETE CASCADE ON UPDATE CASCADE;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'work_coverage_rules_company_id_fkey') THEN
    ALTER TABLE "work_coverage_rules" ADD CONSTRAINT "work_coverage_rules_company_id_fkey" FOREIGN KEY ("company_id") REFERENCES "companies"("id") ON DELETE CASCADE ON UPDATE CASCADE;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'work_week_schedules_company_id_fkey') THEN
    ALTER TABLE "work_week_schedules" ADD CONSTRAINT "work_week_schedules_company_id_fkey" FOREIGN KEY ("company_id") REFERENCES "companies"("id") ON DELETE CASCADE ON UPDATE CASCADE;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'work_schedule_audit_logs_company_id_fkey') THEN
    ALTER TABLE "work_schedule_audit_logs" ADD CONSTRAINT "work_schedule_audit_logs_company_id_fkey" FOREIGN KEY ("company_id") REFERENCES "companies"("id") ON DELETE CASCADE ON UPDATE CASCADE;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'ai_assistant_conversation_turns_company_id_fkey') THEN
    ALTER TABLE "ai_assistant_conversation_turns" ADD CONSTRAINT "ai_assistant_conversation_turns_company_id_fkey" FOREIGN KEY ("company_id") REFERENCES "companies"("id") ON DELETE CASCADE ON UPDATE CASCADE;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'ai_assistant_memories_company_id_fkey') THEN
    ALTER TABLE "ai_assistant_memories" ADD CONSTRAINT "ai_assistant_memories_company_id_fkey" FOREIGN KEY ("company_id") REFERENCES "companies"("id") ON DELETE CASCADE ON UPDATE CASCADE;
  END IF;
END $$;
