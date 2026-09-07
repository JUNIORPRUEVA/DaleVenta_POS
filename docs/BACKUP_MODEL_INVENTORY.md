# DaleVentas Backup Model Inventory

Last updated: 2026-09-06.

This inventory is derived from `apps/api/prisma/schema.prisma` and implemented
by the Phase B backend extractor in `apps/api/src/backups/backup-extractor.ts`.
Restore order is a hint for Phase C only; restore is not implemented in Phase B.

| Model/module | Table | Tenant key | Ownership | Dependencies | Backup | Sensitive fields excluded | Restore hint |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Company | companies | id | tenant root | none | YES | licenseKey | 10 |
| User | users | companyId or CompanyMember.companyId | direct or membership | Company, CompanyMember | YES | passwordHash, sessions, reset tokens | 20 |
| CompanyMember | company_members | companyId | direct | Company, User | YES | none | 30 |
| AppConfig | app_config | companyId | direct | Company | YES | none | 40 |
| OpenSalesTicketState | open_sales_ticket_states | companyId | direct | Company | YES | none | 40 |
| CompanyLicenseAuditLog | company_license_audit_logs | companyId | direct | Company | YES | none | 90 |
| Product | Product | companyId | direct | Company, UnitOfMeasure | YES | none | 50 |
| UnitOfMeasure | unit_of_measures | companyId | direct | Company | YES | none | 45 |
| Tax | taxes | companyId | direct | Company | YES | none | 45 |
| Warehouse | warehouses | companyId | direct | Company | YES | none | 55 |
| WarehouseStock | warehouse_stocks | companyId | direct | Company, Warehouse, Product | YES | none | 70 |
| Terminal | terminals | companyId | direct | Company, Warehouse | YES | none | 60 |
| InventoryMovement | inventory_movements | companyId | direct | Company, Product, Warehouse, User | YES | none | 90 |
| WarehouseTransfer | warehouse_transfers | companyId | direct | Company, Warehouse, User | YES | none | 90 |
| WarehouseTransferItem | warehouse_transfer_items | companyId | direct | WarehouseTransfer, Product | YES | none | 91 |
| InventoryZeroConfigState | inventory_zero_config_states | companyId | direct | Company | YES | none | 80 |
| Supplier | suppliers | companyId | direct | Company | YES | none | 50 |
| PurchaseInvoice | purchase_invoices | companyId | direct | Company, Supplier, PurchaseOrder, User | YES | none | 90 |
| PurchaseOrder | purchase_orders | companyId | direct | Company, Supplier, User | YES | none | 80 |
| PurchaseOrderItem | purchase_order_items | purchaseOrder.companyId | indirect | PurchaseOrder, Product, Supplier | YES | none | 81 |
| PurchaseReceipt | purchase_receipts | purchaseOrder.companyId | indirect | PurchaseOrder, User | YES | none | 82 |
| PurchaseReceiptItem | purchase_receipt_items | receipt.purchaseOrder.companyId | indirect | PurchaseReceipt, PurchaseOrderItem, Warehouse | YES | none | 83 |
| Client | Client | companyId | direct | Company, User | YES | none | 50 |
| Sale | Sale | companyId | direct | Company, User, Client, CashSession, Terminal | YES | none | 80 |
| SaleItem | SaleItem | sale.companyId | indirect | Sale, Product, Warehouse | YES | none | 81 |
| SaleCreditPayment | sale_credit_payments | companyId | direct | Sale, User, Company | YES | none | 82 |
| CashboxDaily | cashbox_daily | companyId | direct | Company | YES | none | 60 |
| CashSession | cash_sessions | companyId | direct | Company, User, Terminal | YES | none | 70 |
| CashMovement | cash_movements | companyId | direct | Company, User | YES | none | 71 |
| NcfSequence | ncf_sequences | companyId | direct | Company | YES | none | 60 |
| NcfAuditLog | ncf_audit_logs | companyId | direct | Company, User | YES | none | 90 |
| Close | Close | companyId | direct | Company | YES | none | 80 |
| CloseTransfer | CloseTransfer | close.companyId | indirect | Close | YES | none | 81 |
| CloseTransferVoucher | CloseTransferVoucher | transfer.close.companyId | indirect | CloseTransfer | YES | none | 82 |
| DepositOrder | DepositOrder | companyId | direct | Company | YES | none | 70 |
| DepositBank | deposit_banks | companyId | direct | Company | YES | none | 60 |
| DepositBankAccount | deposit_bank_accounts | bank.companyId | indirect | DepositBank | YES | none | 61 |
| FiscalInvoice | FiscalInvoice | companyId | direct | Company | YES | none | 80 |
| PayableService | PayableService | companyId | direct | Company | YES | none | 70 |
| PayablePayment | PayablePayment | companyId | direct | Company, PayableService | YES | none | 71 |
| PayrollEmployee | PayrollEmployee | companyId | direct | Company, User | YES | none | 60 |
| PayrollPeriod | PayrollPeriod | companyId | direct | Company, User | YES | none | 61 |
| PayrollEmployeeConfig | PayrollEmployeeConfig | companyId | direct | Company, PayrollPeriod, PayrollEmployee | YES | none | 70 |
| PayrollEntry | PayrollEntry | companyId | direct | Company, PayrollPeriod, PayrollEmployee | YES | none | 80 |
| PayrollEmployeePeriodStatus | PayrollEmployeePeriodStatus | companyId | direct | Company, PayrollPeriod, PayrollEmployee | YES | none | 81 |
| PayrollServiceCommissionRequest | payroll_service_commission_requests | companyId | direct | Company, ServiceOrder, PayrollEmployee, User | YES | none | 82 |
| WarrantyProductConfig | warranty_product_configs | companyId | direct | Company, User | YES | none | 70 |
| Cotizacion | Cotizacion | companyId | direct | Company, User, Client | YES | none | 70 |
| CotizacionItem | CotizacionItem | cotizacion.companyId | indirect | Cotizacion, Product | YES | none | 71 |
| WorkScheduleProfile | work_schedule_profiles | companyId | direct | Company | YES | none | 60 |
| WorkScheduleProfileDay | work_schedule_profile_days | profile.companyId | indirect | WorkScheduleProfile | YES | none | 61 |
| WorkCoverageRule | work_coverage_rules | companyId | direct | Company | YES | none | 60 |
| WorkEmployeeConfig | work_employee_configs | companyId | direct | Company, User | YES | none | 70 |
| WorkScheduleException | work_schedule_exceptions | companyId | direct | Company, User | YES | none | 70 |
| WorkWeekSchedule | work_week_schedules | companyId | direct | Company | YES | none | 70 |
| WorkDayAssignment | work_day_assignments | weekSchedule.companyId | indirect | WorkWeekSchedule, User | YES | none | 71 |
| WorkScheduleAuditLog | work_schedule_audit_logs | companyId | direct | Company | YES | none | 90 |
| AiAssistantConversationTurn | ai_assistant_conversation_turns | companyId | direct | Company, User | YES | none | 90 |
| AiAssistantMemory | ai_assistant_memories | companyId | direct | Company, User | YES | none | 90 |
| CompanyManualEntry | CompanyManualEntry | ownerId | direct owner id | Company | YES | none | 70 |

Not included as canonical Phase B backup modules:

- `AuthSession`, `PasswordResetToken`, and reset-token secrets: excluded by
  security policy.
- Public/global reference definitions such as service categories, phases,
  purchase-order sequences, fuel prices, and website overrides without a
  confirmed tenant key: not promoted to canonical tenant backup in Phase B.
- Restore-only dependency ordering and FK rewrite behavior: deferred to Phase C.

## Phase C Restore Policy

Phase C restore is tenant-scoped and transactional. It preserves identity and
security infrastructure, then replaces only records whose ownership can be
proven from the authenticated tenant or from an already-owned parent record.

| Module | Restorable | Tenant ownership | Strategy | Delete order | Insert order | Special side effect risk |
| --- | --- | --- | --- | --- | --- | --- |
| company | NO | tenant root | preserve | n/a | n/a | Company id, slug, license, plan, and ownership are never overwritten by restore. |
| users | NO | direct or membership | preserve | n/a | n/a | Password hashes, auth identity, and security posture are preserved. |
| company_members | NO | direct | preserve | n/a | n/a | Restore must not grant/remove access or move users between companies. |
| company_license_audit_logs | NO | direct | preserve | n/a | n/a | Audit history is append-only; restore writes new audit events. |
| app_configs | YES | direct | replace | reverse FK order | before business records | Does not issue fiscal numbers or auth secrets. |
| unit_of_measures | YES | direct | replace | reverse FK order | before products | Referenced by products; tenant-owned UoM only. |
| taxes | YES | direct | replace | reverse FK order | before products/sales | Restores configuration only; no tax/fiscal service is called. |
| products | YES | direct | replace | after dependents | before sale/quote/purchase items | Persisted state only; no inventory command replay. |
| warehouses / terminals / warehouse_stocks | YES | direct | replace | after dependents | before inventory/sales | WarehouseStock restored as persisted snapshot. |
| inventory_movements / transfers / transfer_items | YES | direct or parent-owned | replace | after dependents | after stock/products | Historical rows restored directly; no adjustment commands replayed. |
| suppliers / purchase_* | YES | direct or parent-owned | replace | after dependents | parent before child | Purchase receiving services are not called. |
| clients | YES | direct | replace | after sale/quote dependents | before sale/quote | Customer records remain tenant-scoped. |
| sales / sale_items / sale_credit_payments | YES | direct or parent-owned | replace | child before parent | parent before child | No sale/refund/cancel APIs are replayed; stock/cash are not mutated twice. |
| cashbox_dailies / cash_sessions / cash_movements | YES | direct | replace | reverse FK order | before dependent sales when needed | Historical cash state only; no payment side effects. |
| ncf_sequences / ncf_audit_logs / fiscal_invoices | YES | direct | replace | reverse FK order | before/with fiscal rows | No new NCF generation. If production policy later forbids sequence rollback, preserve max(current,snapshot). UAT Phase C restores snapshot only. |
| closes / close_transfers / close_transfer_vouchers | YES | direct or parent-owned | replace | child before parent | parent before child | Historical close records only; no accounting workflow replay. |
| deposit_* / payable_* / payroll_* / warranty_* | YES | direct or parent-owned | replace | reverse FK order | parent before child | Persisted financial/payroll state only; no external side effects. |
| cotizaciones / cotizacion_items | YES | direct or parent-owned | replace | item before parent | parent before item | Quote state restored directly. |
| work_schedule_* | YES | direct or parent-owned | replace | child before parent | parent before child | Schedule rows restored directly; no scheduling engine replay. |
| ai_assistant_* | YES | direct | replace | reverse FK order | normal order | Tenant-scoped AI memory only; no secrets. |
| company_manual_entries | YES | ownerId | replace | reverse FK order | normal order | Uses `ownerId` tenant ownership rather than `companyId`. |
| open_sales_ticket_states | YES | direct | replace | reverse FK order | after sales/products | Open ticket state restored as snapshot. |

Global/shared data such as migrations, auth sessions, password reset tokens,
service catalogs without a tenant key, product image objects, R2 credentials,
database credentials, EasyPanel configuration, and production scheduler state are
not tenant-restored by Phase C.
