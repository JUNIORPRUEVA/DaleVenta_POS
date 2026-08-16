import 'package:daleventa_pos/core/company/company_settings_model.dart';
import 'package:daleventa_pos/core/company/company_settings_repository.dart';
import 'package:daleventa_pos/core/printing/printing_platform_resolver.dart';
import 'package:daleventa_pos/core/routing/routes.dart';
import 'package:daleventa_pos/features/account/account_menu_screens.dart';
import 'package:daleventa_pos/features/settings/data/mobile_printer_settings_model.dart';
import 'package:daleventa_pos/features/settings/data/mobile_printer_settings_repository.dart';
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

class _FakeMobilePrinterSettingsRepository
    extends MobilePrinterSettingsRepository {
  _FakeMobilePrinterSettingsRepository()
    : _settings = const MobilePrinterSettingsModel(
        companyScope: 'test',
        connectionType: MobilePrinterConnectionType.systemPrinter,
      ),
      super(companyScope: 'test');

  MobilePrinterSettingsModel _settings;

  @override
  Future<MobilePrinterSettingsModel> getOrCreate() async => _settings;

  @override
  Future<void> update(MobilePrinterSettingsModel settings) async {
    _settings = settings.copyWith(companyScope: companyScope);
  }

  @override
  Future<void> reset() async {
    _settings = const MobilePrinterSettingsModel(companyScope: 'test');
  }
}

Future<GoRouter> _pumpSettingsRouter(
  WidgetTester tester, {
  String initialLocation = Routes.configuracion,
  Size viewport = const Size(390, 844),
}) async {
  SharedPreferences.setMockInitialValues({});
  tester.view.physicalSize = viewport;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final router = GoRouter(
    initialLocation: initialLocation,
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
      GoRoute(
        path: Routes.configuracionParametros,
        builder: (_, __) => const AccountParametersScreen(),
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
        mobilePrinterSettingsRepositoryProvider.overrideWithValue(
          _FakeMobilePrinterSettingsRepository(),
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

      await tester.tap(find.byTooltip('Volver').first);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Empresa'), findsOneWidget);
      expect(find.text('Impresora'), findsOneWidget);
    });
  }

  testWidgets('mobile settings hub uses drawer leading instead of back', (
    tester,
  ) async {
    await _pumpSettingsRouter(tester);

    expect(find.byTooltip('Abrir menú'), findsOneWidget);
    expect(find.byTooltip('Volver'), findsNothing);
  });

  testWidgets('mobile settings back button responds across its tap target', (
    tester,
  ) async {
    await _pumpSettingsRouter(tester);

    await tester.tap(find.text('Empresa').first);
    await tester.pumpAndSettle();

    final backButton = find.byTooltip('Volver').first;
    final rect = tester.getRect(backButton);
    await tester.tapAt(rect.topCenter + const Offset(0, 8));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Empresa'), findsOneWidget);
    expect(find.text('Impresora'), findsOneWidget);
    expect(find.text('Backup'), findsOneWidget);
  });

  const desktopTargets = <String, String>{
    Routes.configuracionEmpresa: 'Datos de empresa',
    Routes.configuracionDocumentos: 'Datos para documentos',
    Routes.configuracionImpresora: 'Impresión y tickets',
    Routes.configuracionBackup: 'Backup y recuperación',
    Routes.configuracionParametros: 'Parámetros importantes',
  };

  for (final size in [Size(1024, 768), Size(1366, 768), Size(1920, 1080)]) {
    for (final entry in desktopTargets.entries) {
      testWidgets(
        'settings page ${entry.key} has no overflow at ${size.width.toInt()}x${size.height.toInt()}',
        (tester) async {
          await _pumpSettingsRouter(
            tester,
            initialLocation: entry.key,
            viewport: size,
          );

          expect(tester.takeException(), isNull);
          expect(find.text(entry.value), findsOneWidget);
        },
      );
    }
  }
}
