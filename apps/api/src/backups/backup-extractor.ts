import { Prisma } from "@prisma/client";
import {
  BACKUP_FORMAT_VERSION,
  BACKUP_MINIMUM_COMPATIBLE_VERSION,
  BACKUP_PRODUCT,
  BackupManifest,
  BackupModulePayload,
  BackupTypeName,
} from "./backup.types";
import { sha256Hex, stableJson } from "./backup-archive.builder";

type Tx = Prisma.TransactionClient;
type ModuleSpec = {
  name: string;
  extract(tx: Tx, companyId: string): Promise<unknown[]>;
  restoreOrderHint: number;
  tenantKey: string;
  ownership: string;
  dependencies: string[];
  sensitiveFieldsToExclude: string[];
};

const BACKUP_EXTRACT_PAGE_SIZE = 1000;

function byId() {
  return { orderBy: { id: "asc" as const } };
}

function byCompanyId() {
  return { orderBy: { companyId: "asc" as const } };
}

function direct(delegateName: string, name = delegateName): ModuleSpec {
  return {
    name,
    restoreOrderHint: 100,
    tenantKey: "companyId",
    ownership: "DIRECT",
    dependencies: ["Company"],
    sensitiveFieldsToExclude: [],
    extract: async (tx, companyId) =>
      findManyPagedById(
        (tx as unknown as Record<string, { findMany(args: unknown): Promise<unknown[]> }>)[delegateName],
        { companyId },
      ),
  };
}

async function findManyPagedById(
  delegate: { findMany(args: any): Promise<unknown[]> },
  where: Record<string, unknown>,
) {
  const output: unknown[] = [];
  let lastId: string | null = null;
  for (;;) {
    const page = (await delegate.findMany({
      where: lastId ? { AND: [where, { id: { gt: lastId } }] } : where,
      orderBy: { id: "asc" },
      take: BACKUP_EXTRACT_PAGE_SIZE,
    })) as Array<Record<string, unknown>>;
    output.push(...page);
    if (page.length < BACKUP_EXTRACT_PAGE_SIZE) break;
    const nextId = page[page.length - 1]?.id;
    if (typeof nextId !== "string" || nextId === lastId) break;
    lastId = nextId;
  }
  return output;
}

export class BackupExtractor {
  readonly moduleSpecs: ModuleSpec[] = [
    {
      name: "company",
      restoreOrderHint: 10,
      tenantKey: "id",
      ownership: "TENANT_ROOT",
      dependencies: [],
      sensitiveFieldsToExclude: ["licenseKey"],
      extract: async (tx, companyId) => {
        const row = await tx.company.findUnique({
          where: { id: companyId },
          select: {
            id: true,
            name: true,
            slug: true,
            status: true,
            plan: true,
            licenseStatus: true,
            trialStartedAt: true,
            trialEndsAt: true,
            licenseActivatedAt: true,
            licenseExpiresAt: true,
            licenseBlockedAt: true,
            maxUsers: true,
            maxProducts: true,
            taxEnabled: true,
            defaultTaxId: true,
            defaultTaxRate: true,
            pricesIncludeTax: true,
            ncfEnabled: true,
            inventoryEnabled: true,
            measurementUnitsEnabled: true,
            multiWarehouseEnabled: true,
            productSource: true,
            fullposCompanyId: true,
            createdAt: true,
            updatedAt: true,
          },
        });
        return row ? [row] : [];
      },
    },
    {
      name: "users",
      restoreOrderHint: 20,
      tenantKey: "companyId OR CompanyMember.companyId",
      ownership: "DIRECT_OR_MEMBERSHIP",
      dependencies: ["Company", "CompanyMember"],
      sensitiveFieldsToExclude: ["passwordHash", "authSessions", "passwordResetTokens"],
      extract: async (tx, companyId) =>
        tx.user.findMany({
          where: {
            OR: [
              { companyId },
              { companyMemberships: { some: { companyId } } },
            ],
          },
          select: {
            id: true,
            companyId: true,
            email: true,
            nombreCompleto: true,
            telefono: true,
            numeroFlota: true,
            telefonoFamiliar: true,
            cedula: true,
            fotoCedulaUrl: true,
            fotoLicenciaUrl: true,
            fotoPersonalUrl: true,
            workContractSignatureUrl: true,
            workContractSignedAt: true,
            workContractVersion: true,
            workContractJobTitle: true,
            workContractSalary: true,
            workContractPaymentFrequency: true,
            workContractPaymentMethod: true,
            workContractWorkSchedule: true,
            workContractWorkLocation: true,
            workContractClauseOverrides: true,
            workContractCustomClauses: true,
            workContractStartDate: true,
            edad: true,
            tieneHijos: true,
            estaCasado: true,
            casaPropia: true,
            vehiculo: true,
            licenciaConducir: true,
            fechaIngreso: true,
            fechaNacimiento: true,
            cuentaNominaPreferencial: true,
            habilidades: true,
            userPermissions: true,
            role: true,
            blocked: true,
            createdAt: true,
            updatedAt: true,
          },
          orderBy: { id: "asc" },
        }),
    },
    direct("appConfig", "app_configs"),
    {
      ...direct("openSalesTicketState", "open_sales_ticket_states"),
      extract: async (tx, companyId) =>
        tx.openSalesTicketState.findMany({ where: { companyId }, ...byCompanyId() }),
    },
    direct("companyMember", "company_members"),
    direct("companyLicenseAuditLog", "company_license_audit_logs"),
    direct("product", "products"),
    direct("unitOfMeasure", "unit_of_measures"),
    direct("tax", "taxes"),
    direct("warehouse", "warehouses"),
    direct("warehouseStock", "warehouse_stocks"),
    direct("terminal", "terminals"),
    direct("inventoryMovement", "inventory_movements"),
    direct("warehouseTransfer", "warehouse_transfers"),
    direct("warehouseTransferItem", "warehouse_transfer_items"),
    {
      ...direct("inventoryZeroConfigState", "inventory_zero_config_states"),
      extract: async (tx, companyId) =>
        tx.inventoryZeroConfigState.findMany({ where: { companyId }, ...byCompanyId() }),
    },
    direct("supplier", "suppliers"),
    direct("purchaseInvoice", "purchase_invoices"),
    direct("purchaseOrder", "purchase_orders"),
    {
      ...direct("purchaseOrderItem", "purchase_order_items"),
      tenantKey: "purchaseOrder.companyId",
      ownership: "INDIRECT",
      dependencies: ["PurchaseOrder", "Product"],
      extract: async (tx, companyId) =>
        findManyPagedById(tx.purchaseOrderItem, { purchaseOrder: { companyId } }),
    },
    {
      ...direct("purchaseReceipt", "purchase_receipts"),
      tenantKey: "order.companyId",
      ownership: "INDIRECT",
      dependencies: ["PurchaseOrder"],
      extract: async (tx, companyId) =>
        findManyPagedById(tx.purchaseReceipt, { purchaseOrder: { companyId } }),
    },
    {
      ...direct("purchaseReceiptItem", "purchase_receipt_items"),
      tenantKey: "receipt.purchaseOrder.companyId",
      ownership: "INDIRECT",
      dependencies: ["PurchaseReceipt", "PurchaseOrderItem"],
      extract: async (tx, companyId) =>
        findManyPagedById(tx.purchaseReceiptItem, { receipt: { purchaseOrder: { companyId } } }),
    },
    direct("client", "clients"),
    direct("sale", "sales"),
    {
      ...direct("saleItem", "sale_items"),
      tenantKey: "sale.companyId",
      ownership: "INDIRECT",
      dependencies: ["Sale", "Product"],
      extract: async (tx, companyId) => findManyPagedById(tx.saleItem, { sale: { companyId } }),
    },
    direct("saleCreditPayment", "sale_credit_payments"),
    direct("cashboxDaily", "cashbox_dailies"),
    direct("cashSession", "cash_sessions"),
    direct("cashMovement", "cash_movements"),
    direct("ncfSequence", "ncf_sequences"),
    direct("ncfAuditLog", "ncf_audit_logs"),
    direct("close", "closes"),
    {
      ...direct("closeTransfer", "close_transfers"),
      tenantKey: "close.companyId",
      ownership: "INDIRECT",
      dependencies: ["Close"],
      extract: async (tx, companyId) => findManyPagedById(tx.closeTransfer, { close: { companyId } }),
    },
    {
      ...direct("closeTransferVoucher", "close_transfer_vouchers"),
      tenantKey: "transfer.close.companyId",
      ownership: "INDIRECT",
      dependencies: ["CloseTransfer"],
      extract: async (tx, companyId) => findManyPagedById(tx.closeTransferVoucher, { transfer: { close: { companyId } } }),
    },
    direct("depositOrder", "deposit_orders"),
    direct("depositBank", "deposit_banks"),
    {
      ...direct("depositBankAccount", "deposit_bank_accounts"),
      tenantKey: "bank.companyId",
      ownership: "INDIRECT",
      dependencies: ["DepositBank"],
      extract: async (tx, companyId) => findManyPagedById(tx.depositBankAccount, { bank: { companyId } }),
    },
    direct("fiscalInvoice", "fiscal_invoices"),
    direct("payableService", "payable_services"),
    direct("payablePayment", "payable_payments"),
    direct("payrollEmployee", "payroll_employees"),
    direct("payrollPeriod", "payroll_periods"),
    direct("payrollEmployeeConfig", "payroll_employee_configs"),
    direct("payrollEntry", "payroll_entries"),
    direct("payrollEmployeePeriodStatus", "payroll_employee_period_statuses"),
    direct("payrollServiceCommissionRequest", "payroll_service_commission_requests"),
    direct("warrantyProductConfig", "warranty_product_configs"),
    direct("cotizacion", "cotizaciones"),
    {
      ...direct("cotizacionItem", "cotizacion_items"),
      tenantKey: "cotizacion.companyId",
      ownership: "INDIRECT",
      dependencies: ["Cotizacion", "Product"],
      extract: async (tx, companyId) => findManyPagedById(tx.cotizacionItem, { cotizacion: { companyId } }),
    },
    direct("workScheduleProfile", "work_schedule_profiles"),
    {
      ...direct("workScheduleProfileDay", "work_schedule_profile_days"),
      tenantKey: "profile.companyId",
      ownership: "INDIRECT",
      dependencies: ["WorkScheduleProfile"],
      extract: async (tx, companyId) => findManyPagedById(tx.workScheduleProfileDay, { profile: { companyId } }),
    },
    direct("workCoverageRule", "work_coverage_rules"),
    direct("workEmployeeConfig", "work_employee_configs"),
    direct("workScheduleException", "work_schedule_exceptions"),
    direct("workWeekSchedule", "work_week_schedules"),
    {
      ...direct("workDayAssignment", "work_day_assignments"),
      tenantKey: "weekSchedule.companyId",
      ownership: "INDIRECT",
      dependencies: ["WorkWeekSchedule", "User"],
      extract: async (tx, companyId) => findManyPagedById(tx.workDayAssignment, { weekSchedule: { companyId } }),
    },
    direct("workScheduleAuditLog", "work_schedule_audit_logs"),
    direct("aiAssistantConversationTurn", "ai_assistant_conversation_turns"),
    direct("aiAssistantMemory", "ai_assistant_memories"),
    {
      name: "company_manual_entries",
      restoreOrderHint: 140,
      tenantKey: "ownerId",
      ownership: "DIRECT_OWNER_ID",
      dependencies: ["Company"],
      sensitiveFieldsToExclude: [],
      extract: async (tx, companyId) => tx.companyManualEntry.findMany({ where: { ownerId: companyId }, ...byId() }),
    },
  ];

  auditInventory() {
    return this.moduleSpecs.map((spec) => ({
      model: spec.name,
      table: spec.name,
      tenantKey: spec.tenantKey,
      ownership: spec.ownership,
      foreignKeyDependencies: spec.dependencies,
      backupRequired: true,
      sensitiveFieldsToExclude: spec.sensitiveFieldsToExclude,
      restoreOrderHint: spec.restoreOrderHint,
    }));
  }

  async extract(tx: Tx, params: {
    backupId: string;
    companyId: string;
    companyNameSnapshot: string;
    type: BackupTypeName;
    createdAt: Date;
    environment: string;
    backendVersion: string | null;
  }) {
    const modules: BackupModulePayload[] = [];
    for (const spec of this.moduleSpecs) {
      const records = await spec.extract(tx, params.companyId);
      const fileName = `data/${spec.name}.json`;
      const checksum = sha256Hex(Buffer.from(stableJson(records), "utf8"));
      modules.push({
        name: spec.name,
        fileName,
        records,
        recordCount: records.length,
        checksum,
      });
    }

    const manifest: BackupManifest = {
      backupFormatVersion: BACKUP_FORMAT_VERSION,
      backupId: params.backupId,
      product: BACKUP_PRODUCT,
      environment: params.environment,
      createdAt: params.createdAt.toISOString(),
      appVersion: null,
      backendVersion: params.backendVersion,
      minimumCompatibleVersion: BACKUP_MINIMUM_COMPATIBLE_VERSION,
      companyId: params.companyId,
      companyNameSnapshot: params.companyNameSnapshot,
      backupType: params.type,
      backupStatus: "COMPLETE",
      modules: modules.map((module) => module.name),
      recordCounts: Object.fromEntries(modules.map((module) => [module.name, module.recordCount])),
      checksums: Object.fromEntries(modules.map((module) => [module.name, module.checksum])),
    };

    return { manifest, modules };
  }
}
