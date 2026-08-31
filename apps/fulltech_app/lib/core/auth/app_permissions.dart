import 'app_role.dart';
import '../models/user_model.dart';

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
  addStock,
  editProducts,
  viewWarehouseBreakdown,
  viewInventoryHistory,
  viewSales,
  viewSalesReports,
  applyDiscounts,
  refundSales,
  createFiscalInvoices,
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
  viewWarehouses,
  manageWarehouses,
  createWarehouses,
  editWarehouses,
  changeDefaultWarehouse,
  activateWarehouses,
  viewTerminals,
  manageTerminals,
  viewTransfers,
  createTransfers,
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
    AppPermission.addStock,
    AppPermission.editProducts,
    AppPermission.viewWarehouseBreakdown,
    AppPermission.viewInventoryHistory,
    AppPermission.viewSales,
    AppPermission.viewSalesReports,
    AppPermission.applyDiscounts,
    AppPermission.refundSales,
    AppPermission.createFiscalInvoices,
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
    AppPermission.viewWarehouses,
    AppPermission.manageWarehouses,
    AppPermission.createWarehouses,
    AppPermission.editWarehouses,
    AppPermission.changeDefaultWarehouse,
    AppPermission.activateWarehouses,
    AppPermission.viewTerminals,
    AppPermission.manageTerminals,
    AppPermission.viewTransfers,
    AppPermission.createTransfers,
    AppPermission.viewQuotes,
    AppPermission.viewClients,
    AppPermission.viewAccounting,
    AppPermission.manageUsers,
    AppPermission.managePayroll,
    AppPermission.viewMyWarnings,
  },
  AppRole.cajero: {
    AppPermission.viewProfile,
    AppPermission.viewCatalog,
    AppPermission.viewWarehouseBreakdown,
    AppPermission.viewSales,
    AppPermission.viewQuotes,
    AppPermission.viewClients,
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

bool hasUserPermission(UserModel? user, AppPermission permission) {
  if (user == null) return false;
  if (user.appRole == AppRole.admin) return true;
  final override = user.userPermissions[permission.name];
  if (override != null) return override;
  return hasPermission(user.appRole, permission);
}
