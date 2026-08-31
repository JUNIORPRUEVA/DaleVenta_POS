import 'package:daleventa_pos/core/auth/app_permissions.dart';
import 'package:daleventa_pos/core/routing/route_access.dart';
import 'package:daleventa_pos/core/routing/routes.dart';
import 'package:daleventa_pos/core/models/user_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('RouteAccess', () {
    test('protects settings, apps and licenses with manageSettings', () {
      const protectedRoutes = [
        Routes.configuracion,
        Routes.configuracionEmpresa,
        Routes.configuracionImpresora,
        Routes.configuracionBackup,
        Routes.configuracionParametros,
        Routes.configuracionDocumentos,
        Routes.apps,
        Routes.licencias,
        Routes.actualizaciones,
      ];

      for (final route in protectedRoutes) {
        expect(
          RouteAccess.permissionForLocation(route),
          AppPermission.manageSettings,
          reason: '$route debe requerir permiso de configuracion.',
        );
      }
    });

    test('keeps permission checks when location has query parameters', () {
      expect(
        RouteAccess.permissionForLocation(
          '${Routes.configuracion}?tab=empresa',
        ),
        AppPermission.manageSettings,
      );
      expect(
        RouteAccess.permissionForLocation('${Routes.apps}?source=menu'),
        AppPermission.manageSettings,
      );
    });

    test('protects warehouses and Kardex with inventory permissions', () {
      expect(
        RouteAccess.permissionForLocation(Routes.configuracionAlmacenes),
        AppPermission.manageWarehouses,
      );
      expect(
        RouteAccess.permissionForLocation(Routes.catalogoKardex),
        AppPermission.viewInventoryHistory,
      );
    });

    test('default home uses effective user permission overrides', () {
      final cashierWithoutQuotes = UserModel(
        id: 'employee-a',
        email: 'employee-a@test.local',
        nombreCompleto: 'Employee A',
        telefono: '',
        role: 'CAJERO',
        companyId: 'company-a',
        userPermissions: const {'viewQuotes': false, 'viewClients': true},
      );

      expect(
        RouteAccess.defaultHomeForUser(cashierWithoutQuotes),
        Routes.clientes,
      );
    });
  });
}
