type RestoreStrategy = "replace" | "preserve";
type Ownership = "tenant_root" | "direct" | "indirect" | "direct_owner_id";

export type RestoreModuleSpec = {
  name: string;
  delegateName: string | null;
  ownership: Ownership;
  strategy: RestoreStrategy;
  restoreOrder: number;
  deleteOrder: number;
  deleteWhere?: (companyId: string) => Record<string, unknown>;
  validateRecord?: (
    record: Record<string, unknown>,
    companyId: string,
    ids: Map<string, Set<string>>,
  ) => void;
  reason?: string;
};

function asRecord(value: unknown): Record<string, unknown> {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new Error("Module payload record is not an object");
  }
  return value as Record<string, unknown>;
}

function expectCompanyId(record: Record<string, unknown>, companyId: string) {
  if (record.companyId !== companyId) {
    throw new Error("record companyId does not match authenticated tenant");
  }
}

function expectOwnerId(record: Record<string, unknown>, companyId: string) {
  if (record.ownerId !== companyId) {
    throw new Error("record ownerId does not match authenticated tenant");
  }
}

function expectParent(
  record: Record<string, unknown>,
  field: string,
  parentModule: string,
  ids: Map<string, Set<string>>,
) {
  const value = record[field];
  if (typeof value !== "string" || !ids.get(parentModule)?.has(value)) {
    throw new Error(`${field} does not belong to restored tenant snapshot`);
  }
}

function direct(name: string, delegateName: string, restoreOrder: number): RestoreModuleSpec {
  return {
    name,
    delegateName,
    ownership: "direct",
    strategy: "replace",
    restoreOrder,
    deleteOrder: 1000 - restoreOrder,
    deleteWhere: (companyId) => ({ companyId }),
    validateRecord: (record, companyId) => expectCompanyId(record, companyId),
  };
}

function preserve(
  name: string,
  delegateName: string | null,
  ownership: Ownership,
  restoreOrder: number,
  reason: string,
): RestoreModuleSpec {
  return {
    name,
    delegateName,
    ownership,
    strategy: "preserve",
    restoreOrder,
    deleteOrder: 1000 - restoreOrder,
    reason,
  };
}

function indirect(params: {
  name: string;
  delegateName: string;
  restoreOrder: number;
  deleteWhere: (companyId: string) => Record<string, unknown>;
  parentField: string;
  parentModule: string;
}): RestoreModuleSpec {
  return {
    name: params.name,
    delegateName: params.delegateName,
    ownership: "indirect",
    strategy: "replace",
    restoreOrder: params.restoreOrder,
    deleteOrder: 1000 - params.restoreOrder,
    deleteWhere: params.deleteWhere,
    validateRecord: (record, _companyId, ids) =>
      expectParent(record, params.parentField, params.parentModule, ids),
  };
}

export const RESTORE_MODULE_SPECS: RestoreModuleSpec[] = [
  preserve("company", "company", "tenant_root", 10, "Preserve company identity, license, slug, and tenant ownership."),
  preserve("users", "user", "direct", 20, "Preserve authentication identities and password hashes."),
  preserve("company_members", "companyMember", "direct", 30, "Preserve membership and authorization identity."),
  direct("unit_of_measures", "unitOfMeasure", 45),
  direct("taxes", "tax", 45),
  direct("app_configs", "appConfig", 46),
  direct("suppliers", "supplier", 50),
  direct("clients", "client", 50),
  direct("warehouses", "warehouse", 55),
  direct("terminals", "terminal", 60),
  direct("ncf_sequences", "ncfSequence", 60),
  direct("cashbox_dailies", "cashboxDaily", 60),
  direct("deposit_banks", "depositBank", 60),
  direct("payroll_employees", "payrollEmployee", 60),
  direct("payroll_periods", "payrollPeriod", 61),
  indirect({
    name: "deposit_bank_accounts",
    delegateName: "depositBankAccount",
    restoreOrder: 62,
    parentField: "bankId",
    parentModule: "deposit_banks",
    deleteWhere: (companyId) => ({ bank: { companyId } }),
  }),
  direct("products", "product", 65),
  direct("warranty_product_configs", "warrantyProductConfig", 66),
  direct("warehouse_stocks", "warehouseStock", 70),
  direct("cash_sessions", "cashSession", 70),
  direct("cash_movements", "cashMovement", 71),
  direct("deposit_orders", "depositOrder", 71),
  direct("payable_services", "payableService", 72),
  direct("payable_payments", "payablePayment", 73),
  direct("inventory_zero_config_states", "inventoryZeroConfigState", 74),
  direct("payroll_employee_configs", "payrollEmployeeConfig", 75),
  direct("cotizaciones", "cotizacion", 76),
  indirect({
    name: "cotizacion_items",
    delegateName: "cotizacionItem",
    restoreOrder: 77,
    parentField: "cotizacionId",
    parentModule: "cotizaciones",
    deleteWhere: (companyId) => ({ cotizacion: { companyId } }),
  }),
  direct("purchase_orders", "purchaseOrder", 80),
  indirect({
    name: "purchase_order_items",
    delegateName: "purchaseOrderItem",
    restoreOrder: 81,
    parentField: "purchaseOrderId",
    parentModule: "purchase_orders",
    deleteWhere: (companyId) => ({ purchaseOrder: { companyId } }),
  }),
  indirect({
    name: "purchase_receipts",
    delegateName: "purchaseReceipt",
    restoreOrder: 82,
    parentField: "purchaseOrderId",
    parentModule: "purchase_orders",
    deleteWhere: (companyId) => ({ purchaseOrder: { companyId } }),
  }),
  indirect({
    name: "purchase_receipt_items",
    delegateName: "purchaseReceiptItem",
    restoreOrder: 83,
    parentField: "purchaseReceiptId",
    parentModule: "purchase_receipts",
    deleteWhere: (companyId) => ({ receipt: { purchaseOrder: { companyId } } }),
  }),
  direct("purchase_invoices", "purchaseInvoice", 84),
  direct("sales", "sale", 85),
  indirect({
    name: "sale_items",
    delegateName: "saleItem",
    restoreOrder: 86,
    parentField: "saleId",
    parentModule: "sales",
    deleteWhere: (companyId) => ({ sale: { companyId } }),
  }),
  direct("sale_credit_payments", "saleCreditPayment", 87),
  direct("closes", "close", 88),
  indirect({
    name: "close_transfers",
    delegateName: "closeTransfer",
    restoreOrder: 89,
    parentField: "closeId",
    parentModule: "closes",
    deleteWhere: (companyId) => ({ close: { companyId } }),
  }),
  indirect({
    name: "close_transfer_vouchers",
    delegateName: "closeTransferVoucher",
    restoreOrder: 90,
    parentField: "transferId",
    parentModule: "close_transfers",
    deleteWhere: (companyId) => ({ transfer: { close: { companyId } } }),
  }),
  direct("inventory_movements", "inventoryMovement", 91),
  direct("warehouse_transfers", "warehouseTransfer", 92),
  indirect({
    name: "warehouse_transfer_items",
    delegateName: "warehouseTransferItem",
    restoreOrder: 93,
    parentField: "transferId",
    parentModule: "warehouse_transfers",
    deleteWhere: (companyId) => ({ transfer: { companyId } }),
  }),
  direct("ncf_audit_logs", "ncfAuditLog", 94),
  direct("fiscal_invoices", "fiscalInvoice", 95),
  direct("payroll_entries", "payrollEntry", 96),
  direct("payroll_employee_period_statuses", "payrollEmployeePeriodStatus", 97),
  direct("payroll_service_commission_requests", "payrollServiceCommissionRequest", 98),
  direct("work_schedule_profiles", "workScheduleProfile", 100),
  indirect({
    name: "work_schedule_profile_days",
    delegateName: "workScheduleProfileDay",
    restoreOrder: 101,
    parentField: "profileId",
    parentModule: "work_schedule_profiles",
    deleteWhere: (companyId) => ({ profile: { companyId } }),
  }),
  direct("work_coverage_rules", "workCoverageRule", 102),
  direct("work_employee_configs", "workEmployeeConfig", 103),
  direct("work_schedule_exceptions", "workScheduleException", 104),
  direct("work_week_schedules", "workWeekSchedule", 105),
  indirect({
    name: "work_day_assignments",
    delegateName: "workDayAssignment",
    restoreOrder: 106,
    parentField: "weekScheduleId",
    parentModule: "work_week_schedules",
    deleteWhere: (companyId) => ({ weekSchedule: { companyId } }),
  }),
  direct("work_schedule_audit_logs", "workScheduleAuditLog", 107),
  direct("ai_assistant_conversation_turns", "aiAssistantConversationTurn", 108),
  direct("ai_assistant_memories", "aiAssistantMemory", 109),
  {
    ...direct("company_manual_entries", "companyManualEntry", 110),
    ownership: "direct_owner_id",
    deleteWhere: (companyId) => ({ ownerId: companyId }),
    validateRecord: (record, companyId) => expectOwnerId(record, companyId),
  },
  direct("open_sales_ticket_states", "openSalesTicketState", 111),
  preserve(
    "company_license_audit_logs",
    "companyLicenseAuditLog",
    "direct",
    900,
    "Preserve audit history and append restore audit events instead of rolling it back.",
  ),
];

export function moduleIdSets(moduleRecords: Map<string, unknown[]>) {
  const ids = new Map<string, Set<string>>();
  for (const [moduleName, records] of moduleRecords) {
    ids.set(
      moduleName,
      new Set(
        records
          .map((record) => asRecord(record).id)
          .filter((id): id is string => typeof id === "string"),
      ),
    );
  }
  return ids;
}

export function validateRestorePayload(
  specs: RestoreModuleSpec[],
  moduleRecords: Map<string, unknown[]>,
  companyId: string,
) {
  const ids = moduleIdSets(moduleRecords);
  for (const spec of specs) {
    const records = moduleRecords.get(spec.name) ?? [];
    if (spec.strategy !== "replace") continue;
    for (const raw of records) {
      const record = asRecord(raw);
      spec.validateRecord?.(record, companyId, ids);
    }
  }
}
