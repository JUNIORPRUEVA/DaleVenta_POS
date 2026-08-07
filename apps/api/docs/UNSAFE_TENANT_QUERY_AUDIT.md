# Unsafe Tenant Query Audit

Generated at: 2026-08-07T02:06:45.231Z

Errors: 0
Warnings: 130

| Severity | File | Line | Pattern | Query |
| --- | --- | --- | --- | --- |
| warning | ai-assistant/ai-assistant.service.ts | 1082 | findMany possibly unscoped | `const manualEntries = await this.prisma.companyManualEntry.findMany({` |
| warning | ai-assistant/ai-assistant.service.ts | 1772 | count possibly unscoped | `this.prisma.companyManualEntry.count({ where: { ownerId, published: true } }),` |
| warning | ai-assistant/ai-assistant.service.ts | 1773 | count possibly unscoped | `this.prisma.client.count({ where: clientWhere }),` |
| warning | ai-assistant/ai-assistant.service.ts | 1774 | count possibly unscoped | `this.prisma.sale.count({ where: salesWhere }),` |
| warning | ai-assistant/ai-assistant.service.ts | 1775 | count possibly unscoped | `this.prisma.cotizacion.count({ where: quotesWhere }),` |
| warning | ai-assistant/ai-assistant.service.ts | 1796 | count possibly unscoped | `this.prisma.product.count(),` |
| warning | ai-assistant/ai-assistant.service.ts | 2471 | count possibly unscoped | `const count = await this.prisma.serviceOrder.count({ where: accessibleWhere });` |
| warning | ai-assistant/ai-assistant.service.ts | 2561 | findMany possibly unscoped | `const matchingOrders = await this.prisma.serviceOrder.findMany({` |
| warning | ai-assistant/ai-assistant.service.ts | 2673 | count possibly unscoped | `const count = await this.prisma.client.count({ where: accessibleWhere });` |
| warning | ai-assistant/ai-assistant.service.ts | 2747 | findMany possibly unscoped | `const matchingClients = await this.prisma.client.findMany({` |
| warning | ai-assistant/ai-assistant.service.ts | 2798 | aggregate possibly unscoped | `this.prisma.sale.aggregate({` |
| warning | ai-assistant/ai-assistant.service.ts | 2804 | aggregate possibly unscoped | `this.prisma.cotizacion.aggregate({` |
| warning | ai-assistant/ai-assistant.service.ts | 2893 | count possibly unscoped | `const saleCount = await this.prisma.sale.count({ where: { customerId: client.id, isDeleted: false } });` |
| warning | ai-assistant/ai-assistant.service.ts | 2993 | count possibly unscoped | `total = await this.prisma.product.count();` |
| warning | ai-assistant/ai-assistant.service.ts | 3028 | findMany possibly unscoped | `: await this.prisma.product.findMany({` |
| warning | ai-assistant/ai-assistant.service.ts | 3246 | count possibly unscoped | `const totalQuotes = await this.prisma.cotizacion.count({ where });` |
| warning | ai-assistant/ai-assistant.service.ts | 3321 | count possibly unscoped | `this.prisma.sale.count({ where }),` |
| warning | ai-assistant/ai-assistant.service.ts | 3363 | count possibly unscoped | `const clientSalesCount = await this.prisma.sale.count({` |
| warning | ai-assistant/ai-assistant.service.ts | 3387 | count possibly unscoped | `this.prisma.close.count({ where: { date: { gte: todayStart, lte: todayEnd } } }),` |
| warning | ai-assistant/ai-assistant.service.ts | 3388 | count possibly unscoped | `this.prisma.depositOrder.count({ where: { status: DepositOrderStatus.PENDING } }),` |
| warning | cash/cash.service.ts | 229 | findMany possibly unscoped | `return this.prisma.cashMovement.findMany({` |
| warning | cash/cash.service.ts | 257 | findMany possibly unscoped | `const rows = await this.prisma.cashMovement.findMany({` |
| warning | cash/cash.service.ts | 319 | findMany possibly unscoped | `return this.prisma.cashSession.findMany({` |
| warning | cash/cash.service.ts | 343 | findMany possibly unscoped | `this.prisma.cashMovement.findMany({` |
| warning | cash/cash.service.ts | 387 | findMany possibly unscoped | `this.prisma.sale.findMany({` |
| warning | cash/cash.service.ts | 412 | findMany possibly unscoped | `this.prisma.saleCreditPayment.findMany({` |
| warning | clients/clients.service.ts | 376 | findMany possibly unscoped | `this.prisma.client.findMany({` |
| warning | clients/clients.service.ts | 382 | count possibly unscoped | `this.prisma.client.count({ where }),` |
| warning | clients/clients.service.ts | 467 | findMany possibly unscoped | `const clients = await this.prisma.client.findMany({` |
| warning | clients/clients.service.ts | 483 | findMany possibly unscoped | `const quotations = await this.prisma.cotizacion.findMany({` |
| warning | clients/clients.service.ts | 534 | aggregate possibly unscoped | `this.prisma.sale.aggregate({` |
| warning | clients/clients.service.ts | 540 | aggregate possibly unscoped | `this.prisma.serviceOrder.aggregate({` |
| warning | clients/clients.service.ts | 545 | aggregate possibly unscoped | `this.prisma.service.aggregate({` |
| warning | clients/clients.service.ts | 551 | aggregate possibly unscoped | `this.prisma.serviceEvidence.aggregate({` |
| warning | clients/clients.service.ts | 556 | aggregate possibly unscoped | `this.prisma.serviceReport.aggregate({` |
| warning | clients/clients.service.ts | 561 | aggregate possibly unscoped | `this.prisma.cotizacion.aggregate({` |
| warning | contabilidad/contabilidad.service.ts | 256 | findMany possibly unscoped | `return await this.prisma.depositOrder.findMany({` |
| warning | contabilidad/contabilidad.service.ts | 950 | findMany possibly unscoped | `return this.prisma.close.findMany({` |
| warning | contabilidad/contabilidad.service.ts | 1001 | findMany possibly unscoped | `const closes = await this.prisma.close.findMany({` |
| warning | contabilidad/contabilidad.service.ts | 1056 | findMany possibly unscoped | `const deposits = await this.prisma.depositOrder.findMany({` |
| warning | contabilidad/contabilidad.service.ts | 1372 | findMany possibly unscoped | `const existing = await this.prisma.close.findMany({` |
| warning | contabilidad/contabilidad.service.ts | 1950 | findMany possibly unscoped | `const recipients = await this.prisma.user.findMany({` |
| warning | contabilidad/contabilidad.service.ts | 1988 | findMany possibly unscoped | `const previous = await this.prisma.close.findMany({` |
| warning | contabilidad/contabilidad.service.ts | 2557 | count possibly unscoped | `const correctionCount = await this.prisma.depositOrder.count({` |
| warning | contabilidad/contabilidad.service.ts | 2613 | findMany possibly unscoped | `return this.prisma.fiscalInvoice.findMany({` |
| warning | contabilidad/contabilidad.service.ts | 2696 | findMany possibly unscoped | `return this.prisma.payableService.findMany({` |
| warning | contabilidad/contabilidad.service.ts | 2832 | findMany possibly unscoped | `return this.prisma.payablePayment.findMany({` |
| warning | cotizaciones/cotizaciones.service.ts | 318 | findMany possibly unscoped | `const adminUsers = await this.prisma.user.findMany({` |
| warning | cotizaciones/cotizaciones.service.ts | 579 | findMany possibly unscoped | `const items = await this.prisma.cotizacion.findMany({` |
| warning | cotizaciones/cotizaciones.service.ts | 1054 | findMany possibly unscoped | `const quotes = await this.prisma.cotizacion.findMany({` |
| warning | cotizaciones/cotizaciones.service.ts | 1277 | findMany possibly unscoped | `products = await this.prisma.product.findMany({` |
| warning | cotizaciones/cotizaciones.service.ts | 1518 | findMany possibly unscoped | `const entries = await this.prisma.companyManualEntry.findMany({` |
| warning | cotizaciones/cotizaciones.service.ts | 1685 | count possibly unscoped | `const totalSales = await this.prisma.sale.count({` |
| warning | cotizaciones/cotizaciones.service.ts | 1705 | count possibly unscoped | `const totalClients = await this.prisma.client.count({` |
| warning | cotizaciones/cotizaciones.service.ts | 1725 | count possibly unscoped | `const totalQuotes = await this.prisma.cotizacion.count({` |
| warning | license/license.service.ts | 116 | count possibly unscoped | `this.prisma.company.count({ where }),` |
| warning | license/license.service.ts | 117 | findMany possibly unscoped | `this.prisma.company.findMany({` |
| warning | license/license.service.ts | 133 | findMany possibly unscoped | `const auditLogs = await this.prisma.companyLicenseAuditLog.findMany({` |
| warning | license/license.service.ts | 291 | count possibly unscoped | `this.prisma.user.count({` |
| warning | locations/locations.service.ts | 53 | findMany possibly unscoped | `return prismaAny.userLocation.findMany({` |
| warning | notifications/notifications.service.ts | 454 | findMany possibly unscoped | `const rows = await tx.notificationOutbox.findMany({` |
| warning | notifications/service-order-notification-jobs.processor.ts | 34 | findMany possibly unscoped | `const rows = await tx.serviceOrderNotificationJob.findMany({` |
| warning | notifications/service-order-notifications.listener.ts | 1334 | count possibly unscoped | `const count = await this.prisma.serviceOrderNotificationJob.count({` |
| warning | notifications/service-order-notifications.listener.ts | 1409 | count possibly unscoped | `return this.prisma.notificationOutbox.count({` |
| warning | notifications/service-order-notifications.listener.ts | 1454 | findMany possibly unscoped | `const users = await this.prisma.user.findMany({` |
| warning | payroll/payroll.service.ts | 59 | findMany possibly unscoped | `return this.prisma.payrollPeriod.findMany({` |
| warning | payroll/payroll.service.ts | 70 | count possibly unscoped | `const count = await this.prisma.payrollPeriod.count({` |
| warning | payroll/payroll.service.ts | 110 | findMany possibly unscoped | `const openPeriods = await this.prisma.payrollPeriod.findMany({` |
| warning | payroll/payroll.service.ts | 189 | findMany possibly unscoped | `return this.prisma.payrollEmployee.findMany({` |
| warning | payroll/payroll.service.ts | 336 | findMany possibly unscoped | `return this.prisma.payrollEntry.findMany({` |
| warning | payroll/payroll.service.ts | 532 | findMany possibly unscoped | `return this.prisma.payrollServiceCommissionRequest.findMany({` |
| warning | payroll/payroll.service.ts | 832 | findMany possibly unscoped | `return this.prisma.payrollEmployeePeriodStatus.findMany({` |
| warning | payroll/payroll.service.ts | 1237 | findMany possibly unscoped | `const direct = await this.prisma.payrollEmployee.findMany({` |
| warning | payroll/payroll.service.ts | 1245 | findMany possibly unscoped | `const fallback = await this.prisma.payrollEmployee.findMany({` |
| warning | payroll/payroll.service.ts | 1308 | findMany possibly unscoped | `const legacyMatches = await this.prisma.payrollEmployee.findMany({` |
| warning | payroll/payroll.service.ts | 1420 | aggregate possibly unscoped | `const aggregate = await this.prisma.sale.aggregate({` |
| warning | payroll/payroll.service.ts | 1468 | findMany possibly unscoped | `const users = await this.prisma.user.findMany({` |
| warning | payroll/payroll.service.ts | 1479 | findMany possibly unscoped | `const payrollUsers = await this.prisma.payrollEmployee.findMany({` |
| warning | products/products.service.ts | 172 | findMany possibly unscoped | `const candidates = await tx.product.findMany({` |
| warning | products/products.service.ts | 224 | count possibly unscoped | `tx.saleItem.count({ where: { productId } }),` |
| warning | products/products.service.ts | 225 | count possibly unscoped | `tx.cotizacionItem.count({ where: { productId } }),` |
| warning | products/products.service.ts | 226 | count possibly unscoped | `tx.purchaseOrderItem.count({ where: { productId } }),` |
| warning | products/products.service.ts | 227 | count possibly unscoped | `tx.websiteProductOverride.count({ where: { productId } }),` |
| warning | products/products.service.ts | 244 | findMany possibly unscoped | `const candidates = await tx.product.findMany({` |
| warning | products/products.service.ts | 505 | findMany possibly unscoped | `const products = await this.prisma.product.findMany({` |
| warning | products/products.service.ts | 512 | findMany possibly unscoped | `const products = await this.prisma.product.findMany({` |
| warning | purchases/purchases.service.ts | 59 | findMany possibly unscoped | `const rows = await this.prisma.supplier.findMany({` |
| warning | purchases/purchases.service.ts | 114 | findMany possibly unscoped | `return this.prisma.purchaseInvoice.findMany({` |
| warning | purchases/purchases.service.ts | 235 | findMany possibly unscoped | `return this.prisma.purchaseOrder.findMany({` |
| warning | purchases/purchases.service.ts | 549 | findMany possibly unscoped | `const refreshedItems = await tx.purchaseOrderItem.findMany({` |
| warning | purchases/purchases.service.ts | 574 | findMany possibly unscoped | `const products = await this.prisma.product.findMany({` |
| warning | purchases/purchases.service.ts | 761 | findMany possibly unscoped | `? await this.prisma.product.findMany({` |
| warning | purchases/purchases.service.ts | 773 | findMany possibly unscoped | `? await this.prisma.supplier.findMany({` |
| warning | purchases/purchases.service.ts | 890 | findMany possibly unscoped | `this.prisma.purchaseOrder.findMany({` |
| warning | reports/reports.service.ts | 52 | findMany possibly unscoped | `this.prisma.sale.findMany({` |
| warning | reports/reports.service.ts | 64 | findMany possibly unscoped | `this.prisma.sale.findMany({` |
| warning | reports/reports.service.ts | 76 | findMany possibly unscoped | `this.prisma.product.findMany({` |
| warning | reports/reports.service.ts | 87 | findMany possibly unscoped | `this.prisma.cashMovement.findMany({` |
| warning | sales/sales.service.ts | 184 | findMany possibly unscoped | `return await this.prisma.sale.findMany({` |
| warning | sales/sales.service.ts | 216 | findMany possibly unscoped | `return await this.prisma.sale.findMany({` |
| warning | sales/sales.service.ts | 246 | findMany possibly unscoped | `return this.prisma.sale.findMany({` |
| warning | sales/sales.service.ts | 287 | aggregate possibly unscoped | `this.prisma.sale.aggregate({` |
| warning | sales/sales.service.ts | 296 | count possibly unscoped | `this.prisma.sale.count({ where }),` |
| warning | sales/sales.service.ts | 360 | findMany possibly unscoped | `users = await this.prisma.user.findMany({` |
| warning | sales/sales.service.ts | 446 | findMany possibly unscoped | `products = await this.prisma.product.findMany({` |
| warning | sales/sales.service.ts | 807 | findMany possibly unscoped | `return await this.prisma.sale.findMany({` |
| warning | users/users.service.ts | 747 | findMany possibly unscoped | `return this.prisma.user.findMany({` |
| warning | warranty-configs/warranty-configs.service.ts | 43 | findMany possibly unscoped | `const items = await this.prisma.warrantyProductConfig.findMany({` |
| warning | warranty-configs/warranty-configs.service.ts | 142 | findMany possibly unscoped | `const configs = await this.prisma.warrantyProductConfig.findMany({` |
| warning | work-scheduling/work-scheduling.service.ts | 183 | findMany possibly unscoped | `const existing = await this.prisma.workEmployeeConfig.findMany({` |
| warning | work-scheduling/work-scheduling.service.ts | 199 | findMany possibly unscoped | `const users = await this.prisma.user.findMany({` |
| warning | work-scheduling/work-scheduling.service.ts | 214 | findMany possibly unscoped | `const configs = await this.prisma.workEmployeeConfig.findMany({` |
| warning | work-scheduling/work-scheduling.service.ts | 345 | findMany possibly unscoped | `const profiles = await this.prisma.workScheduleProfile.findMany({` |
| warning | work-scheduling/work-scheduling.service.ts | 493 | findMany possibly unscoped | `const rules = await this.prisma.workCoverageRule.findMany({` |
| warning | work-scheduling/work-scheduling.service.ts | 551 | findMany possibly unscoped | `const list = await this.prisma.workScheduleException.findMany({` |
| warning | work-scheduling/work-scheduling.service.ts | 755 | findMany possibly unscoped | `const users = await this.prisma.user.findMany({` |
| warning | work-scheduling/work-scheduling.service.ts | 769 | findMany possibly unscoped | `const configs = await this.prisma.workEmployeeConfig.findMany({` |
| warning | work-scheduling/work-scheduling.service.ts | 996 | findMany possibly unscoped | `const assignments = await this.prisma.workDayAssignment.findMany({` |
| warning | work-scheduling/work-scheduling.service.ts | 1003 | findMany possibly unscoped | `const users = await this.prisma.user.findMany({` |
| warning | work-scheduling/work-scheduling.service.ts | 1009 | findMany possibly unscoped | `const configs = await this.prisma.workEmployeeConfig.findMany({` |
| warning | work-scheduling/work-scheduling.service.ts | 1076 | findMany possibly unscoped | `const assignments = await this.prisma.workDayAssignment.findMany({` |
| warning | work-scheduling/work-scheduling.service.ts | 1094 | findMany possibly unscoped | `const users = await this.prisma.user.findMany({` |
| warning | work-scheduling/work-scheduling.service.ts | 1141 | findMany possibly unscoped | `const profileDays = await this.prisma.workScheduleProfileDay.findMany({` |
| warning | work-scheduling/work-scheduling.service.ts | 1149 | findMany possibly unscoped | `const exceptions = await this.prisma.workScheduleException.findMany({` |
| warning | work-scheduling/work-scheduling.service.ts | 1260 | findMany possibly unscoped | `? await tx.workDayAssignment.findMany({` |
| warning | work-scheduling/work-scheduling.service.ts | 1383 | findMany possibly unscoped | `const [fromA, toA] = await this.prisma.workDayAssignment.findMany({` |
| warning | work-scheduling/work-scheduling.service.ts | 1482 | findMany possibly unscoped | `const list = await this.prisma.workDayAssignment.findMany({` |
| warning | work-scheduling/work-scheduling.service.ts | 1630 | findMany possibly unscoped | `const logs = await this.prisma.workScheduleAuditLog.findMany({` |
| warning | work-scheduling/work-scheduling.service.ts | 1672 | findMany possibly unscoped | `const users = await this.prisma.user.findMany({` |
| warning | work-scheduling/work-scheduling.service.ts | 1697 | findMany possibly unscoped | `const weeks = await this.prisma.workWeekSchedule.findMany({` |
