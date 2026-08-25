import 'dart:async';
import 'dart:io';

import 'package:daleventa_pos/core/auth/auth_provider.dart';
import 'package:daleventa_pos/core/company/company_settings_model.dart';
import 'package:daleventa_pos/core/company/company_settings_repository.dart';
import 'package:daleventa_pos/core/models/user_model.dart';
import 'package:daleventa_pos/core/offline/offline_store.dart';
import 'package:daleventa_pos/core/offline/sync_queue_service.dart';
import 'package:daleventa_pos/core/printing/printing_platform_resolver.dart';
import 'package:daleventa_pos/core/routing/routes.dart';
import 'package:daleventa_pos/features/account/account_menu_screens.dart';
import 'package:daleventa_pos/features/settings/data/mobile_printer_settings_model.dart';
import 'package:daleventa_pos/features/settings/data/mobile_printer_settings_repository.dart';
import 'package:dio/dio.dart';
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

class _FakeCompanySettingsRepository extends CompanySettingsRepository {
  _FakeCompanySettingsRepository({this.saveCompleter, this.pinCompleter})
    : super(Dio(), SyncQueueService(OfflineStore.instance));

  final Completer<bool>? saveCompleter;
  final Completer<AdminAuthorizationVerification>? pinCompleter;

  @override
  Future<CompanySettings> getSettings() async => CompanySettings.empty();

  @override
  Future<bool> saveSettingsOrQueue(CompanySettings settings) {
    final completer = saveCompleter;
    if (completer != null) return completer.future;
    return Future.value(false);
  }

  @override
  Future<AdminAuthorizationVerification> verifyAdminAuthorizationPin(
    String pin,
  ) {
    final completer = pinCompleter;
    if (completer != null) return completer.future;
    return Future.value(
      const AdminAuthorizationVerification(
        duration: Duration(minutes: 5),
        token: 'test-token',
      ),
    );
  }
}

class _TestAuthController extends AuthController {
  _TestAuthController(super.ref, {required String role}) {
    state = AuthState(
      initialized: true,
      isAuthenticated: true,
      user: UserModel(
        id: 'u-test',
        email: 'test@example.com',
        nombreCompleto: 'Test User',
        telefono: '',
        role: role,
        companyId: 'company-test',
      ),
    );
  }
}

Future<GoRouter> _pumpSettingsRouter(
  WidgetTester tester, {
  String initialLocation = Routes.configuracion,
  Size viewport = const Size(390, 844),
  CompanySettingsRepository? companyRepository,
  String userRole = 'ADMIN',
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
        if (companyRepository != null)
          companySettingsRepositoryProvider.overrideWithValue(
            companyRepository,
          ),
        authStateProvider.overrideWith(
          (ref) => _TestAuthController(ref, role: userRole),
        ),
        printingPlatformResolverProvider.overrideWithValue(
          const _FakePrintingPlatformResolver(PrintingPlatform.android),
        ),
        mobilePrinterSettingsRepositoryProvider.overrideWithValue(
          _FakeMobilePrinterSettingsRepository(),
        ),
      ],
      child: MaterialApp.router(
        theme: ThemeData(platform: TargetPlatform.android),
        routerConfig: router,
      ),
    ),
  );
  await _settleSettingsFrame(tester);
  return router;
}

String _readProjectFile(String path) => File(path).readAsStringSync();

Future<void> _settleSettingsFrame(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 120));
  await tester.pump(const Duration(milliseconds: 120));
}

void main() {
  testWidgets('dispose during fiscal company save does not use WidgetRef', (
    tester,
  ) async {
    final saveCompleter = Completer<bool>();
    await _pumpSettingsRouter(
      tester,
      initialLocation: Routes.configuracionEmpresa,
      viewport: const Size(1366, 1200),
      companyRepository: _FakeCompanySettingsRepository(
        saveCompleter: saveCompleter,
      ),
    );

    final saveButton = find.text('Guardar empresa');
    await tester.ensureVisible(saveButton);
    await tester.tap(saveButton);
    await tester.pump();

    expect(saveCompleter.isCompleted, isFalse);

    await tester.pumpWidget(const SizedBox.shrink());
    saveCompleter.complete(false);
    await _settleSettingsFrame(tester);

    expect(tester.takeException(), isNull);
  });

  testWidgets('dispose during admin PIN validation does not use WidgetRef', (
    tester,
  ) async {
    final pinCompleter = Completer<AdminAuthorizationVerification>();
    await _pumpSettingsRouter(
      tester,
      initialLocation: Routes.configuracionEmpresa,
      viewport: const Size(1366, 1200),
      userRole: 'CAJERO',
      companyRepository: _FakeCompanySettingsRepository(
        pinCompleter: pinCompleter,
      ),
    );

    final saveButton = find.text('Guardar empresa');
    await tester.ensureVisible(saveButton);
    await tester.tap(saveButton);
    await _settleSettingsFrame(tester);

    await tester.enterText(find.byType(TextField).last, '1234');
    await tester.tap(find.text('Autorizar').hitTestable());
    await tester.pump();

    expect(pinCompleter.isCompleted, isFalse);

    await tester.pumpWidget(const SizedBox.shrink());
    pinCompleter.complete(
      const AdminAuthorizationVerification(
        duration: Duration(minutes: 5),
        token: 'pin-token',
      ),
    );
    await _settleSettingsFrame(tester);

    expect(tester.takeException(), isNull);
  });

  test('company tax settings async save is guarded after dispose', () {
    final source = _readProjectFile(
      'lib/features/account/account_menu_screens.dart',
    );

    expect(source, contains('final settingsRepository = ref.read'));
    expect(source, contains('await settingsRepository.saveSettingsOrQueue'));

    final saveIndex = source.indexOf(
      'await settingsRepository.saveSettingsOrQueue',
    );
    final mountedGuardIndex = source.indexOf(
      'if (!mounted) return;',
      saveIndex,
    );
    final invalidateIndex = source.indexOf(
      'ref.invalidate(companySettingsProvider);',
      saveIndex,
    );

    expect(saveIndex, greaterThanOrEqualTo(0));
    expect(mountedGuardIndex, greaterThan(saveIndex));
    expect(invalidateIndex, greaterThan(mountedGuardIndex));
  });

  test('admin authorization dialog does not read ref after pin await', () {
    final source = _readProjectFile('lib/core/auth/admin_authorization.dart');

    final verifyIndex = source.indexOf(
      'await repository.verifyAdminAuthorizationPin(value);',
    );
    final mountedGuardIndex = source.indexOf(
      'if (!mounted) return;',
      verifyIndex,
    );
    final popIndex = source.indexOf(
      'Navigator.of(context).pop(true);',
      verifyIndex,
    );

    expect(verifyIndex, greaterThanOrEqualTo(0));
    expect(mountedGuardIndex, greaterThan(verifyIndex));
    expect(popIndex, greaterThan(mountedGuardIndex));
  });

  const targets = <String, String>{
    'Empresa': 'Datos de empresa',
    'Impresora': 'Impresión y tickets',
    'Backup': 'Backup y recuperación',
  };

  for (final entry in targets.entries) {
    testWidgets('mobile settings card opens ${entry.key}', (tester) async {
      await _pumpSettingsRouter(tester);

      await tester.tap(find.text(entry.key).hitTestable().first);
      await _settleSettingsFrame(tester);

      expect(tester.takeException(), isNull);
      expect(find.text(entry.value), findsOneWidget);

      await tester.tap(find.byTooltip('Volver').hitTestable().first);
      await _settleSettingsFrame(tester);

      expect(tester.takeException(), isNull);
      expect(find.text('Empresa').hitTestable(), findsWidgets);
      expect(find.text('Impresora').hitTestable(), findsWidgets);
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

    await tester.tap(find.text('Empresa').hitTestable().first);
    await _settleSettingsFrame(tester);

    final backButton = find.byTooltip('Volver').hitTestable().first;
    final rect = tester.getRect(backButton);
    expect(rect.width, greaterThanOrEqualTo(48));
    expect(rect.height, greaterThanOrEqualTo(48));
    await tester.tapAt(rect.centerLeft + const Offset(8, 0));
    await _settleSettingsFrame(tester);

    expect(tester.takeException(), isNull);
    expect(find.text('Empresa').hitTestable(), findsWidgets);
    expect(find.text('Impresora').hitTestable(), findsWidgets);
    expect(find.text('Backup').hitTestable(), findsWidgets);
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
