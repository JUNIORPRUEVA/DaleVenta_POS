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
    AppPermission.viewWhatsapp,
    AppPermission.viewOperations,
    AppPermission.viewTechOperations,
    AppPermission.viewPunch,
    AppPermission.viewCatalog,
    AppPermission.viewSales,
    AppPermission.viewSalesReports,
    AppPermission.viewQuotes,
    AppPermission.viewClients,
    AppPermission.viewMediaGallery,
    AppPermission.viewAccounting,
    AppPermission.viewCompanyManual,
    AppPermission.viewAdminPanel,
    AppPermission.viewPublicidad,
    AppPermission.viewGaleriaPublicidad,
    AppPermission.manageUsers,
    AppPermission.manageSettings,
    AppPermission.managePayroll,
    AppPermission.manageCompanyManual,
    AppPermission.viewAdminTechDepartures,
    AppPermission.viewWhatsappCrm,
    AppPermission.viewCrmComercial,
    AppPermission.createCrmComercialCustomer,
    AppPermission.editCrmComercialCustomer,
    AppPermission.changeCrmComercialStatus,
    AppPermission.viewCrmComercialHistory,
    AppPermission.manageWebsite,
    AppPermission.viewWarnings,
    AppPermission.viewMyWarnings,
  },
  AppRole.asistente: {
    AppPermission.viewProfile,
    AppPermission.viewMyPayments,
    AppPermission.viewWhatsapp,
    AppPermission.viewOperations,
    AppPermission.viewPunch,
    AppPermission.viewSales,
    AppPermission.viewQuotes,
    AppPermission.viewClients,
    AppPermission.viewAccounting,
    AppPermission.viewCompanyManual,
    AppPermission.viewWarnings,
    AppPermission.viewMyWarnings,
    AppPermission.manageWebsite,
  },
  AppRole.vendedor: {
    AppPermission.viewProfile,
    AppPermission.viewMyPayments,
    AppPermission.viewWhatsapp,
    AppPermission.viewOperations,
    AppPermission.viewPunch,
    AppPermission.viewSales,
    AppPermission.viewQuotes,
    AppPermission.viewClients,
    AppPermission.viewCompanyManual,
    AppPermission.viewMyWarnings,
  },
  AppRole.marketing: {
    AppPermission.viewProfile,
    AppPermission.viewMyPayments,
    AppPermission.viewWhatsapp,
    AppPermission.viewOperations,
    AppPermission.viewPunch,
    AppPermission.viewQuotes,
    AppPermission.viewClients,
    AppPermission.viewMediaGallery,
    AppPermission.viewCompanyManual,
    AppPermission.viewMyWarnings,
    AppPermission.manageWebsite,
  },
  AppRole.tecnico: {
    AppPermission.viewProfile,
    AppPermission.viewMyPayments,
    AppPermission.viewWhatsapp,
    AppPermission.viewOperations,
    AppPermission.viewTechOperations,
    AppPermission.viewPunch,
    AppPermission.viewQuotes,
    AppPermission.viewTechDepartures,
    AppPermission.viewCompanyManual,
    AppPermission.viewMyWarnings,
  },
  AppRole.unknown: {
    // Least privilege (still allow self areas to avoid redirect loops)
    AppPermission.viewProfile,
    AppPermission.viewWhatsapp,
  },
};

bool hasPermission(AppRole role, AppPermission permission) {
  final set = rolePermissions[role];
  if (set == null) return false;
  return set.contains(permission);
}
