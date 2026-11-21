import 'dart:async';
import 'dart:io';

import '../../support/inactive_activation_controller.dart';
import 'package:daleventa_pos/core/widgets/compact_square_switch.dart';
import 'package:daleventa_pos/features/onboarding/application/activation_controller.dart';

import 'package:daleventa_pos/core/auth/auth_provider.dart';
import 'package:daleventa_pos/core/company/company_settings_feedback.dart';
import 'package:daleventa_pos/core/company/company_settings_model.dart';
import 'package:daleventa_pos/core/company/company_settings_repository.dart';
import 'package:daleventa_pos/core/errors/api_exception.dart';
import 'package:daleventa_pos/core/models/user_model.dart';
import 'package:daleventa_pos/core/offline/offline_store.dart';
import 'package:daleventa_pos/core/offline/sync_queue_service.dart';
import 'package:daleventa_pos/core/printing/printing_platform_resolver.dart';
import 'package:daleventa_pos/core/routing/routes.dart';
import 'package:daleventa_pos/core/utils/app_feedback.dart';
import 'package:daleventa_pos/features/account/account_menu_screens.dart';
import 'package:daleventa_pos/features/settings/data/mobile_printer_settings_model.dart';
import 'package:daleventa_pos/features/settings/data/mobile_printer_settings_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../support/feedback_finders.dart';

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
  _FakeCompanySettingsRepository({
    Completer<bool>? saveCompleter,
    Completer<AdminAuthorizationVerification>? pinCompleter,
    Completer<void>? saveCalled,
    Completer<void>? pinCalled,
    CompanySettings? initialSettings,
    Object? saveError,
  }) : this._(
         OfflineStore.forTesting(
           'account_settings_navigation_${_nextStoreId()}.db',
         ),
         saveCompleter: saveCompleter,
         pinCompleter: pinCompleter,
         saveCalled: saveCalled,
         pinCalled: pinCalled,
         initialSettings: initialSettings,
         saveError: saveError,
       );

  _FakeCompanySettingsRepository._(
    OfflineStore store, {
    this.saveCompleter,
    this.pinCompleter,
    this.saveCalled,
    this.pinCalled,
    CompanySettings? initialSettings,
    this.saveError,
  }) : _store = store,
       _settings = initialSettings ?? CompanySettings.empty(),
       super(Dio(), SyncQueueService(store));

  final OfflineStore _store;
  CompanySettings _settings;
  final Completer<bool>? saveCompleter;
  final Completer<AdminAuthorizationVerification>? pinCompleter;
  final Completer<void>? saveCalled;
  final Completer<void>? pinCalled;
  final Object? saveError;
  CompanySettings? lastSavedSettings;

  Future<void> close() => _store.closeForTesting();

  @override
  Future<CompanySettings> getSettings() async => _settings;

  @override
  Future<bool> saveSettingsOrQueue(CompanySettings settings) {
    final called = saveCalled;
    if (called != null && !called.isCompleted) called.complete();
    lastSavedSettings = settings;
    final error = saveError;
    if (error != null) return Future.error(error);
    final completer = saveCompleter;
    if (completer != null) return completer.future;
    _settings = settings;
    return Future.value(false);
  }

  @override
  Future<AdminAuthorizationVerification> verifyAdminAuthorizationPin(
    String pin, {
    required String scope,
  }) {
    final called = pinCalled;
    if (called != null && !called.isCompleted) called.complete();
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

int _storeCounter = 0;

int _nextStoreId() => _storeCounter++;

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
  CompanySettings? initialSettings,
  String userRole = 'ADMIN',
}) async {
  final settings = initialSettings ?? CompanySettings.empty();
  SharedPreferences.setMockInitialValues({});
  tester.view.physicalSize = viewport;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final fakeCompanyRepository =
      companyRepository is _FakeCompanySettingsRepository
      ? companyRepository
      : null;
  if (fakeCompanyRepository != null) {
    addTearDown(fakeCompanyRepository.close);
  }

  final router = GoRouter(
    initialLocation: initialLocation,
    routes: [
      GoRoute(path: Routes.planes, builder: (_, __) => const Scaffold(body: Text('Destino de planes'))),
      GoRoute(path: Routes.apps, builder: (_, __) => const Scaffold(body: Text('Destino de apps'))),
      GoRoute(path: Routes.actualizaciones, builder: (_, __) => const Scaffold(body: Text('Destino de actualizaciones'))),
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
        path: Routes.configuracionParametros,
        builder: (_, __) => const AccountParametersScreen(),
      ),
    ],
  );
  addTearDown(router.dispose);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        activationControllerProvider.overrideWith(
          InactiveActivationController.new,
        ),
        companySettingsProvider.overrideWith((_) async => settings),
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

Finder _companySettingSwitch(String title) =>
    find.byKey(ValueKey('company_setting_switch_$title'));

bool _companySettingSwitchValue(WidgetTester tester, String title) =>
    tester.widget<CompactSquareSwitch>(_companySettingSwitch(title)).value;

void main() {
  testWidgets('native settings uses neutral rows and preserves company app and plans destinations', (tester) async {
    final router = await _pumpSettingsRouter(tester, viewport: const Size(390, 844));
    for (final label in ['Empresa', 'Impresora', 'App y actualizaciones', 'Apps de la empresa', 'Planes', 'Atajos de teclado', 'Eliminar cuenta']) {
      expect(find.byKey(ValueKey('phone-settings-row-$label')), findsOneWidget);
    }
    await tester.tap(find.text('Planes'));
    await _settleSettingsFrame(tester);
    expect(find.text('Destino de planes'), findsOneWidget);
    router.go(Routes.configuracion);
    await _settleSettingsFrame(tester);
    await tester.tap(find.text('App y actualizaciones', findRichText: false));
    await _settleSettingsFrame(tester);
    expect(find.text('Destino de actualizaciones'), findsOneWidget);
    router.go(Routes.configuracion);
    await _settleSettingsFrame(tester);
    await tester.tap(find.text('Apps de la empresa'));
    await _settleSettingsFrame(tester);
    expect(find.text('Destino de apps'), findsOneWidget);
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant({TargetPlatform.android, TargetPlatform.iOS}));

  testWidgets(
    'guardar datos principales conserva los campos ocultos y permite RNC y representante vacíos',
    (tester) async {
      final initial = CompanySettings.empty().copyWith(
        companyName: 'Empresa de prueba',
        rnc: '',
        legalRepresentativeName: '',
        legalRepresentativeCedula: '',
        phone: '8095550100',
        ecfContactEmail: 'fiscal@example.test',
        phonePreferential: '8095550200',
        businessHours: 'Lunes a viernes',
        description: 'Descripción conservada',
        websiteUrl: 'https://example.test',
        legalRepresentativeRole: 'Administrador',
        legalRepresentativeNationality: 'Dominicana',
        bankAccounts: const [
          BankAccountEntry(
            name: 'Principal',
            accountNumber: 'cuenta-ficticia-1',
          ),
          BankAccountEntry(
            name: 'Secundaria',
            accountNumber: 'cuenta-ficticia-2',
          ),
        ],
      );
      final repository = _FakeCompanySettingsRepository(
        initialSettings: initial,
      );
      await _pumpSettingsRouter(
        tester,
        initialLocation: Routes.configuracionEmpresa,
        initialSettings: initial,
        companyRepository: repository,
        viewport: const Size(1264, 681),
      );
      expect(
        find.byKey(
          const ValueKey('company_field_Correo de facturación electrónica'),
        ),
        findsNothing,
      );
      await tester.enterText(
        find.byKey(const ValueKey('company_field_Teléfono principal')),
        '8095550300',
      );
      await tester.ensureVisible(find.text('Guardar empresa'));
      await tester.tap(find.text('Guardar empresa').hitTestable());
      await _settleSettingsFrame(tester);
      if (find.text('Autorizar').evaluate().isNotEmpty) {
        await tester.enterText(find.byType(TextField).last, '1234');
        await tester.tap(find.text('Autorizar'));
        await _settleSettingsFrame(tester);
      }
      final saved = repository.lastSavedSettings!;
      expect(saved.phone, '8095550300');
      expect(saved.rnc, isEmpty);
      expect(saved.legalRepresentativeName, isEmpty);
      expect(saved.legalRepresentativeCedula, isEmpty);
      expect(saved.ecfContactEmail, initial.ecfContactEmail);
      expect(saved.phonePreferential, initial.phonePreferential);
      expect(saved.businessHours, initial.businessHours);
      expect(saved.description, initial.description);
      expect(saved.websiteUrl, initial.websiteUrl);
      expect(saved.legalRepresentativeRole, initial.legalRepresentativeRole);
      expect(
        saved.legalRepresentativeNationality,
        initial.legalRepresentativeNationality,
      );
      expect(
        saved.bankAccounts.map((bank) => bank.toMap()),
        initial.bankAccounts.map((bank) => bank.toMap()),
      );
      expect(tester.takeException(), isNull);
    },
  );

  test('settings error mapper hides technical ApiException formatting', () {
    final message = CompanySettingsFeedback.failure(
      CompanySettings.empty().copyWith(measurementUnitsEnabled: true),
      CompanySettings.empty().copyWith(measurementUnitsEnabled: false),
      ApiException(
        'No se puede desactivar unidades de medida mientras existan productos con unidades distintas de Unidad.',
        400,
      ),
    );

    expect(message.title, 'No se pueden desactivar las unidades de medida');
    expect(message.body, contains('Cambia esos productos a Unidad'));
    expect(message.body, isNot(contains('ApiException')));
    expect(message.body, isNot(contains('400')));
  });

  test('unexpected settings error uses friendly fallback', () {
    final message = CompanySettingsFeedback.failure(
      CompanySettings.empty().copyWith(taxEnabled: false),
      CompanySettings.empty().copyWith(taxEnabled: true),
      Exception('DioException: endpoint /settings failed with status 500'),
    );

    expect(message.title, 'No pudimos guardar el cambio');
    expect(message.body, contains('Inténtalo nuevamente'));
    expect(message.body, isNot(contains('DioException')));
    expect(message.body, isNot(contains('/settings')));
  });

  test('settings success titles cover activation and deactivation labels', () {
    final base = CompanySettings.empty();

    expect(
      CompanySettingsFeedback.success(
        base.copyWith(inventoryEnabled: false),
        base.copyWith(inventoryEnabled: true),
      ).title,
      'Control de inventario activado',
    );
    expect(
      CompanySettingsFeedback.success(
        base.copyWith(inventoryEnabled: true),
        base.copyWith(inventoryEnabled: false),
      ).title,
      'Control de inventario desactivado',
    );
    expect(
      CompanySettingsFeedback.success(
        base.copyWith(measurementUnitsEnabled: false),
        base.copyWith(measurementUnitsEnabled: true),
      ).title,
      'Unidades de medida activadas',
    );
    expect(
      CompanySettingsFeedback.success(
        base.copyWith(measurementUnitsEnabled: true),
        base.copyWith(measurementUnitsEnabled: false),
      ).title,
      'Unidades de medida desactivadas',
    );
    expect(
      CompanySettingsFeedback.success(
        base.copyWith(multiWarehouseEnabled: false),
        base.copyWith(multiWarehouseEnabled: true),
      ).title,
      'Múltiples almacenes activados',
    );
    expect(
      CompanySettingsFeedback.success(
        base.copyWith(multiWarehouseEnabled: true),
        base.copyWith(multiWarehouseEnabled: false),
      ).title,
      'Múltiples almacenes desactivados',
    );
    expect(
      CompanySettingsFeedback.success(
        base.copyWith(taxEnabled: false),
        base.copyWith(taxEnabled: true),
      ).title,
      'Impuestos activados',
    );
    expect(
      CompanySettingsFeedback.success(
        base.copyWith(taxEnabled: true),
        base.copyWith(taxEnabled: false),
      ).title,
      'Impuestos desactivados',
    );
    expect(
      CompanySettingsFeedback.success(
        base.copyWith(taxEnabled: true, ncfEnabled: false),
        base.copyWith(taxEnabled: true, ncfEnabled: true),
      ).title,
      'Comprobantes fiscales activados',
    );
    expect(
      CompanySettingsFeedback.success(
        base.copyWith(taxEnabled: true, ncfEnabled: true),
        base.copyWith(taxEnabled: true, ncfEnabled: false),
      ).title,
      'Comprobantes fiscales desactivados',
    );
  });

  testWidgets(
    'inventory setting requires confirmation and saves only after confirm',
    (tester) async {
      final repository = _FakeCompanySettingsRepository(
        initialSettings: CompanySettings.empty().copyWith(
          companyName: 'FULLTECH',
          inventoryEnabled: true,
        ),
      );
      await _pumpSettingsRouter(
        tester,
        initialLocation: Routes.configuracionEmpresa,
        viewport: const Size(1366, 1600),
        companyRepository: repository,
        initialSettings: CompanySettings.empty().copyWith(
          companyName: 'FULLTECH',
          inventoryEnabled: true,
        ),
      );

      final inventorySwitch = _companySettingSwitch('Control de inventario');
      await tester.ensureVisible(inventorySwitch);
      await tester.tap(find.text('Control de inventario'));
      await tester.pumpAndSettle();

      expect(find.text('Desactivar control de inventario'), findsOneWidget);
      expect(
        find.textContaining('El inventario actual se conservará'),
        findsOneWidget,
      );
      await tester.tap(find.text('Cancelar').last);
      await tester.pumpAndSettle();
      expect(
        _companySettingSwitchValue(tester, 'Control de inventario'),
        isTrue,
      );
      expect(repository.lastSavedSettings, isNull);

      await tester.tap(inventorySwitch);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Desactivar').last);
      await tester.pumpAndSettle();
      expect(
        _companySettingSwitchValue(tester, 'Control de inventario'),
        isFalse,
      );

      final save = find.text('Guardar empresa');
      await tester.ensureVisible(save);
      await tester.tap(save.hitTestable());
      await _settleSettingsFrame(tester);

      expect(repository.lastSavedSettings?.inventoryEnabled, isFalse);
      expect(find.text('Control de inventario desactivado'), findsOneWidget);
      expect(find.textContaining('DioException'), findsNothing);
    },
  );

  testWidgets('persistent notification remains until closed with X', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () => AppFeedback.showPersistentNotification(
                  context,
                  const AppFeedbackNotification(
                    title: 'Unidades de medida activadas',
                    body: 'La configuración se guardó correctamente.',
                    kind: AppFeedbackKind.success,
                  ),
                ),
                child: const Text('Mostrar'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Mostrar'));
    await tester.pump();

    expect(
      find.byKey(const ValueKey('persistent_feedback_card')),
      findsOneWidget,
    );
    expect(find.text('Unidades de medida activadas'), findsOneWidget);

    await tester.pump(const Duration(seconds: 30));
    expect(
      find.byKey(const ValueKey('persistent_feedback_card')),
      findsOneWidget,
    );

    await tester.tap(closeFeedbackButton());
    await tester.pump();
    expect(
      find.byKey(const ValueKey('persistent_feedback_card')),
      findsNothing,
    );
  });

  testWidgets('dispose during fiscal company save does not use WidgetRef', (
    tester,
  ) async {
    final saveCompleter = Completer<bool>();
    final saveCalled = Completer<void>();
    await _pumpSettingsRouter(
      tester,
      initialLocation: Routes.configuracionEmpresa,
      viewport: const Size(1366, 1600),
      companyRepository: _FakeCompanySettingsRepository(
        saveCompleter: saveCompleter,
        saveCalled: saveCalled,
      ),
    );

    await tester.enterText(
      find.byKey(const ValueKey('company_field_Nombre comercial')),
      'FULLTECH',
    );
    await tester.pump();

    final saveButton = find.text('Guardar empresa');
    await tester.ensureVisible(saveButton);
    await tester.tap(saveButton.hitTestable());
    await tester.pump();

    await saveCalled.future;
    expect(saveCompleter.isCompleted, isFalse);

    await tester.pumpWidget(const SizedBox.shrink());
    saveCompleter.complete(false);
    await _settleSettingsFrame(tester);

    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'blocked measurement unit disable shows friendly persistent notification and restores toggle',
    (tester) async {
      final initialSettings = CompanySettings.empty().copyWith(
        companyName: 'FULLTECH',
        measurementUnitsEnabled: true,
      );
      await _pumpSettingsRouter(
        tester,
        initialLocation: Routes.configuracionEmpresa,
        viewport: const Size(1366, 1600),
        initialSettings: initialSettings,
        companyRepository: _FakeCompanySettingsRepository(
          initialSettings: initialSettings,
          saveError: ApiException(
            'No se puede desactivar unidades de medida mientras existan productos con unidades distintas de Unidad.',
            400,
          ),
        ),
      );

      final unitsSwitch = _companySettingSwitch('Activar unidades de medida');
      await tester.ensureVisible(unitsSwitch);
      await tester.tap(unitsSwitch);
      await tester.pump();
      await tester.tap(find.text('Guardar empresa').hitTestable());
      await _settleSettingsFrame(tester);

      expect(
        find.text('No se pueden desactivar las unidades de medida'),
        findsOneWidget,
      );
      expect(find.textContaining('ApiException'), findsNothing);
      expect(find.textContaining('code: 400'), findsNothing);
      expect(
        _companySettingSwitchValue(tester, 'Activar unidades de medida'),
        isTrue,
      );
    },
  );

  testWidgets('successful covered setting change shows customer feedback', (
    tester,
  ) async {
    final initialSettings = CompanySettings.empty().copyWith(
      companyName: 'FULLTECH',
      taxEnabled: false,
    );
    await _pumpSettingsRouter(
      tester,
      initialLocation: Routes.configuracionEmpresa,
      viewport: const Size(1366, 1600),
      initialSettings: initialSettings,
      companyRepository: _FakeCompanySettingsRepository(
        initialSettings: initialSettings,
      ),
    );

    final taxesSwitch = _companySettingSwitch('Activar múltiples almacenes');
    await tester.ensureVisible(taxesSwitch);
    await tester.tap(taxesSwitch);
    await tester.pump();
    await tester.tap(find.text('Guardar empresa').hitTestable());
    await _settleSettingsFrame(tester);

    expect(find.text('Múltiples almacenes activados'), findsOneWidget);
    expect(
      find.text('La configuración se guardó correctamente.'),
      findsOneWidget,
    );
  });

  testWidgets('dispose during admin PIN validation does not use WidgetRef', (
    tester,
  ) async {
    final pinCompleter = Completer<AdminAuthorizationVerification>();
    final pinCalled = Completer<void>();
    await _pumpSettingsRouter(
      tester,
      initialLocation: Routes.configuracionEmpresa,
      viewport: const Size(1366, 1600),
      userRole: 'CAJERO',
      companyRepository: _FakeCompanySettingsRepository(
        pinCompleter: pinCompleter,
        pinCalled: pinCalled,
      ),
    );

    await tester.enterText(
      find.byKey(const ValueKey('company_field_Nombre comercial')),
      'FULLTECH',
    );
    await tester.pump();

    final saveButton = find.text('Guardar empresa');
    await tester.ensureVisible(saveButton);
    await tester.tap(saveButton.hitTestable());
    await _settleSettingsFrame(tester);

    await tester.enterText(find.byType(TextField).last, '1234');
    await tester.tap(find.text('Autorizar').hitTestable());
    await tester.pump();

    await pinCalled.future;
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
      'await repository.verifyAdminAuthorizationPin(',
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

  const targets = <String, String>{'Impresora': 'Impresión y tickets'};

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
      expect(find.text('Impresora').hitTestable(), findsWidgets);
    });
  }

  testWidgets('mobile settings hub documents implemented Windows shortcuts', (
    tester,
  ) async {
    await _pumpSettingsRouter(tester);

    await tester.tap(find.text('Atajos de teclado').hitTestable().first);
    await tester.pumpAndSettle();

    expect(find.text('Atajos de teclado'), findsWidgets);
    expect(
      find.text('Usa estos atajos en Facturacion para trabajar mas rapido.'),
      findsOneWidget,
    );
    for (final keyLabel in [
      'F1',
      'F2',
      'F3',
      'F4',
      'F5',
      'F6',
      'Esc',
      'Delete',
      '+',
      '-',
      'Enter',
    ]) {
      expect(find.text(keyLabel), findsOneWidget);
    }
    expect(find.text('F7'), findsNothing);
    expect(find.text('Ctrl+P'), findsNothing);
    expect(
      find.text(
        'Los atajos funcionan en la aplicacion de Windows y respetan los permisos y confirmaciones configurados.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('settings uses back on native phones and keeps the Windows menu', (
    tester,
  ) async {
    await _pumpSettingsRouter(tester);

    if (defaultTargetPlatform == TargetPlatform.windows) {
      expect(find.byTooltip('Abrir menú'), findsOneWidget);
    } else {
      expect(find.byTooltip('Regresar'), findsOneWidget);
      expect(find.byTooltip('Abrir menú'), findsNothing);
    }
  }, variant: TargetPlatformVariant({TargetPlatform.android, TargetPlatform.iOS, TargetPlatform.windows}));

  testWidgets('mobile settings back button responds across its tap target', (
    tester,
  ) async {
    await _pumpSettingsRouter(tester);

    await tester.tap(find.text('Impresora').hitTestable().first);
    await _settleSettingsFrame(tester);

    final backButton = find.byTooltip('Volver').hitTestable().first;
    final rect = tester.getRect(backButton);
    expect(rect.width, greaterThanOrEqualTo(48));
    expect(rect.height, greaterThanOrEqualTo(48));
  });

  testWidgets('mobile settings back button navigates from semantic button', (
    tester,
  ) async {
    await _pumpSettingsRouter(tester);

    await tester.tap(find.text('Impresora').hitTestable().first);
    await _settleSettingsFrame(tester);

    await tester.tap(find.byTooltip('Volver').hitTestable().first);
    await _settleSettingsFrame(tester);

    expect(tester.takeException(), isNull);
    expect(find.text('Impresora').hitTestable(), findsWidgets);
  });

  const desktopTargets = <String, String>{
    Routes.configuracionEmpresa: 'Datos de la empresa',
    Routes.configuracionDocumentos: 'Datos para documentos',
    Routes.configuracionImpresora: 'Impresión y tickets',
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
