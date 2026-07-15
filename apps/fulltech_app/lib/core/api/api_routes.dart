/// Centraliza rutas de API para fácil ajuste
class ApiRoutes {
  static const releaseCheckUpdate = '/api/v1/check-update';
  static const login = '/auth/login';
  static const refresh = '/auth/refresh';
  static const me = '/auth/me';
  static const settings = '/settings';

  // Usuarios
  static const users = '/users';
  static const usersMe = '/users/me';
  static String userDetail(String id) => '/users/$id';
  static String updateUser(String id) => '/users/$id';
  static String deleteUser(String id) => '/users/$id';
  static String blockUser(String id) => '/users/$id/block';
  static String unblockUser(String id) => '/users/$id/unblock';
  static const usersUpload = '/users/upload';
  static const usersMeWorkContractSign = '/users/me/work-contract/sign';
  static String userWorkContractAiEdit(String id) =>
      '/users/$id/work-contract/ai-edit';
  static const upload = '/upload';

  // Ponche
  static const punch = '/punch';
  static const punchMe = '/punch/me';
  static const punchMeAttendance = '/punch/me/attendance';
  static const punchAdmin = '/admin/punch';
  static const punchAttendanceSummary = '/admin/attendance/summary';
  static String punchAttendanceUser(String id) => '/admin/attendance/user/$id';
  static const adminSales = '/admin/sales';
  static const adminSalesSummary = '/admin/sales/summary';
  static const adminServiceCommissions = '/admin/service-commissions';
  static const adminServiceCommissionsSummary =
      '/admin/service-commissions/summary';
  static const adminPanelOverview = '/admin/panel/overview';
  static const adminPanelAiInsights = '/admin/panel/ai-insights';

  // Ubicación
  static const locationsReport = '/locations';
  static const adminLocationsLatest = '/admin/locations/latest';

  // Contabilidad
  static const contabilidadCloses = '/contabilidad/closes';
  static String contabilidadCloseDetail(String id) =>
      '/contabilidad/closes/$id';
  static const contabilidadCloseDeleteBulk = '/contabilidad/closes/delete-bulk';
  static String contabilidadCloseApprove(String id) =>
      '/contabilidad/closes/$id/approve';
  static String contabilidadCloseReject(String id) =>
      '/contabilidad/closes/$id/reject';
  static String contabilidadCloseAiReport(String id) =>
      '/contabilidad/closes/$id/ai-report';
  static String contabilidadCloseCashDeposit(String id) =>
      '/contabilidad/closes/$id/cash-deposit';
  static const contabilidadCloseFinancialSummary =
      '/contabilidad/closes/financial-summary';
  static const contabilidadCloseVoucherUpload =
      '/contabilidad/closes/vouchers/upload';
  static const contabilidadDepositOrders = '/contabilidad/deposit-orders';
  static String contabilidadDepositOrderDetail(String id) =>
      '/contabilidad/deposit-orders/$id';
  static String contabilidadDepositOrderApprove(String id) =>
      '/contabilidad/deposit-orders/$id/approve';
  static String contabilidadDepositOrderCancel(String id) =>
      '/contabilidad/deposit-orders/$id/cancel';
  static const contabilidadFiscalInvoices = '/contabilidad/fiscal-invoices';
  static String contabilidadFiscalInvoiceDetail(String id) =>
      '/contabilidad/fiscal-invoices/$id';
  static const contabilidadFiscalInvoicesUpload =
      '/contabilidad/fiscal-invoices/upload';
  static const contabilidadPayableServices = '/contabilidad/payables/services';
  static String contabilidadPayableServiceDetail(String id) =>
      '/contabilidad/payables/services/$id';
  static String contabilidadPayableServicePayments(String id) =>
      '/contabilidad/payables/services/$id/payments';
  static const contabilidadPayablePayments = '/contabilidad/payables/payments';
  static String contabilidadPayablePaymentDetail(String id) =>
      '/contabilidad/payables/payments/$id';

  // Clientes
  static const clients = '/clients';
  static const clientsDebugPurge = '/clients/debug/purge';
  static String clientDetail(String id) => '/clients/$id';
  static String clientProfile(String id) => '/clients/$id/profile';
  static String clientTimeline(String id) => '/clients/$id/timeline';

  // CRM Comercial
  static const crmCommercialCustomers = '/crm-commercial/customers';
  static String crmCommercialCustomerById(String id) =>
      '/crm-commercial/customers/$id';
  static String crmCommercialCustomerStatus(String id) =>
      '/crm-commercial/customers/$id/status';
  static String crmCommercialCustomerNotes(String id) =>
      '/crm-commercial/customers/$id/notes';
  static String crmCommercialCustomerActivities(String id) =>
      '/crm-commercial/customers/$id/activities';

  static const crmCommercialFollowupTasks = '/crm-commercial/followup-tasks';
  static String crmCommercialCustomerFollowupTasks(String id) =>
      '/crm-commercial/customers/$id/followup-tasks';
  static String crmCommercialFollowupTaskComplete(String id) =>
      '/crm-commercial/followup-tasks/$id/complete';
  static String crmCommercialFollowupTaskCancel(String id) =>
      '/crm-commercial/followup-tasks/$id/cancel';
  static String crmCommercialFollowupTaskById(String id) =>
      '/crm-commercial/followup-tasks/$id';
  static const crmCommercialSettings = '/crm-commercial/settings';
  static const crmCommercialAvailableWhatsappInstances =
      '/crm-commercial/available-whatsapp-instances';
  static const crmCommercialConversations = '/crm-commercial/conversations';
  static String crmCommercialConversationRead(String id) =>
      '/crm-commercial/conversations/$id/read';
  static const crmCommercialStartConversationMessage =
      '/crm-commercial/conversations/start-message';
  static const crmCommercialStartConversationMedia =
      '/crm-commercial/conversations/start-media';
  static String crmCommercialConversationMessages(String id) =>
      '/crm-commercial/conversations/$id/messages';
  static String crmCommercialConversationReply(String id) =>
      '/crm-commercial/conversations/$id/reply';
  static String crmCommercialConversationReplyMedia(String id) =>
      '/crm-commercial/conversations/$id/reply-media';
  static String crmCommercialConversationMessageDelete(
    String conversationId,
    String messageId,
  ) => '/crm-commercial/conversations/$conversationId/messages/$messageId';
  static const crmCommercialLibrary = '/crm-commercial/library';
  static String crmCommercialLibraryUse(String id) =>
      '/crm-commercial/library/$id/use';
  static String crmCommercialLibraryItem(String id) =>
      '/crm-commercial/library/$id';
  static const crmCommercialOrthographySuggestion =
      '/crm-commercial/ai/orthography-suggestion';
  static const crmCommercialAiSuggestReply = '/crm-commercial/ai/suggest-reply';

  // CRM Comercial - Bot
  static const crmCommercialBotSettings = '/crm-commercial/bot/settings';
  static String crmCommercialBotConversationStatus(String id) =>
      '/crm-commercial/bot/conversations/$id/status';
  static String crmCommercialBotConversationPause(String id) =>
      '/crm-commercial/bot/conversations/$id/pause';
  static String crmCommercialBotConversationResume(String id) =>
      '/crm-commercial/bot/conversations/$id/resume';
  static String crmCommercialBotConversationExclude(String id) =>
      '/crm-commercial/bot/conversations/$id/exclude';
  static String crmCommercialBotConversationInclude(String id) =>
      '/crm-commercial/bot/conversations/$id/include';
  static String crmCommercialBotConversationSuggest(String id) =>
      '/crm-commercial/bot/conversations/$id/suggest';
  static String crmCommercialBotConversationSend(String id) =>
      '/crm-commercial/bot/conversations/$id/send';

  // Productos
  static const products = '/products';
  static const catalogProducts = '/products';
  static const productsDebugPurge = '/products/debug/purge';
  static const productsUpload = '/products/upload';
  static String productDetail(String id) => '/products/$id';
  static String updateProduct(String id) => '/products/$id';
  static String deleteProduct(String id) => '/products/$id';

  // Ventas
  static const sales = '/sales';
  static const salesInvoices = '/sales/invoices';
  static const salesDebugPurge = '/sales/debug/purge';
  static const salesSummary = '/sales/summary';
  static String saleDetail(String id) => '/sales/$id';
  static String saleReturn(String id) => '/sales/$id/return';

  static const services = '/services';
  static const technicians = '/technicians';
  static String serviceDetail(String id) => '/services/$id';
  static String orderDetail(String id) => '/ordenes/$id';
  static String serviceStatus(String id) => '/services/$id/status';
  static String serviceOrderState(String id) => '/services/$id/order-state';
  static String servicePhase(String id) => '/services/$id/phase';
  static String serviceAdminPhase(String id) => '/services/$id/admin-phase';
  static String serviceAdminStatus(String id) => '/services/$id/admin-status';
  static String servicePhases(String id) => '/services/$id/phases';
  static String serviceSchedule(String id) => '/services/$id/schedule';
  static String serviceAssign(String id) => '/services/$id/assign';
  static String serviceUpdate(String id) => '/services/$id/update';
  static String serviceFiles(String id) => '/services/$id/files';
  static String serviceSignature(String id) => '/services/$id/signature';
  static String serviceExecutionReport(String id) =>
      '/services/$id/execution-report';
  static String serviceChecklists(String id) => '/services/$id/checklists';
  static String serviceExecutionChanges(String id) =>
      '/services/$id/execution-report/changes';
  static String serviceExecutionChangeDelete(String id, String changeId) =>
      '/services/$id/execution-report/changes/$changeId';
  static const checklistCategories = '/checklist/categories';
  static const checklistPhases = '/checklist/phases';
  static const checklistTemplates = '/checklist/templates';
  static const checklistTemplate = '/checklist/template';
  static const checklistItem = '/checklist/item';
  static String checklistItemCheck(String id) => '/checklist/item/$id/check';
  static const warrantyConfigs = '/warranty-configs';
  static String warrantyConfigDetail(String id) => '/warranty-configs/$id';
  static String warrantyConfigActive(String id) =>
      '/warranty-configs/$id/active';

  // Nómina
  static const payrollPeriods = '/payroll/periods';
  static const payrollPeriodEnsureCurrentOpen =
      '/payroll/periods/ensure-current-open';
  static const payrollPeriodOpenOverlap = '/payroll/periods/open-overlap';
  static String payrollPeriodDetail(String id) => '/payroll/periods/$id';
  static String payrollPeriodClose(String id) => '/payroll/periods/$id/close';
  static String payrollPeriodNextOpen(String id) =>
      '/payroll/periods/$id/next-open';
  static String payrollPeriodTotalAll(String id) =>
      '/payroll/periods/$id/total-all';

  static const payrollEmployees = '/payroll/employees';
  static const payrollEmployeeUpsert = '/payroll/employees/upsert';
  static String payrollEmployeeDetail(String id) => '/payroll/employees/$id';

  static const payrollConfig = '/payroll/config';
  static const payrollConfigUpsert = '/payroll/config/upsert';

  static const payrollEntries = '/payroll/entries';
  static String payrollEntryDetail(String id) => '/payroll/entries/$id';
  static const payrollPaymentStatus = '/payroll/payment-status';
  static const payrollPaymentStatusMarkPaid =
      '/payroll/payment-status/mark-paid';
  static const payrollPendingServiceCommissions =
      '/payroll/service-commissions/pending';
  static String payrollApproveServiceCommission(String id) =>
      '/payroll/service-commissions/$id/approve';
  static String payrollRejectServiceCommission(String id) =>
      '/payroll/service-commissions/$id/reject';

  static const payrollTotals = '/payroll/totals';
  static const payrollMyHistory = '/payroll/my-history';
  static const payrollMyGoal = '/payroll/my-goal';
  static const payrollSendWhatsapp = '/payroll/send-whatsapp';
  static const payrollSendWhatsappSchedule = '/payroll/send-whatsapp/schedule';

  // Manual interno
  static const companyManualEntries = '/company-manual';
  static const companyManualSummary = '/company-manual/summary';
  static String companyManualEntryDetail(String id) => '/company-manual/$id';

  // Cotizaciones (nube)
  static const cotizaciones = '/cotizaciones';
  static const cotizacionesDebugPurge = '/cotizaciones/debug/purge';
  static String cotizacionDetail(String id) => '/cotizaciones/$id';
  static const cotizacionAiAnalyze = '/cotizaciones/ai/analyze';
  static const cotizacionAiChat = '/cotizaciones/ai/chat';
  static const cotizacionSendWhatsapp = '/cotizaciones/send-whatsapp';

  // Service orders
  static const serviceOrders = '/service-orders';
  static const serviceOrdersDebugPurge = '/service-orders/debug/purge';
  static const serviceOrderSalesSummary = '/service-orders/sales-summary';
  static const serviceOrderCommissions = '/service-orders/commissions';
  static const mediaGallery = '/media-gallery';
  static const mediaGalleryPublicidad = '/media-gallery/publicidad';
  static String mediaGalleryDelete(String id) => '/media-gallery/$id';
  static String mediaGalleryMarkPublicidad(String id) =>
      '/media-gallery/$id/publicidad';
  static String mediaGalleryUnmarkPublicidad(String id) =>
      '/media-gallery/$id/quitar-publicidad';
  static const publicidadImages = '/publicidad-images';
  static String publicidadImagesDelete(String id) => '/publicidad-images/$id';
  static String publicidadImagesUpdate(String id) => '/publicidad-images/$id';
  static const marketingDashboard = '/marketing/dashboard';
  static const marketingStories = '/marketing/stories';
  static const marketingStoriesGenerateMissing =
      '/marketing/stories/generate-missing';
  static const marketingStoriesRepairIncomplete =
      '/marketing/stories/repair-incomplete';
  static String marketingStoryApprove(String id) =>
      '/marketing/stories/$id/approve';
  static String marketingStoryRetryPublish(String id) =>
      '/marketing/stories/$id/retry-publish';
  static String marketingStoryReject(String id) =>
      '/marketing/stories/$id/reject';
  static String marketingStoryRegenerate(String id) =>
      '/marketing/stories/$id/regenerate';
  static String marketingStoryRegenerateImage(String id) =>
      '/marketing/stories/$id/regenerate-image';
  static String marketingStoryChangeBaseImage(String id, String mediaAssetId) =>
      '/marketing/stories/$id/base-image/$mediaAssetId';
  static String marketingStoryEdit(String id) => '/marketing/stories/$id';
  static const marketingCampaigns = '/marketing/campaigns';
  static const marketingCampaignsGenerateMissing =
      '/marketing/campaigns/generate-missing';
  static String marketingCampaignConfirmBaseImage(String id) =>
      '/marketing/campaigns/$id/confirm-base-image';
  static String marketingCampaignChangeBaseImage(
    String id,
    String mediaAssetId,
  ) => '/marketing/campaigns/$id/base-image/$mediaAssetId';
  static String marketingCampaignUploadDesign(String id) =>
      '/marketing/campaigns/$id/upload-design';
  static String marketingCampaignRegenerateCopy(String id) =>
      '/marketing/campaigns/$id/regenerate-copy';
  static String marketingCampaignUpdate(String id) =>
      '/marketing/campaigns/$id';
  static String marketingCampaignCreateMeta(String id) =>
      '/marketing/campaigns/$id/create-meta-campaign';
  static String marketingCampaignActivate(String id) =>
      '/marketing/campaigns/$id/activate';
  static String marketingCampaignPause(String id) =>
      '/marketing/campaigns/$id/pause';
  static String marketingCampaignReject(String id) =>
      '/marketing/campaigns/$id/reject';
  static String marketingCampaignDuplicate(String id) =>
      '/marketing/campaigns/$id/duplicate';
  static String marketingCampaignDetails(String id) =>
      '/marketing/campaigns/$id/details';
  static const marketingDebugMetaAdsConfig = '/marketing/debug/meta-ads-config';
  static const marketingDebugMetaRuntimeConfig =
      '/marketing/debug/meta-runtime-config';
  static const marketingDebugMetaAdsPermissions =
      '/marketing/debug/meta-ads-permissions';
  static const marketingDebugMetaAdAccounts =
      '/marketing/debug/meta-adaccounts';
  static const marketingDebugMetaN8nCompatibility =
      '/marketing/debug/meta-n8n-compatibility';
  static const marketingDebugMetaWhatsapp = '/marketing/debug/meta-whatsapp';
  static const marketingContentGallery = '/marketing/content-gallery';
  static const marketingMediaAssets = '/marketing/media-assets';
  static const marketingPublishedAssets = '/marketing/published-assets';
  static const marketingSocialAccounts = '/marketing/social-accounts';
  static String marketingMediaAssetById(String id) =>
      '/marketing/media-assets/$id';
  static String marketingSocialAccountById(String id) =>
      '/marketing/social-accounts/$id';
  static const marketingHistory = '/marketing/history';
  static const marketingConfig = '/marketing/config';
  static const marketingResearchConfig = '/marketing/research/config';
  static const marketingResearchLatest = '/marketing/research/latest';
  static const marketingResearchList = '/marketing/research/list';
  static const marketingResearchGenerate = '/marketing/research/generate';
  static const marketingResearchForce = '/marketing/research/force';
  static const marketingResearchLearningStats =
      '/marketing/research/learning-stats';
  static String marketingResearchApprove(String id) =>
      '/marketing/research/$id/approve';
  static String marketingResearchReject(String id) =>
      '/marketing/research/$id/reject';
  static const marketingFlowActivate = '/marketing/flow/activate';
  static const marketingFlowPause = '/marketing/flow/pause';
  static const marketingFlowReset = '/marketing/flow/reset';
  static const marketingResetClean = '/marketing/reset-clean';
  static String serviceOrderDetail(String id) => '/service-orders/$id';
  static String serviceOrderUpdate(String id) => '/service-orders/$id';
  static String serviceOrderDelete(String id) => '/service-orders/$id';
  static String serviceOrderStatus(String id) => '/service-orders/$id/status';
  static String serviceOrderEvidences(String id) =>
      '/service-orders/$id/evidences';
  static String serviceOrderReport(String id) => '/service-orders/$id/report';
  static String serviceOrderClone(String id) => '/service-orders/$id/clone';

  // Document flows
  static const documentFlows = '/document-flows';
  static String documentFlowByOrder(String orderId) =>
      '/document-flows/$orderId';
  static String documentFlowEditDraft(String id) =>
      '/document-flows/$id/edit-draft';
  static String documentFlowGenerate(String id) =>
      '/document-flows/$id/generate';
  static String documentFlowSend(String id) => '/document-flows/$id/send';
  static String documentFlowDelete(String id) => '/document-flows/$id';

  // Asistente IA (global)
  static const aiChat = '/ai/chat';

  // Storage (R2 presigned uploads)
  static const storagePresign = '/storage/presign';
  static const storageConfirm = '/storage/confirm';
  static String storageByService(String serviceId) =>
      '/storage/service/$serviceId';
  static String storageItem(String id) => '/storage/$id';

  // Horarios (Work Scheduling)
  static const workSchedulingEmployees = '/work-scheduling/employees';
  static String workSchedulingEmployee(String id) =>
      '/work-scheduling/employees/$id';

  static const workSchedulingProfiles = '/work-scheduling/profiles';
  static const workSchedulingProfilesUpsert =
      '/work-scheduling/profiles/upsert';

  static const workSchedulingCoverageRules = '/work-scheduling/coverage-rules';
  static const workSchedulingCoverageRulesUpsert =
      '/work-scheduling/coverage-rules/upsert';

  static const workSchedulingExceptions = '/work-scheduling/exceptions';
  static String workSchedulingException(String id) =>
      '/work-scheduling/exceptions/$id';
  static String workSchedulingExceptionDelete(String id) =>
      '/work-scheduling/exceptions/$id/delete';

  static const workSchedulingWeeksGenerate = '/work-scheduling/weeks/generate';
  static String workSchedulingWeek(String weekStartDate) =>
      '/work-scheduling/weeks/$weekStartDate';

  static const workSchedulingManualMoveDayOff =
      '/work-scheduling/manual/move-day-off';
  static const workSchedulingManualSwapDayOff =
      '/work-scheduling/manual/swap-day-off';

  static const workSchedulingAudit = '/work-scheduling/audit';
  static const workSchedulingReportMostChanges =
      '/work-scheduling/reports/most-changes';
  static const workSchedulingReportLowCoverage =
      '/work-scheduling/reports/low-coverage';

  // WhatsApp (instancias por usuario)
  static const whatsappInstance = '/whatsapp/instance';
  static const whatsappInstanceStatus = '/whatsapp/instance/status';
  static const whatsappInstanceQr = '/whatsapp/instance/qr';
  static const whatsappAdminUsers = '/whatsapp/admin/users';

  // Employee Warnings (Amonestaciones)
  static const employeeWarnings = '/employee-warnings';
  static String employeeWarningDetail(String id) => '/employee-warnings/$id';
  static String employeeWarningUpdate(String id) => '/employee-warnings/$id';
  static String employeeWarningDelete(String id) => '/employee-warnings/$id';
  static String employeeWarningSubmit(String id) =>
      '/employee-warnings/$id/submit';
  static String employeeWarningAnnul(String id) =>
      '/employee-warnings/$id/annul';
  static String employeeWarningPdf(String id) => '/employee-warnings/$id/pdf';
  static String employeeWarningPdfDownload(String id) =>
      '/employee-warnings/$id/pdf-download';
  static String employeeWarningEvidences(String id) =>
      '/employee-warnings/$id/evidences';
  static const employeeWarningsMyPending = '/employee-warnings/me/pending';
  static String employeeWarningsMy(String id) => '/employee-warnings/me/$id';
  static String employeeWarningsMyPdf(String id) =>
      '/employee-warnings/me/$id/pdf';
  static String employeeWarningsMySign(String id) =>
      '/employee-warnings/me/$id/sign';
  static String employeeWarningsMyRefuse(String id) =>
      '/employee-warnings/me/$id/refuse';
}
