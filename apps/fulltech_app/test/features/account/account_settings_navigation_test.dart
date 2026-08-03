import 'package:daleventa_pos/core/company/company_settings_model.dart';
import 'package:daleventa_pos/core/company/company_settings_repository.dart';
import 'package:daleventa_pos/core/printing/printing_platform_resolver.dart';
import 'package:daleventa_pos/core/routing/routes.dart';
import 'package:daleventa_pos/features/account/account_menu_screens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakePrintingPlatformResolver extends PrintingPlatformResolver {
  const _FakePrintingPlatformResolver(this._platform);

  final PrintingPlatform _platform;

  @override
  PrintingPlatform get platform => _platform;
}

Future<GoRouter> _pumpSettingsRouter(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({});
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final router = GoRouter(
    initialLocation: Routes.configuracion,
    routes: [
      GoRoute(
        path: Routes.configuracion,
        builder: (_, __) => const AccountSettingsScreen(),
      ),
      GoRoute(
        path: Routes.configuracionEmpresa,
        builder: (_, __) => const AccountCompanySettingsScreen(),
      ),
      GoRoute(
        path: Routes.configuracionDocumentos,
        builder: (_, __) => const AccountDocumentsSettingsScreen(),
      ),
      GoRoute(
        path: Routes.configuracionImpresora,
        builder: (_, __) => const AccountPrinterSettingsScreen(),
      ),
      GoRoute(
        path: Routes.configuracionBackup,
        builder: (_, __) => const AccountBackupSettingsScreen(),
      ),
    ],
  );
  addTearDown(router.dispose);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        companySettingsProvider.overrideWith(
          (_) async => CompanySettings.empty(),
        ),
        printingPlatformResolverProvider.overrideWithValue(
          const _FakePrintingPlatformResolver(PrintingPlatform.android),
        ),
      ],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
  return router;
}

void main() {
  const targets = <String, String>{
    'Empresa': 'Datos de empresa',
    'Documentos': 'Datos para documentos',
    'Impresora': 'Impresión y tickets',
    'Backup': 'Backup y recuperación',
  };

  for (final entry in targets.entries) {
    testWidgets('mobile settings card opens ${entry.key}', (tester) async {
      await _pumpSettingsRouter(tester);

      await tester.tap(find.text(entry.key).first);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text(entry.value), findsOneWidget);
    });
  }
}
