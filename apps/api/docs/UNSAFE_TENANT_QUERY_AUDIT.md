# Unsafe Tenant Query Audit

Generated at: 2026-08-05T03:45:06.607Z

Errors: 0
Warnings: 128

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
| warning | cash/cash.service.ts | 226 | findMany possibly unscoped | `return this.prisma.cashMovement.findMany({` |
| warning | cash/cash.service.ts | 254 | findMany possibly unscoped | `const rows = await this.prisma.cashMovement.findMany({` |
| warning | cash/cash.service.ts | 316 | findMany possibly unscoped | `return this.prisma.cashSession.findMany({` |
| warning | cash/cash.service.ts | 340 | findMany possibly unscoped | `this.prisma.cashMovement.findMany({` |
| warning | cash/cash.service.ts | 384 | findMany possibly unscoped | `this.prisma.sale.findMany({` |
| warning | cash/cash.service.ts | 408 | findMany possibly unscoped | `this.prisma.cashMovement.findMany({ where: { sessionId } }),` |
| warning | cash/cash.service.ts | 409 | findMany possibly unscoped | `this.prisma.saleCreditPayment.findMany({` |
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
| warning | contabilidad/contabilidad.service.ts | 948 | findMany possibly unscoped | `return this.prisma.close.findMany({` |
| warning | contabilidad/contabilidad.service.ts | 999 | findMany possibly unscoped | `const closes = await this.prisma.close.findMany({` |
| warning | contabilidad/contabilidad.service.ts | 1054 | findMany possibly unscoped | `const deposits = await this.prisma.depositOrder.findMany({` |
| warning | contabilidad/contabilidad.service.ts | 1370 | findMany possibly unscoped | `const existing = await this.prisma.close.findMany({` |
| warning | contabilidad/contabilidad.service.ts | 1948 | findMany possibly unscoped | `const recipients = await this.prisma.user.findMany({` |
| warning | contabilidad/contabilidad.service.ts | 1986 | findMany possibly unscoped | `const previous = await this.prisma.close.findMany({` |
| warning | contabilidad/contabilidad.service.ts | 2555 | count possibly unscoped | `const correctionCount = await this.prisma.depositOrder.count({` |
| warning | contabilidad/contabilidad.service.ts | 2611 | findMany possibly unscoped | `return this.prisma.fiscalInvoice.findMany({` |
| warning | contabilidad/contabilidad.service.ts | 2694 | findMany possibly unscoped | `return this.prisma.payableService.findMany({` |
| warning | contabilidad/contabilidad.service.ts | 2830 | findMany possibly unscoped | `return this.prisma.payablePayment.findMany({` |
| warning | cotizaciones/cotizaciones.service.ts | 316 | findMany possibly unscoped | `const adminUsers = await this.prisma.user.findMany({` |
| warning | cotizaciones/cotizaciones.service.ts | 546 | findMany possibly unscoped | `const items = await this.prisma.cotizacion.findMany({` |
| warning | cotizaciones/cotizaciones.service.ts | 1012 | findMany possibly unscoped | `const quotes = await this.prisma.cotizacion.findMany({` |
| warning | cotizaciones/cotizaciones.service.ts | 1234 | findMany possibly unscoped | `products = await this.prisma.product.findMany({` |
| warning | cotizaciones/cotizaciones.service.ts | 1475 | findMany possibly unscoped | `const entries = await this.prisma.companyManualEntry.findMany({` |
| warning | cotizaciones/cotizaciones.service.ts | 1641 | count possibly unscoped | `const totalSales = await this.prisma.sale.count({` |
| warning | cotizaciones/cotizaciones.service.ts | 1661 | count possibly unscoped | `const totalClients = await this.prisma.client.count({` |
| warning | cotizaciones/cotizaciones.service.ts | 1681 | count possibly unscoped | `const totalQuotes = await this.prisma.cotizacion.count({` |
| warning | locations/locations.service.ts | 53 | findMany possibly unscoped | `return prismaAny.userLocation.findMany({` |
| warning | notifications/notifications.service.ts | 454 | findMany possibly unscoped | `const rows = await tx.notificationOutbox.findMany({` |
| warning | notifications/service-order-notification-jobs.processor.ts | 34 | findMany possibly unscoped | `const rows = await tx.serviceOrderNotificationJob.findMany({` |
| warning | notifications/service-order-notifications.listener.ts | 1334 | count possibly unscoped | `const count = await this.prisma.serviceOrderNotificationJob.count({` |
| warning | notifications/service-order-notifications.listener.ts | 1409 | count possibly unscoped | `return this.prisma.notificationOutbox.count({` |
| warning | notifications/service-order-notifications.listener.ts | 1454 | findMany possibly unscoped | `const users = await this.prisma.user.findMany({` |
| warning | payroll/payroll.service.ts | 40 | findMany possibly unscoped | `return this.prisma.payrollPeriod.findMany({` |
| warning | payroll/payroll.service.ts | 51 | count possibly unscoped | `const count = await this.prisma.payrollPeriod.count({` |
| warning | payroll/payroll.service.ts | 88 | findMany possibly unscoped | `const openPeriods = await this.prisma.payrollPeriod.findMany({` |
| warning | payroll/payroll.service.ts | 164 | findMany possibly unscoped | `return this.prisma.payrollEmployee.findMany({` |
| warning | payroll/payroll.service.ts | 307 | findMany possibly unscoped | `return this.prisma.payrollEntry.findMany({` |
| warning | payroll/payroll.service.ts | 501 | findMany possibly unscoped | `return this.prisma.payrollServiceCommissionRequest.findMany({` |
| warning | payroll/payroll.service.ts | 797 | findMany possibly unscoped | `return this.prisma.payrollEmployeePeriodStatus.findMany({` |
| warning | payroll/payroll.service.ts | 1200 | findMany possibly unscoped | `const direct = await this.prisma.payrollEmployee.findMany({` |
| warning | payroll/payroll.service.ts | 1208 | findMany possibly unscoped | `const fallback = await this.prisma.payrollEmployee.findMany({` |
| warning | payroll/payroll.service.ts | 1271 | findMany possibly unscoped | `const legacyMatches = await this.prisma.payrollEmployee.findMany({` |
| warning | payroll/payroll.service.ts | 1383 | aggregate possibly unscoped | `const aggregate = await this.prisma.sale.aggregate({` |
| warning | payroll/payroll.service.ts | 1431 | findMany possibly unscoped | `const users = await this.prisma.user.findMany({` |
| warning | payroll/payroll.service.ts | 1442 | findMany possibly unscoped | `const payrollUsers = await this.prisma.payrollEmployee.findMany({` |
| warning | products/products.service.ts | 170 | findMany possibly unscoped | `const candidates = await tx.product.findMany({` |
| warning | products/products.service.ts | 222 | count possibly unscoped | `tx.saleItem.count({ where: { productId } }),` |
| warning | products/products.service.ts | 223 | count possibly unscoped | `tx.cotizacionItem.count({ where: { productId } }),` |
| warning | products/products.service.ts | 224 | count possibly unscoped | `tx.purchaseOrderItem.count({ where: { productId } }),` |
| warning | products/products.service.ts | 225 | count possibly unscoped | `tx.websiteProductOverride.count({ where: { productId } }),` |
| warning | products/products.service.ts | 242 | findMany possibly unscoped | `const candidates = await tx.product.findMany({` |
| warning | products/products.service.ts | 502 | findMany possibly unscoped | `const products = await this.prisma.product.findMany({` |
| warning | products/products.service.ts | 509 | findMany possibly unscoped | `const products = await this.prisma.product.findMany({` |
| warning | purchases/purchases.service.ts | 58 | findMany possibly unscoped | `const rows = await this.prisma.supplier.findMany({` |
| warning | purchases/purchases.service.ts | 107 | findMany possibly unscoped | `return this.prisma.purchaseInvoice.findMany({` |
| warning | purchases/purchases.service.ts | 220 | findMany possibly unscoped | `return this.prisma.purchaseOrder.findMany({` |
| warning | purchases/purchases.service.ts | 525 | findMany possibly unscoped | `const refreshedItems = await tx.purchaseOrderItem.findMany({` |
| warning | purchases/purchases.service.ts | 549 | findMany possibly unscoped | `const products = await this.prisma.product.findMany({` |
| warning | purchases/purchases.service.ts | 734 | findMany possibly unscoped | `? await this.prisma.product.findMany({` |
| warning | purchases/purchases.service.ts | 843 | findMany possibly unscoped | `this.prisma.purchaseOrder.findMany({` |
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
| warning | users/users.service.ts | 744 | findMany possibly unscoped | `return this.prisma.user.findMany({` |
| warning | warranty-configs/warranty-configs.service.ts | 42 | findMany possibly unscoped | `const items = await this.prisma.warrantyProductConfig.findMany({` |
| warning | warranty-configs/warranty-configs.service.ts | 141 | findMany possibly unscoped | `const configs = await this.prisma.warrantyProductConfig.findMany({` |
| warning | work-scheduling/work-scheduling.service.ts | 148 | count possibly unscoped | `const count = await this.prisma.workCoverageRule.count();` |
| warning | work-scheduling/work-scheduling.service.ts | 172 | findMany possibly unscoped | `const existing = await this.prisma.workEmployeeConfig.findMany({` |
| warning | work-scheduling/work-scheduling.service.ts | 187 | findMany possibly unscoped | `const users = await this.prisma.user.findMany({` |
| warning | work-scheduling/work-scheduling.service.ts | 202 | findMany possibly unscoped | `const configs = await this.prisma.workEmployeeConfig.findMany({` |
| warning | work-scheduling/work-scheduling.service.ts | 319 | findMany possibly unscoped | `const profiles = await this.prisma.workScheduleProfile.findMany({` |
| warning | work-scheduling/work-scheduling.service.ts | 463 | findMany possibly unscoped | `const rules = await this.prisma.workCoverageRule.findMany({` |
| warning | work-scheduling/work-scheduling.service.ts | 517 | findMany possibly unscoped | `const list = await this.prisma.workScheduleException.findMany({` |
| warning | work-scheduling/work-scheduling.service.ts | 702 | findMany possibly unscoped | `const rules = await this.prisma.workCoverageRule.findMany();` |
| warning | work-scheduling/work-scheduling.service.ts | 712 | findMany possibly unscoped | `const users = await this.prisma.user.findMany({` |
| warning | work-scheduling/work-scheduling.service.ts | 720 | findMany possibly unscoped | `const configs = await this.prisma.workEmployeeConfig.findMany({` |
| warning | work-scheduling/work-scheduling.service.ts | 947 | findMany possibly unscoped | `const assignments = await this.prisma.workDayAssignment.findMany({` |
| warning | work-scheduling/work-scheduling.service.ts | 954 | findMany possibly unscoped | `const users = await this.prisma.user.findMany({` |
| warning | work-scheduling/work-scheduling.service.ts | 960 | findMany possibly unscoped | `const configs = await this.prisma.workEmployeeConfig.findMany({` |
| warning | work-scheduling/work-scheduling.service.ts | 1026 | findMany possibly unscoped | `const assignments = await this.prisma.workDayAssignment.findMany({` |
| warning | work-scheduling/work-scheduling.service.ts | 1044 | findMany possibly unscoped | `const users = await this.prisma.user.findMany({` |
| warning | work-scheduling/work-scheduling.service.ts | 1090 | findMany possibly unscoped | `const profileDays = await this.prisma.workScheduleProfileDay.findMany({` |
| warning | work-scheduling/work-scheduling.service.ts | 1098 | findMany possibly unscoped | `const exceptions = await this.prisma.workScheduleException.findMany({` |
| warning | work-scheduling/work-scheduling.service.ts | 1208 | findMany possibly unscoped | `? await tx.workDayAssignment.findMany({` |
| warning | work-scheduling/work-scheduling.service.ts | 1331 | findMany possibly unscoped | `const [fromA, toA] = await this.prisma.workDayAssignment.findMany({` |
| warning | work-scheduling/work-scheduling.service.ts | 1430 | findMany possibly unscoped | `const list = await this.prisma.workDayAssignment.findMany({` |
| warning | work-scheduling/work-scheduling.service.ts | 1577 | findMany possibly unscoped | `const logs = await this.prisma.workScheduleAuditLog.findMany({` |
| warning | work-scheduling/work-scheduling.service.ts | 1617 | findMany possibly unscoped | `const users = await this.prisma.user.findMany({ where: { id: { in: ids } }, select: { id: true, nombreCompleto: true, role: true } });` |
| warning | work-scheduling/work-scheduling.service.ts | 1638 | findMany possibly unscoped | `const weeks = await this.prisma.workWeekSchedule.findMany({` |
