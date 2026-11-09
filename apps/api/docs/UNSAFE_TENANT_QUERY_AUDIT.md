# Unsafe Tenant Query Audit

Generated at: 2026-11-09T03:01:17.786Z

Errors: 0
Warnings: 291

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
| warning | app-updates/app-updates.service.ts | 150 | findMany possibly unscoped | `const releases = await this.prisma.appRelease.findMany({` |
| warning | app-updates/app-updates.service.ts | 303 | findMany possibly unscoped | `const releases = await this.prisma.appRelease.findMany({` |
| warning | app-updates/app-updates.service.ts | 404 | findMany possibly unscoped | `const releases = await this.prisma.appRelease.findMany({` |
| warning | backups/backup-extractor.ts | 121 | findMany possibly unscoped | `tx.user.findMany({` |
| warning | backups/backups.service.ts | 89 | findMany possibly unscoped | `}).backupRecord.findMany({` |
| warning | backups/backups.service.ts | 236 | findMany possibly unscoped | `const companies: Array<{ id: string }> = await this.prisma.company.findMany({` |
| warning | backups/backups.service.ts | 280 | findMany possibly unscoped | `}).backupRecord.findMany({` |
| warning | cash/cash.service.ts | 103 | findMany possibly unscoped | `this.prisma.cashSession.findMany({` |
| warning | cash/cash.service.ts | 692 | findMany possibly unscoped | `return this.prisma.cashMovement.findMany({` |
| warning | cash/cash.service.ts | 739 | findMany possibly unscoped | `const rows = await this.prisma.cashMovement.findMany({` |
| warning | cash/cash.service.ts | 818 | findMany possibly unscoped | `const rows = await this.prisma.cashSession.findMany({` |
| warning | cash/cash.service.ts | 876 | findMany possibly unscoped | `this.prisma.cashMovement.findMany({` |
| warning | cash/cash.service.ts | 995 | aggregate possibly unscoped | `this.prisma.cashSession.aggregate({` |
| warning | cash/cash.service.ts | 1000 | count possibly unscoped | `this.prisma.cashSession.count({` |
| warning | cash/cash.service.ts | 1037 | findMany possibly unscoped | `const rows = await this.prisma.cashSession.findMany({` |
| warning | cash/cash.service.ts | 1283 | aggregate possibly unscoped | `const totals = await tx.cashSession.aggregate({` |
| warning | cash/cash.service.ts | 1361 | aggregate possibly unscoped | `this.prisma.saleCreditPayment.aggregate({` |
| warning | cash/cash.service.ts | 1371 | aggregate possibly unscoped | `this.prisma.saleCreditPayment.aggregate({` |
| warning | cash/cash.service.ts | 1581 | findMany possibly unscoped | `const sales = await this.prisma.sale.findMany({` |
| warning | cash/cash.service.ts | 1609 | findMany possibly unscoped | `this.prisma.saleCreditPayment.findMany({` |
| warning | clients/clients.service.ts | 468 | findMany possibly unscoped | `this.prisma.client.findMany({` |
| warning | clients/clients.service.ts | 483 | count possibly unscoped | `this.prisma.client.count({ where }),` |
| warning | clients/clients.service.ts | 618 | findMany possibly unscoped | `const clients = await this.prisma.client.findMany({` |
| warning | clients/clients.service.ts | 640 | findMany possibly unscoped | `const quotations = await this.prisma.cotizacion.findMany({` |
| warning | clients/clients.service.ts | 707 | aggregate possibly unscoped | `this.prisma.sale.aggregate({` |
| warning | clients/clients.service.ts | 713 | aggregate possibly unscoped | `this.prisma.sale.aggregate({` |
| warning | clients/clients.service.ts | 728 | aggregate possibly unscoped | `this.prisma.serviceOrder.aggregate({` |
| warning | clients/clients.service.ts | 733 | aggregate possibly unscoped | `this.prisma.service.aggregate({` |
| warning | clients/clients.service.ts | 739 | aggregate possibly unscoped | `this.prisma.serviceEvidence.aggregate({` |
| warning | clients/clients.service.ts | 744 | aggregate possibly unscoped | `this.prisma.serviceReport.aggregate({` |
| warning | clients/clients.service.ts | 749 | aggregate possibly unscoped | `this.prisma.cotizacion.aggregate({` |
| warning | contabilidad/contabilidad.service.ts | 269 | findMany possibly unscoped | `return await this.prisma.depositOrder.findMany({` |
| warning | contabilidad/contabilidad.service.ts | 997 | findMany possibly unscoped | `const rows = await this.prisma.close.findMany({` |
| warning | contabilidad/contabilidad.service.ts | 1053 | aggregate possibly unscoped | `const closeTotals = await this.prisma.close.aggregate({` |
| warning | contabilidad/contabilidad.service.ts | 1122 | aggregate possibly unscoped | `? await this.prisma.depositOrder.aggregate({` |
| warning | contabilidad/contabilidad.service.ts | 1458 | findMany possibly unscoped | `const existing = await this.prisma.close.findMany({` |
| warning | contabilidad/contabilidad.service.ts | 2070 | findMany possibly unscoped | `const recipients = await this.prisma.user.findMany({` |
| warning | contabilidad/contabilidad.service.ts | 2108 | findMany possibly unscoped | `const previous = await this.prisma.close.findMany({` |
| warning | contabilidad/contabilidad.service.ts | 2305 | findMany possibly unscoped | `return this.prisma.depositBank.findMany({` |
| warning | contabilidad/contabilidad.service.ts | 2873 | count possibly unscoped | `const correctionCount = await this.prisma.depositOrder.count({` |
| warning | contabilidad/contabilidad.service.ts | 2936 | findMany possibly unscoped | `const rows = await this.prisma.fiscalInvoice.findMany({` |
| warning | contabilidad/contabilidad.service.ts | 3029 | findMany possibly unscoped | `const rows = await this.prisma.payableService.findMany({` |
| warning | contabilidad/contabilidad.service.ts | 3178 | findMany possibly unscoped | `const rows = await this.prisma.payablePayment.findMany({` |
| warning | cotizaciones/cotizaciones.service.ts | 341 | findMany possibly unscoped | `const adminUsers = await this.prisma.user.findMany({` |
| warning | cotizaciones/cotizaciones.service.ts | 720 | findMany possibly unscoped | `this.prisma.cotizacion.findMany({` |
| warning | cotizaciones/cotizaciones.service.ts | 727 | count possibly unscoped | `this.prisma.cotizacion.count({ where }),` |
| warning | cotizaciones/cotizaciones.service.ts | 1380 | findMany possibly unscoped | `const quotes = await this.prisma.cotizacion.findMany({` |
| warning | cotizaciones/cotizaciones.service.ts | 1613 | findMany possibly unscoped | `products = await this.prisma.product.findMany({` |
| warning | cotizaciones/cotizaciones.service.ts | 1975 | findMany possibly unscoped | `const entries = await this.prisma.companyManualEntry.findMany({` |
| warning | cotizaciones/cotizaciones.service.ts | 2142 | count possibly unscoped | `const totalSales = await this.prisma.sale.count({` |
| warning | cotizaciones/cotizaciones.service.ts | 2162 | count possibly unscoped | `const totalClients = await this.prisma.client.count({` |
| warning | cotizaciones/cotizaciones.service.ts | 2182 | count possibly unscoped | `const totalQuotes = await this.prisma.cotizacion.count({` |
| warning | ecf/certification/ecf-certification-authorization.service.ts | 105 | findMany possibly unscoped | `this.prisma.ecfAuditLog.findMany({` |
| warning | ecf/dgii/certification/ecf-certification-recovery.service.ts | 110 | findMany possibly unscoped | `const rows = await this.prisma.ecfCertificationAttempt.findMany({` |
| warning | ecf/dgii/ecf-dgii-activation.service.ts | 412 | findMany possibly unscoped | `const existing = await this.prisma.ecfOnboardingStep.findMany({` |
| warning | ecf/dgii/ecf-dgii-activation.service.ts | 440 | findMany possibly unscoped | `const rows = await this.prisma.ecfOnboardingStep.findMany({` |
| warning | ecf/dgii/ecf-dgii-application.service.ts | 219 | findMany possibly unscoped | `const evidence = await tx.ecfEvidence.findMany({` |
| warning | ecf/dgii/ecf-dgii-application.service.ts | 361 | findMany possibly unscoped | `const rows = await this.prisma.ecfDgiiApplicationSnapshot.findMany({` |
| warning | ecf/dgii/ecf-dgii-habilitation.service.ts | 84 | findMany possibly unscoped | `this.prisma.ecfOnboardingStep.findMany({` |
| warning | ecf/dgii/ecf-dgii-habilitation.service.ts | 99 | findMany possibly unscoped | `this.prisma.ecfEvidence.findMany({` |
| warning | ecf/dgii/ecf-dgii-habilitation.service.ts | 246 | findMany possibly unscoped | `const rows = await this.prisma.ecfAuditLog.findMany({` |
| warning | ecf/dgii/ecf-dgii-habilitation.service.ts | 286 | findMany possibly unscoped | `const rows = await this.prisma.ecfEvidence.findMany({` |
| warning | ecf/dgii/ecf-support-grant.service.ts | 105 | findMany possibly unscoped | `const stale = await tx.ecfSupportGrant.findMany({` |
| warning | ecf/dgii/ecf-support-grant.service.ts | 166 | findMany possibly unscoped | `const rows = await this.prisma.ecfSupportGrant.findMany({` |
| warning | ecf/dgii/ecf-support-grant.service.ts | 247 | findMany possibly unscoped | `const rows = await this.prisma.ecfSupportGrant.findMany({` |
| warning | ecf/documents/ecf-dgii-authorized-sequences.service.ts | 30 | findMany possibly unscoped | `const rows = await this.prisma.ecfDgiiAuthorizedSequence.findMany({` |
| warning | ecf/documents/ecf-document-query.service.ts | 131 | count possibly unscoped | `this.prisma.ecfElectronicDocument.count({ where }),` |
| warning | ecf/documents/ecf-document-query.service.ts | 132 | findMany possibly unscoped | `this.prisma.ecfElectronicDocument.findMany({` |
| warning | ecf/documents/ecf-document-query.service.ts | 253 | findMany possibly unscoped | `const candidates = await this.prisma.ecfElectronicDocument.findMany({` |
| warning | ecf/documents/ecf-line-classification.service.ts | 184 | findMany possibly unscoped | `const rows = await this.prisma.ecfElectronicDocument.findMany({` |
| warning | ecf/documents/ecf-line-classification.service.ts | 202 | findMany possibly unscoped | `const rows = await this.prisma.ecfLineClassification.findMany({` |
| warning | ecf/documents/ecf-sales-without-document.service.ts | 123 | findMany possibly unscoped | `const rows = await this.prisma.ecfSaleWithoutDocument.findMany({` |
| warning | ecf/ecf.service.ts | 80 | findMany possibly unscoped | `this.prisma.ecfOnboardingStep.findMany({` |
| warning | ecf/ecf.service.ts | 84 | findMany possibly unscoped | `this.prisma.ecfAuditLog.findMany({` |
| warning | ecf/ecf.service.ts | 200 | findMany possibly unscoped | `return this.prisma.ecfAuditLog.findMany({` |
| warning | ecf/ecf.service.ts | 439 | findMany possibly unscoped | `const steps = await tx.ecfOnboardingStep.findMany({` |
| warning | ecf/ecf.service.ts | 463 | count possibly unscoped | `const completeWebhookEvents = await tx.ecfDosaWebhookEvent.count({` |
| warning | ecf/platform/ecf-platform.controller.ts | 115 | findMany possibly unscoped | `this.prisma.ecfDgiiHabilitation.findMany({` |
| warning | ecf/platform/ecf-platform.controller.ts | 132 | count possibly unscoped | `this.prisma.ecfDgiiHabilitation.count({ where }),` |
| warning | ecf/platform/ecf-platform.controller.ts | 188 | findMany possibly unscoped | `this.prisma.ecfEvidence.findMany({` |
| warning | ecf/portal/ecf-certification-portal.service.ts | 265 | findMany possibly unscoped | `const audits = await this.prisma.ecfAuditLog.findMany({` |
| warning | ecf/portal/ecf-portal-enrollment.service.ts | 251 | findMany possibly unscoped | `return this.prisma.ecfPortalEnrollment.findMany({` |
| warning | ecf/pos/ecf-sale-fiscal.adapter.ts | 282 | findMany possibly unscoped | `const rows = await this.prisma.ecfLineClassification.findMany({` |
| warning | ecf/provider/dosa/dosa-certification-intent.controller.ts | 654 | findMany possibly unscoped | `const audits = await tx.ecfAuditLog.findMany({` |
| warning | ecf/provider/dosa/dosa-certification-intent.controller.ts | 819 | findMany possibly unscoped | `return this.prisma.ecfAuditLog.findMany({` |
| warning | ecf/provider/dosa/dosa-emission-dispatch.service.ts | 234 | findMany possibly unscoped | `const candidates = await this.prisma.ecfElectronicDocument.findMany({` |
| warning | ecf/provider/dosa/dosa-emission-dispatch.service.ts | 253 | findMany possibly unscoped | `const attempted = await this.prisma.ecfElectronicDocumentAttempt.findMany({` |
| warning | ecf/provider/dosa/dosa-incident.service.ts | 228 | findMany possibly unscoped | `this.prisma.ecfDosaIncident.findMany({` |
| warning | ecf/provider/dosa/dosa-incident.service.ts | 252 | count possibly unscoped | `this.prisma.ecfDosaIncident.count({ where }),` |
| warning | ecf/provider/dosa/dosa-incident.service.ts | 437 | findMany possibly unscoped | `const rows = await this.prisma.ecfDosaIncident.findMany({` |
| warning | ecf/provider/dosa/dosa-incident.service.ts | 447 | findMany possibly unscoped | `const rows = await this.prisma.ecfDosaIncident.findMany({` |
| warning | ecf/sandbox/e32-reconciliation-executor.ts | 155 | count possibly unscoped | `const postAttempts = await tx.ecfElectronicDocumentAttempt.count({` |
| warning | ecf/sandbox/e32-reconciliation-executor.ts | 158 | count possibly unscoped | `const dbQueryAttempts = await tx.ecfElectronicDocumentAttempt.count({` |
| warning | ecf/sandbox/e32-reconciliation-executor.ts | 225 | count possibly unscoped | `const conflicts = await tx.ecfElectronicDocument.count({` |
| warning | ecf/sandbox/e32-sandbox.cli.ts | 57 | count possibly unscoped | `const occupied = facts.schema ? await prisma.ecfSandboxE32Trial.count({where:{slot:"FIRST_E32_SANDBOX"}}) : 1;` |
| warning | guardian/guardian.admin.controller.ts | 137 | findMany possibly unscoped | `await this.prisma.guardianIncident.findMany({` |
| warning | guardian/guardian.admin.controller.ts | 156 | count possibly unscoped | `this.prisma.guardianIncident.count({` |
| warning | guardian/guardian.admin.controller.ts | 159 | count possibly unscoped | `this.prisma.guardianIncident.count({` |
| warning | guardian/guardian.admin.controller.ts | 162 | count possibly unscoped | `this.prisma.guardianAlert.count({` |
| warning | guardian/guardian.admin.controller.ts | 165 | count possibly unscoped | `this.prisma.guardianAlert.count({` |
| warning | guardian/guardian.alert.service.ts | 394 | findMany possibly unscoped | `const candidates = await this.prisma.guardianAlert.findMany({` |
| warning | guardian/guardian.alert.service.ts | 411 | findMany possibly unscoped | `return this.prisma.guardianAlert.findMany({ where: { id: { in: claimed } } });` |
| warning | guardian/guardian.alert.service.ts | 449 | count possibly unscoped | `return this.prisma.guardianAlert.count({` |
| warning | guardian/guardian.alert.service.ts | 512 | count possibly unscoped | `const relatedCount = await this.prisma.guardianIncident.count({` |
| warning | guardian/guardian.auto-enrollment.service.ts | 224 | count possibly unscoped | `const active = await this.store.guardianMachineCredential.count({` |
| warning | guardian/guardian.auto-enrollment.service.ts | 241 | count possibly unscoped | `const recent = await this.store.guardianEnrollmentCode.count({` |
| warning | guardian/guardian.auto-enrollment.service.ts | 341 | count possibly unscoped | `activeInstallations = await this.store.guardianMachineCredential.count({` |
| warning | guardian/guardian.diagnosis.service.ts | 56 | findMany possibly unscoped | `const candidates = await this.prisma.guardianIncident.findMany({` |
| warning | guardian/guardian.diagnosis.service.ts | 76 | findMany possibly unscoped | `return this.prisma.guardianIncident.findMany({ where: { id: { in: claimed } } });` |
| warning | guardian/guardian.diagnosis.service.ts | 304 | count possibly unscoped | `const running = await tx.guardianDiagnosis.count({` |
| warning | guardian/guardian.diagnosis.service.ts | 349 | findMany possibly unscoped | `const similarIncidents = await this.prisma.guardianIncident.findMany({` |
| warning | guardian/guardian.diagnosis.service.ts | 388 | findMany possibly unscoped | `const versionTimeline = await this.prisma.appRelease.findMany({` |
| warning | guardian/guardian.incidents.service.ts | 47 | findMany possibly unscoped | `const rows = await this.prisma.guardianIncident.findMany({` |
| warning | guardian/guardian.incidents.service.ts | 112 | count possibly unscoped | `this.prisma.guardianIncident.count({` |
| warning | guardian/guardian.incidents.service.ts | 115 | count possibly unscoped | `this.prisma.guardianIncidentGroup.count({` |
| warning | guardian/guardian.ingest.service.ts | 327 | findMany possibly unscoped | `const companies = await this.prisma.guardianIncident.findMany({` |
| warning | guardian/guardian.platform.service.ts | 138 | findMany possibly unscoped | `const companies = await this.prisma.company.findMany({` |
| warning | guardian/guardian.platform.service.ts | 178 | count possibly unscoped | `this.prisma.guardianIncident.count(),` |
| warning | guardian/guardian.platform.service.ts | 193 | count possibly unscoped | `this.prisma.guardianIncident.count({` |
| warning | guardian/guardian.platform.service.ts | 200 | count possibly unscoped | `this.prisma.guardianAlert.count({ where: { state: { in: ['PENDING', 'SENDING', 'QUEUED'] } } }),` |
| warning | guardian/guardian.platform.service.ts | 233 | findMany possibly unscoped | `const rows = await this.prisma.guardianIncident.findMany({` |
| warning | guardian/guardian.platform.service.ts | 378 | count possibly unscoped | `this.prisma.guardianAlert.count({ where: { state: { in: ['PENDING', 'SENDING', 'QUEUED'] } } }),` |
| warning | guardian/guardian.platform.service.ts | 379 | count possibly unscoped | `this.prisma.guardianAlert.count({ where: { state: 'FAILED_PERMANENT' } }),` |
| warning | guardian/guardian.platform.service.ts | 380 | count possibly unscoped | `this.prisma.guardianIncident.count({` |
| warning | guardian/guardian.platform.service.ts | 434 | findMany possibly unscoped | `const rows = await this.prisma.guardianWorkerHeartbeat.findMany({` |
| warning | guardian/guardian.quota.service.ts | 66 | count possibly unscoped | `this.prisma.guardianIncident.count({` |
| warning | guardian/guardian.quota.service.ts | 69 | count possibly unscoped | `this.prisma.guardianIncident.count({` |
| warning | guardian/guardian.quota.service.ts | 84 | count possibly unscoped | `const deviceCount = await this.prisma.guardianIncident.count({` |
| warning | guardian/guardian.retention.service.ts | 82 | findMany possibly unscoped | `const rows = await this.prisma.guardianIncident.findMany({` |
| warning | guardian/guardian.retention.service.ts | 150 | count possibly unscoped | `const expiredIncidents = await this.prisma.guardianIncident.count({ where: expiredWhere });` |
| warning | guardian/guardian.retention.service.ts | 151 | count possibly unscoped | `const keptForInvestigation = await this.prisma.guardianIncident.count({` |
| warning | guardian/guardian.retention.service.ts | 168 | findMany possibly unscoped | `const candidates = await this.prisma.guardianIncident.findMany({` |
| warning | inventory/inventory-mutation.service.ts | 190 | findMany possibly unscoped | `const products = await tx.product.findMany({` |
| warning | inventory/inventory-reporting.service.ts | 71 | count possibly unscoped | `this.prisma.inventoryMovement.count({ where }),` |
| warning | inventory/inventory-reporting.service.ts | 72 | findMany possibly unscoped | `this.prisma.inventoryMovement.findMany({` |
| warning | inventory/inventory-reporting.service.ts | 119 | findMany possibly unscoped | `this.prisma.warehouse.findMany({` |
| warning | inventory/inventory-reporting.service.ts | 130 | findMany possibly unscoped | `this.prisma.product.findMany({` |
| warning | inventory/inventory-reporting.service.ts | 218 | findMany possibly unscoped | `const rows = await this.prisma.product.findMany({` |
| warning | inventory/inventory-reporting.service.ts | 379 | findMany possibly unscoped | `this.prisma.warehouseTransfer.findMany({` |
| warning | inventory/inventory-reporting.service.ts | 387 | findMany possibly unscoped | `this.prisma.sale.findMany({` |
| warning | inventory/inventory-reporting.service.ts | 391 | findMany possibly unscoped | `this.prisma.purchaseReceipt.findMany({` |
| warning | inventory/zero-config-inventory.ts | 229 | findMany possibly unscoped | `const products = await tx.product.findMany({` |
| warning | inventory/zero-config-inventory.ts | 251 | findMany possibly unscoped | `const existingStocks = await tx.warehouseStock.findMany({` |
| warning | inventory/zero-config-inventory.ts | 293 | count possibly unscoped | `const warehouseStockCount = await tx.warehouseStock.count({` |
| warning | inventory/zero-config-inventory.ts | 335 | findMany possibly unscoped | `const companies = await prisma.company.findMany({` |
| warning | license/license.service.ts | 133 | count possibly unscoped | `this.prisma.company.count({ where }),` |
| warning | license/license.service.ts | 134 | findMany possibly unscoped | `this.prisma.company.findMany({` |
| warning | license/license.service.ts | 150 | findMany possibly unscoped | `const auditLogs = await this.prisma.companyLicenseAuditLog.findMany({` |
| warning | locations/locations.service.ts | 53 | findMany possibly unscoped | `return prismaAny.userLocation.findMany({` |
| warning | notifications/notifications.service.ts | 513 | findMany possibly unscoped | `const candidates = await this.prisma.notificationOutbox.findMany({` |
| warning | notifications/notifications.service.ts | 537 | findMany possibly unscoped | `return this.prisma.notificationOutbox.findMany({` |
| warning | notifications/service-order-notification-jobs.processor.ts | 34 | findMany possibly unscoped | `const rows = await tx.serviceOrderNotificationJob.findMany({` |
| warning | notifications/service-order-notifications.listener.ts | 1334 | count possibly unscoped | `const count = await this.prisma.serviceOrderNotificationJob.count({` |
| warning | notifications/service-order-notifications.listener.ts | 1409 | count possibly unscoped | `return this.prisma.notificationOutbox.count({` |
| warning | notifications/service-order-notifications.listener.ts | 1454 | findMany possibly unscoped | `const users = await this.prisma.user.findMany({` |
| warning | onboarding/onboarding.service.ts | 62 | count possibly unscoped | `this.prisma.product.count({` |
| warning | payroll/payroll.service.ts | 65 | findMany possibly unscoped | `return this.prisma.payrollPeriod.findMany({` |
| warning | payroll/payroll.service.ts | 77 | count possibly unscoped | `const count = await this.prisma.payrollPeriod.count({` |
| warning | payroll/payroll.service.ts | 117 | findMany possibly unscoped | `const openPeriods = await this.prisma.payrollPeriod.findMany({` |
| warning | payroll/payroll.service.ts | 197 | findMany possibly unscoped | `return this.prisma.payrollEmployee.findMany({` |
| warning | payroll/payroll.service.ts | 345 | findMany possibly unscoped | `return this.prisma.payrollEntry.findMany({` |
| warning | payroll/payroll.service.ts | 542 | findMany possibly unscoped | `return this.prisma.payrollServiceCommissionRequest.findMany({` |
| warning | payroll/payroll.service.ts | 843 | findMany possibly unscoped | `return this.prisma.payrollEmployeePeriodStatus.findMany({` |
| warning | payroll/payroll.service.ts | 1249 | findMany possibly unscoped | `const direct = await this.prisma.payrollEmployee.findMany({` |
| warning | payroll/payroll.service.ts | 1258 | findMany possibly unscoped | `const fallback = await this.prisma.payrollEmployee.findMany({` |
| warning | payroll/payroll.service.ts | 1322 | findMany possibly unscoped | `const legacyMatches = await this.prisma.payrollEmployee.findMany({` |
| warning | payroll/payroll.service.ts | 1434 | aggregate possibly unscoped | `const aggregate = await this.prisma.sale.aggregate({` |
| warning | payroll/payroll.service.ts | 1482 | findMany possibly unscoped | `const users = await this.prisma.user.findMany({` |
| warning | payroll/payroll.service.ts | 1493 | findMany possibly unscoped | `const payrollUsers = await this.prisma.payrollEmployee.findMany({` |
| warning | price-lists/price-lists.service.ts | 28 | findMany possibly unscoped | `return this.prisma.priceList.findMany({` |
| warning | price-lists/price-lists.service.ts | 297 | findMany possibly unscoped | `this.prisma.product.findMany({` |
| warning | price-lists/price-lists.service.ts | 301 | findMany possibly unscoped | `this.prisma.priceListProductRule.findMany({` |
| warning | products/products.service.ts | 145 | findMany possibly unscoped | `const activeWarehouses = await tx.warehouse.findMany({` |
| warning | products/products.service.ts | 342 | count possibly unscoped | `tx.warehouseStock.count({` |
| warning | products/products.service.ts | 351 | count possibly unscoped | `tx.purchaseOrderItem.count({` |
| warning | products/products.service.ts | 481 | findMany possibly unscoped | `const rows = await this.prisma.unitOfMeasure.findMany({` |
| warning | products/products.service.ts | 599 | findMany possibly unscoped | `const candidates = await tx.product.findMany({` |
| warning | products/products.service.ts | 653 | count possibly unscoped | `tx.saleItem.count({ where: { productId } }),` |
| warning | products/products.service.ts | 654 | count possibly unscoped | `tx.cotizacionItem.count({ where: { productId } }),` |
| warning | products/products.service.ts | 655 | count possibly unscoped | `tx.purchaseOrderItem.count({ where: { productId } }),` |
| warning | products/products.service.ts | 656 | count possibly unscoped | `tx.websiteProductOverride.count({ where: { productId } }),` |
| warning | products/products.service.ts | 762 | count possibly unscoped | `tx.saleItem.count({` |
| warning | products/products.service.ts | 765 | count possibly unscoped | `tx.cotizacionItem.count({` |
| warning | products/products.service.ts | 768 | count possibly unscoped | `tx.purchaseOrderItem.count({` |
| warning | products/products.service.ts | 771 | count possibly unscoped | `tx.purchaseReceiptItem.count({` |
| warning | products/products.service.ts | 807 | findMany possibly unscoped | `const candidates = await tx.product.findMany({` |
| warning | products/products.service.ts | 1401 | findMany possibly unscoped | `this.prisma.product.findMany({` |
| warning | products/products.service.ts | 1409 | count possibly unscoped | `? this.prisma.product.count({ where })` |
| warning | products/products.service.ts | 1421 | findMany possibly unscoped | `this.prisma.product.findMany({` |
| warning | products/products.service.ts | 1429 | count possibly unscoped | `? this.prisma.product.count({ where: legacyWhere })` |
| warning | purchases/purchases.service.ts | 141 | findMany possibly unscoped | `const activeWarehouses = await tx.warehouse.findMany({` |
| warning | purchases/purchases.service.ts | 186 | findMany possibly unscoped | `const rows = await this.prisma.supplier.findMany({` |
| warning | purchases/purchases.service.ts | 250 | findMany possibly unscoped | `const rows = await this.prisma.purchaseInvoice.findMany({` |
| warning | purchases/purchases.service.ts | 410 | findMany possibly unscoped | `const rows = await this.prisma.purchaseOrder.findMany({` |
| warning | purchases/purchases.service.ts | 914 | findMany possibly unscoped | `const refreshedItems = await tx.purchaseOrderItem.findMany({` |
| warning | purchases/purchases.service.ts | 980 | findMany possibly unscoped | `const products = await this.prisma.product.findMany({` |
| warning | purchases/purchases.service.ts | 1174 | findMany possibly unscoped | `? await this.prisma.product.findMany({` |
| warning | purchases/purchases.service.ts | 1197 | findMany possibly unscoped | `? await this.prisma.supplier.findMany({` |
| warning | purchases/purchases.service.ts | 1390 | findMany possibly unscoped | `this.prisma.purchaseOrder.findMany({` |
| warning | reports/reports.service.ts | 175 | findMany possibly unscoped | `this.prisma.sale.findMany({` |
| warning | reports/reports.service.ts | 188 | findMany possibly unscoped | `this.prisma.sale.findMany({` |
| warning | reports/reports.service.ts | 201 | findMany possibly unscoped | `this.prisma.sale.findMany({` |
| warning | reports/reports.service.ts | 220 | findMany possibly unscoped | `this.prisma.sale.findMany({` |
| warning | reports/reports.service.ts | 1381 | findMany possibly unscoped | `const rows = await delegate.saleCreditPayment.findMany({` |
| warning | reports/reports.service.ts | 1805 | findMany possibly unscoped | `const products = await this.prisma.product.findMany({` |
| warning | sales/sale-reconciliation-obligation.service.ts | 406 | findMany possibly unscoped | `const rows = await this.prisma.saleReconciliationObligation.findMany({` |
| warning | sales/sale-reconciliation-obligation.service.ts | 431 | findMany possibly unscoped | `await this.prisma.saleReconciliationDeclarationEvent.findMany({` |
| warning | sales/sales.service.ts | 471 | count possibly unscoped | `return this.prisma.sale.count({ where });` |
| warning | sales/sales.service.ts | 473 | findMany possibly unscoped | `const rows = await this.prisma.sale.findMany({` |
| warning | sales/sales.service.ts | 620 | findMany possibly unscoped | `return await this.prisma.sale.findMany({` |
| warning | sales/sales.service.ts | 629 | findMany possibly unscoped | `return this.prisma.sale.findMany({` |
| warning | sales/sales.service.ts | 755 | findMany possibly unscoped | `const refundItems = await tx.saleItem.findMany({` |
| warning | sales/sales.service.ts | 1019 | findMany possibly unscoped | `const rows = await this.prisma.sale.findMany({` |
| warning | sales/sales.service.ts | 1313 | aggregate possibly unscoped | `this.prisma.sale.aggregate({` |
| warning | sales/sales.service.ts | 1322 | aggregate possibly unscoped | `this.prisma.sale.aggregate({` |
| warning | sales/sales.service.ts | 1332 | aggregate possibly unscoped | `? this.prisma.sale.aggregate({` |
| warning | sales/sales.service.ts | 1497 | findMany possibly unscoped | `? await this.prisma.user.findMany({` |
| warning | sales/sales.service.ts | 1654 | findMany possibly unscoped | `products = await this.prisma.product.findMany({` |
| warning | sales/sales.service.ts | 2277 | findMany possibly unscoped | `? await this.prisma.product.findMany({` |
| warning | sales/sales.service.ts | 2734 | findMany possibly unscoped | `const originalItems = await this.prisma.saleItem.findMany({` |
| warning | sales/sales.service.ts | 2746 | findMany possibly unscoped | `const refundedItems = await this.prisma.saleItem.findMany({` |
| warning | sales/sales.service.ts | 2775 | findMany possibly unscoped | `const thisRefundItems = await this.prisma.saleItem.findMany({` |
| warning | service-orders/service-orders.service.ts | 72 | findMany possibly unscoped | `const rows = await this.prisma.serviceOrder.findMany({` |
| warning | service-orders/service-orders.service.ts | 94 | findMany possibly unscoped | `const rows = await this.prisma.serviceOrder.findMany({` |
| warning | settings/settings.service.ts | 397 | findMany possibly unscoped | `const distributedRows = await tx.warehouseStock.findMany({` |
| warning | tax/tax.service.ts | 30 | findMany possibly unscoped | `return this.prisma.tax.findMany({` |
| warning | terminals/terminal-resolution.service.ts | 54 | findMany possibly unscoped | `const matches = await tx.terminal.findMany({` |
| warning | terminals/terminal-resolution.service.ts | 89 | findMany possibly unscoped | `const activeTerminals = await tx.terminal.findMany({` |
| warning | usage-telemetry/usage-telemetry.service.ts | 100 | findMany possibly unscoped | `const companies = await this.prisma.company.findMany({` |
| warning | usage-telemetry/usage-telemetry.service.ts | 325 | count possibly unscoped | `this.prisma.telemetryOutbox.count({ where: { status: 'PENDING' } }),` |
| warning | usage-telemetry/usage-telemetry.service.ts | 326 | count possibly unscoped | `this.prisma.telemetryOutbox.count({ where: { status: 'FAILED' } }),` |
| warning | usage-telemetry/usage-telemetry.service.ts | 398 | count possibly unscoped | `this.prisma.authSession.count({` |
| warning | usage-telemetry/usage-telemetry.service.ts | 401 | count possibly unscoped | `this.prisma.user.count({` |
| warning | usage-telemetry/usage-telemetry.service.ts | 414 | count possibly unscoped | `this.prisma.sale.count({ where: this.saleWhere(company.id, todayStart) }),` |
| warning | usage-telemetry/usage-telemetry.service.ts | 415 | count possibly unscoped | `this.prisma.sale.count({ where: this.saleWhere(company.id, sevenDaysAgo) }),` |
| warning | usage-telemetry/usage-telemetry.service.ts | 416 | count possibly unscoped | `this.prisma.sale.count({ where: this.saleWhere(company.id, monthStart) }),` |
| warning | usage-telemetry/usage-telemetry.service.ts | 417 | count possibly unscoped | `this.prisma.sale.count({ where: this.saleWhere(company.id) }),` |
| warning | usage-telemetry/usage-telemetry.service.ts | 423 | aggregate possibly unscoped | `this.prisma.sale.aggregate({ where: this.saleWhere(company.id, todayStart), _sum: { totalSold: true } }),` |
| warning | usage-telemetry/usage-telemetry.service.ts | 424 | aggregate possibly unscoped | `this.prisma.sale.aggregate({ where: this.saleWhere(company.id, monthStart), _sum: { totalSold: true } }),` |
| warning | usage-telemetry/usage-telemetry.service.ts | 438 | count possibly unscoped | `this.prisma.serviceOrder.count({` |
| warning | users/users.service.ts | 271 | count possibly unscoped | `return this.prisma.user.count({ where });` |
| warning | warehouses/warehouses.service.ts | 48 | findMany possibly unscoped | `const rows = await this.prisma.warehouse.findMany({` |
| warning | warehouses/warehouses.service.ts | 77 | findMany possibly unscoped | `const rows = await this.prisma.terminal.findMany({` |
| warning | warehouses/warehouses.service.ts | 192 | count possibly unscoped | `const nonZero = await tx.warehouseStock.count({` |
| warning | warehouses/warehouses.service.ts | 204 | count possibly unscoped | `const linkedTerminals = await tx.terminal.count({` |
| warning | warehouses/warehouses.service.ts | 307 | findMany possibly unscoped | `const warehouses = await this.prisma.warehouse.findMany({` |
| warning | warehouses/warehouses.service.ts | 361 | findMany possibly unscoped | `const rows = await this.prisma.warehouseTransfer.findMany({` |
| warning | warehouses/warehouses.service.ts | 429 | findMany possibly unscoped | `const products = await tx.product.findMany({` |
| warning | warranty-configs/warranty-configs.service.ts | 45 | findMany possibly unscoped | `const items = await this.prisma.warrantyProductConfig.findMany({` |
| warning | warranty-configs/warranty-configs.service.ts | 145 | findMany possibly unscoped | `const configs = await this.prisma.warrantyProductConfig.findMany({` |
| warning | work-scheduling/work-scheduling.service.ts | 186 | findMany possibly unscoped | `const existing = await this.prisma.workEmployeeConfig.findMany({` |
| warning | work-scheduling/work-scheduling.service.ts | 202 | findMany possibly unscoped | `const users = await this.prisma.user.findMany({` |
| warning | work-scheduling/work-scheduling.service.ts | 218 | findMany possibly unscoped | `const configs = await this.prisma.workEmployeeConfig.findMany({` |
| warning | work-scheduling/work-scheduling.service.ts | 349 | findMany possibly unscoped | `const profiles = await this.prisma.workScheduleProfile.findMany({` |
| warning | work-scheduling/work-scheduling.service.ts | 498 | findMany possibly unscoped | `const rules = await this.prisma.workCoverageRule.findMany({` |
| warning | work-scheduling/work-scheduling.service.ts | 556 | findMany possibly unscoped | `const list = await this.prisma.workScheduleException.findMany({` |
| warning | work-scheduling/work-scheduling.service.ts | 761 | findMany possibly unscoped | `const users = await this.prisma.user.findMany({` |
| warning | work-scheduling/work-scheduling.service.ts | 776 | findMany possibly unscoped | `const configs = await this.prisma.workEmployeeConfig.findMany({` |
| warning | work-scheduling/work-scheduling.service.ts | 1003 | findMany possibly unscoped | `const assignments = await this.prisma.workDayAssignment.findMany({` |
| warning | work-scheduling/work-scheduling.service.ts | 1010 | findMany possibly unscoped | `const users = await this.prisma.user.findMany({` |
| warning | work-scheduling/work-scheduling.service.ts | 1016 | findMany possibly unscoped | `const configs = await this.prisma.workEmployeeConfig.findMany({` |
| warning | work-scheduling/work-scheduling.service.ts | 1083 | findMany possibly unscoped | `const assignments = await this.prisma.workDayAssignment.findMany({` |
| warning | work-scheduling/work-scheduling.service.ts | 1101 | findMany possibly unscoped | `const users = await this.prisma.user.findMany({` |
| warning | work-scheduling/work-scheduling.service.ts | 1148 | findMany possibly unscoped | `const profileDays = await this.prisma.workScheduleProfileDay.findMany({` |
| warning | work-scheduling/work-scheduling.service.ts | 1156 | findMany possibly unscoped | `const exceptions = await this.prisma.workScheduleException.findMany({` |
| warning | work-scheduling/work-scheduling.service.ts | 1268 | findMany possibly unscoped | `? await tx.workDayAssignment.findMany({` |
| warning | work-scheduling/work-scheduling.service.ts | 1391 | findMany possibly unscoped | `const [fromA, toA] = await this.prisma.workDayAssignment.findMany({` |
| warning | work-scheduling/work-scheduling.service.ts | 1490 | findMany possibly unscoped | `const list = await this.prisma.workDayAssignment.findMany({` |
| warning | work-scheduling/work-scheduling.service.ts | 1638 | findMany possibly unscoped | `const logs = await this.prisma.workScheduleAuditLog.findMany({` |
| warning | work-scheduling/work-scheduling.service.ts | 1680 | findMany possibly unscoped | `const users = await this.prisma.user.findMany({` |
| warning | work-scheduling/work-scheduling.service.ts | 1705 | findMany possibly unscoped | `const weeks = await this.prisma.workWeekSchedule.findMany({` |
