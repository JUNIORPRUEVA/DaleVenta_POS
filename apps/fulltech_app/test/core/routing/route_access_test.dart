import 'package:daleventa_pos/core/auth/app_permissions.dart';
import 'package:daleventa_pos/core/routing/route_access.dart';
import 'package:daleventa_pos/core/routing/routes.dart';
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
        RouteAccess.permissionForLocation('${Routes.configuracion}?tab=empresa'),
        AppPermission.manageSettings,
      );
      expect(
        RouteAccess.permissionForLocation('${Routes.apps}?source=menu'),
        AppPermission.manageSettings,
      );
    });
  });
}
