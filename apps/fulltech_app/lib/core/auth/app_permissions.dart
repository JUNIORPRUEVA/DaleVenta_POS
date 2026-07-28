import 'app_role.dart';

/// Central permission list used by routing, navigation and UI actions.
/// Keep this small and meaningful (module/screen/action-level capabilities).
enum AppPermission {
  // Common
  viewProfile,
  viewMyPayments,
  viewWhatsapp,

  // Core modules
  viewOperations,
  viewPunch,

  // Technician
  viewTechOperations,
  viewTechDepartures,

  // Sales/CRM
  viewCatalog,
  viewSales,
  viewSalesReports,
  viewPurchases,
  createPurchases,
  editPurchases,
  approvePurchases,
  cancelPurchases,
  receivePurchases,
  updateInventoryFromPurchases,
  manageSuppliers,
  viewPurchaseCosts,
  downloadPurchasePdf,
  deletePurchaseDrafts,
  viewQuotes,
  viewClients,
  viewMediaGallery,

  // Accounting
  viewAccounting,
  viewCompanyManual,

  // Admin
  viewAdminPanel,
  viewPublicidad,
  viewGaleriaPublicidad,
  manageUsers,
  manageSettings,
  managePayroll,
  manageCompanyManual,
  viewAdminTechDepartures,
  viewWhatsappCrm,
  viewCrmComercial,
  createCrmComercialCustomer,
  editCrmComercialCustomer,
  changeCrmComercialStatus,
  viewCrmComercialHistory,
  manageWebsite,
  viewTechnicalNetwork,
  viewTechnicalNetworkApplications,
  reviewTechnicalNetworkApplications,
  approveTechnicalNetworkApplications,
  rejectTechnicalNetworkApplications,
  createTechnicalNetworkTechnicians,
  editTechnicalNetworkTechnicians,
  deactivateTechnicalNetworkTechnicians,
  viewTechnicalNetworkPrivateDocuments,
  registerTechnicalNetworkJobs,
  evaluateTechnicalNetworkTechnicians,

  // HR
  viewWarnings,
  viewMyWarnings,
}

/// Role → permissions map. This is the *only* place to change access rules.
///
/// IMPORTANT: Technician is intentionally restricted to a technician-focused
/// experience (operations + punch + self areas).
const Map<AppRole, Set<AppPermission>> rolePermissions = {
  AppRole.admin: {
    AppPermission.viewProfile,
    AppPermission.viewMyPayments,
    AppPermission.viewCatalog,
    AppPermission.viewSales,
    AppPermission.viewSalesReports,
    AppPermission.viewPurchases,
    AppPermission.createPurchases,
    AppPermission.editPurchases,
    AppPermission.approvePurchases,
    AppPermission.cancelPurchases,
    AppPermission.receivePurchases,
    AppPermission.updateInventoryFromPurchases,
    AppPermission.manageSuppliers,
    AppPermission.viewPurchaseCosts,
    AppPermission.downloadPurchasePdf,
    AppPermission.deletePurchaseDrafts,
    AppPermission.viewQuotes,
    AppPermission.viewClients,
    AppPermission.viewAccounting,
    AppPermission.manageUsers,
    AppPermission.managePayroll,
    AppPermission.viewMyWarnings,
  },
  AppRole.asistente: {
    AppPermission.viewProfile,
    AppPermission.viewMyPayments,
    AppPermission.viewSales,
    AppPermission.viewQuotes,
    AppPermission.viewClients,
    AppPermission.viewAccounting,
    AppPermission.viewMyWarnings,
  },
  AppRole.vendedor: {
    AppPermission.viewProfile,
    AppPermission.viewMyPayments,
    AppPermission.viewSales,
    AppPermission.viewQuotes,
    AppPermission.viewClients,
    AppPermission.viewMyWarnings,
  },
  AppRole.marketing: {
    AppPermission.viewProfile,
    AppPermission.viewMyPayments,
    AppPermission.viewQuotes,
    AppPermission.viewClients,
    AppPermission.viewMyWarnings,
  },
  AppRole.tecnico: {
    AppPermission.viewProfile,
    AppPermission.viewMyPayments,
    AppPermission.viewQuotes,
    AppPermission.viewMyWarnings,
  },
  AppRole.unknown: {
    // Least privilege (still allow self areas to avoid redirect loops)
    AppPermission.viewProfile,
  },
};

bool hasPermission(AppRole role, AppPermission permission) {
  final set = rolePermissions[role];
  if (set == null) return false;
  return set.contains(permission);
}
