import '../auth/app_permissions.dart';
import '../auth/app_role.dart';
import 'routes.dart';

/// Maps routes to the permission required to access them.
///
/// This is enforced at the router level (deep-link safe) and reused
/// by navigation (drawer/tabs) to avoid duplicating logic.
class RouteAccess {
  static AppPermission? permissionForLocation(String location) {
    final path = location.split('?').first;

    // Exact matches first
    switch (path) {
      case Routes.profile:
        return AppPermission.viewProfile;
      case Routes.misPagos:
        return AppPermission.viewMyPayments;
      case Routes.ponche:
      case Routes.poncheHistorial:
        return AppPermission.viewPunch;
      case Routes.publicidadGaleria:
        return AppPermission.viewPublicidad;
      case Routes.catalogo:
        return AppPermission.viewCatalog;
      case Routes.ventas:
        return AppPermission.viewSalesReports;
      case Routes.ventasLista:
      case Routes.ventasCreditos:
      case Routes.caja:
      case Routes.cajaRegistrarIngreso:
      case Routes.cajaRegistrarSalida:
      case Routes.cajaMovimientos:
      case Routes.cajaRegistrarGasto:
      case Routes.cajaGastosHistorial:
      case Routes.cajaTurnosHistorial:
      case Routes.registrarVenta:
        return AppPermission.viewSales;
      case Routes.serviceOrders:
      case Routes.serviceOrderCommissions:
      case Routes.serviceOrderCreate:
        return AppPermission.viewOperations;
      case Routes.mediaGallery:
        return AppPermission.viewMediaGallery;
      case Routes.galeriaPublicidad:
        return AppPermission.viewGaleriaPublicidad;
      case Routes.cotizaciones:
      case Routes.cotizacionesHistorial:
        return AppPermission.viewQuotes;
      case Routes.clientes:
      case Routes.clienteNuevo:
        return AppPermission.viewClients;
      case Routes.nomina:
        return AppPermission.managePayroll;
      case Routes.manualInterno:
        return AppPermission.viewCompanyManual;
      case Routes.contabilidad:
      case Routes.contabilidadCierresDiarios:
      case Routes.contabilidadDepositos:
      case Routes.contabilidadFacturaFiscal:
      case Routes.contabilidadPagosPendientes:
        return AppPermission.viewAccounting;
      case Routes.administracion:
      case Routes.administracionPonches:
      case Routes.administracionVentas:
      case Routes.administracionComisiones:
      case Routes.administracionCotizaciones:
        return AppPermission.viewAdminPanel;
      case Routes.configuracion:
        return AppPermission.manageSettings;
      case Routes.whatsapp:
        return AppPermission.viewWhatsapp;
      case Routes.publicidad:
      case Routes.publicidadInvestigacion:
      case Routes.publicidadEstados:
      case Routes.publicidadCampanas:
      case Routes.publicidadMarketplace:
        return AppPermission.viewPublicidad;
      case Routes.whatsappCrm:
        return AppPermission.viewWhatsappCrm;
      case Routes.crmComercial:
        return AppPermission.viewCrmComercial;
      case Routes.sitioWeb:
        return AppPermission.manageWebsite;
      case Routes.amonestaciones:
        return AppPermission.viewWarnings;
      case Routes.misAmonestacionesPendientes:
        return null;
      case Routes.users:
      case Routes.user:
        return AppPermission.manageUsers;
    }

    // Prefix matches (parameterized routes)
    if (path.startsWith('/clientes/')) {
      return AppPermission.viewClients;
    }
    if (path.startsWith('${Routes.ponche}/')) {
      return AppPermission.viewPunch;
    }
    if (path.startsWith('${Routes.serviceOrders}/')) {
      return AppPermission.viewOperations;
    }
    if (path.startsWith('/users/')) {
      return AppPermission.manageUsers;
    }
    if (path.startsWith('${Routes.contabilidad}/')) {
      return AppPermission.viewAccounting;
    }
    if (path.startsWith('/amonestaciones/')) {
      return AppPermission.viewWarnings;
    }
    if (path.startsWith('${Routes.administracion}/')) {
      return AppPermission.viewAdminPanel;
    }
    if (path.startsWith('${Routes.publicidad}/')) {
      return AppPermission.viewPublicidad;
    }
    if (path.startsWith('${Routes.sitioWeb}/')) {
      return AppPermission.manageWebsite;
    }
    return null;
  }

  static String defaultHomeForRole(AppRole role) {
    if (hasPermission(role, AppPermission.viewQuotes)) {
      return Routes.cotizaciones;
    }
    if (hasPermission(role, AppPermission.viewOperations)) {
      return Routes.serviceOrders;
    }
    if (hasPermission(role, AppPermission.viewClients)) {
      return Routes.clientes;
    }
    if (hasPermission(role, AppPermission.viewSales)) {
      return Routes.ventasLista;
    }
    if (hasPermission(role, AppPermission.viewCatalog)) {
      return Routes.catalogo;
    }

    return Routes.profile;
  }
}
