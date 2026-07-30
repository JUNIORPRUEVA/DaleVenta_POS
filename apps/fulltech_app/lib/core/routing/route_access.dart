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
      case Routes.publicidadGaleria:
        return null;
      case Routes.catalogo:
        return AppPermission.viewCatalog;
      case Routes.ventas:
        return AppPermission.viewSalesReports;
      case Routes.compras:
        return AppPermission.viewPurchases;
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
      case Routes.mediaGallery:
      case Routes.galeriaPublicidad:
        return null;
      case Routes.cotizaciones:
      case Routes.cotizacionesHistorial:
        return AppPermission.viewQuotes;
      case Routes.clientes:
      case Routes.clienteNuevo:
        return AppPermission.viewClients;
      case Routes.nomina:
        return AppPermission.managePayroll;
      case Routes.manualInterno:
        return null;
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
        return null;
      case Routes.apps:
      case Routes.licencias:
      case Routes.actualizaciones:
      case Routes.configuracion:
      case Routes.configuracionEmpresa:
      case Routes.configuracionImpresora:
      case Routes.configuracionBackup:
      case Routes.configuracionParametros:
      case Routes.configuracionDocumentos:
        return null;
      case Routes.whatsapp:
        return null;
      case Routes.publicidad:
      case Routes.publicidadInvestigacion:
      case Routes.publicidadEstados:
      case Routes.publicidadCampanas:
      case Routes.publicidadMarketplace:
        return null;
      case Routes.whatsappCrm:
        return null;
      case Routes.crmComercial:
        return null;
      case Routes.sitioWeb:
        return null;
      case Routes.redTecnica:
        return null;
      case Routes.redTecnicaPublicForm:
        return null;
      case Routes.amonestaciones:
        return null;
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
      return null;
    }
    if (path.startsWith('${Routes.serviceOrders}/')) {
      return null;
    }
    if (path.startsWith('/users/')) {
      return AppPermission.manageUsers;
    }
    if (path.startsWith('${Routes.contabilidad}/')) {
      return AppPermission.viewAccounting;
    }
    if (path.startsWith('/amonestaciones/')) {
      return null;
    }
    if (path.startsWith('${Routes.administracion}/')) {
      return null;
    }
    if (path.startsWith('${Routes.publicidad}/')) {
      return null;
    }
    if (path.startsWith('${Routes.sitioWeb}/')) {
      return null;
    }
    if (path.startsWith('${Routes.redTecnica}/') &&
        path != Routes.redTecnicaPublicForm) {
      return null;
    }
    return null;
  }

  static String defaultHomeForRole(AppRole role) {
    if (hasPermission(role, AppPermission.viewQuotes)) {
      return Routes.cotizaciones;
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
