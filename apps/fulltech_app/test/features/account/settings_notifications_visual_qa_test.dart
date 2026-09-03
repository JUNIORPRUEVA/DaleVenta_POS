// SETTINGS-NOTIFICATIONS-01 — Visual QA evidence (non-production, no network).
//
// This test renders the REAL persistent notification presenter
// (AppFeedback.showPersistentNotification -> _PersistentFeedbackCard) and the
// REAL company settings editor screen, at desktop and narrow/mobile widths,
// with real Manrope fonts loaded so captured PNGs are readable.
//
// The repository boundary is faked on purpose: no HTTP, no database, no
// production endpoint is ever contacted. Business rejection messages used are
// the exact strings the backend settings service returns
// (apps/api/src/settings/settings.service.ts) so the error mapper is exercised
// against real contracts.
//
// Captured evidence is written under docs/settings-notifications-visual-evidence.
// Run only this file when you want to (re)generate evidence:
//   flutter test test/features/account/settings_notifications_visual_qa_test.dart
//
// ignore_for_file: avoid_print

import 'dart:io';
import 'dart:ui' as ui;

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
import 'package:daleventa_pos/core/theme/app_colors.dart';
import 'package:daleventa_pos/core/utils/app_feedback.dart';
import 'package:daleventa_pos/features/account/account_menu_screens.dart';
import 'package:daleventa_pos/features/settings/data/mobile_printer_settings_model.dart';
import 'package:daleventa_pos/features/settings/data/mobile_printer_settings_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _outDir = '../../docs/settings-notifications-visual-evidence';

// ---- Fonts -----------------------------------------------------------------

Future<void> _loadFonts() async {
  Future<void> loadFile(String path, String family) async {
    final bytes = File(path).readAsBytesSync();
    final data = ByteData.view(bytes.buffer);
    final loader = FontLoader(family)..addFont(Future.value(data));
    await loader.load();
  }

  await loadFile('assets/fonts/manrope/Manrope-Regular.ttf', 'Manrope');
  await loadFile('assets/fonts/manrope/Manrope-Medium.ttf', 'Manrope');
  await loadFile('assets/fonts/manrope/Manrope-SemiBold.ttf', 'Manrope');
  await loadFile('assets/fonts/manrope/Manrope-Bold.ttf', 'Manrope');
}

// ---- Capture helpers --------------------------------------------------------

Future<void> _setViewport(WidgetTester tester, Size size) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _shot(WidgetTester tester, String name) async {
  await tester.pump(const Duration(milliseconds: 350));
  await tester.runAsync(() async {
    final binding = TestWidgetsFlutterBinding.instance;
    final renderView = binding.renderViews.first;
    // ignore: invalid_use_of_protected_member
    final layer = renderView.layer! as OffsetLayer;
    final image = await layer.toImage(renderView.paintBounds);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    final dir = Directory(_outDir);
    if (!dir.existsSync()) dir.createSync(recursive: true);
    File('${dir.path}/$name.png')
        .writeAsBytesSync(data!.buffer.asUint8List());
  });
}

// ---- Host scaffold used to show the real persistent notification card -------

class _NotificationHost extends StatelessWidget {
  const _NotificationHost({
    required this.buttonLabel,
    required this.notification,
  });

  final String buttonLabel;
  final AppFeedbackNotification notification;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: ThemeData(fontFamily: 'Manrope'),
      home: Builder(
        builder: (context) => Scaffold(
          backgroundColor: AppColors.background,
          body: Center(
            child: FilledButton(
              onPressed: () => AppFeedback.showPersistentNotification(
                context,
                notification,
                scope: 'settings_notifications_visual_qa',
              ),
              child: Text(buttonLabel),
            ),
          ),
        ),
      ),
    );
  }
}

// ---- Real settings screen harness (mirrors navigation tests) ----------------

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

int _storeCounter = 0;
int _nextStoreId() => _storeCounter++;

class _FakeCompanySettingsRepository extends CompanySettingsRepository {
  _FakeCompanySettingsRepository({
    CompanySettings? initialSettings,
    Object? saveError,
  }) : this._(
         OfflineStore.forTesting(
           'settings_notifications_visual_qa_${_nextStoreId()}.db',
         ),
         initialSettings: initialSettings,
         saveError: saveError,
       );

  _FakeCompanySettingsRepository._(
    OfflineStore store, {
    CompanySettings? initialSettings,
    Object? saveError,
  }) : _store = store,
       _settings = initialSettings ?? CompanySettings.empty(),
       _saveError = saveError,
       super(Dio(), SyncQueueService(store));

  final OfflineStore _store;
  CompanySettings _settings;
  final Object? _saveError;

  Future<void> close() => _store.closeForTesting();

  @override
  Future<CompanySettings> getSettings() async => _settings;

  @override
  Future<bool> saveSettingsOrQueue(CompanySettings settings) {
    final error = _saveError;
    if (error != null) return Future.error(error);
    _settings = settings;
    return Future.value(false);
  }

  @override
  Future<AdminAuthorizationVerification> verifyAdminAuthorizationPin(
    String pin, {
    required String scope,
  }) {
    return Future.value(
      const AdminAuthorizationVerification(
        duration: Duration(minutes: 5),
        token: 'qa-token',
      ),
    );
  }
}

class _TestAuthController extends AuthController {
  _TestAuthController(super.ref) {
    state = AuthState(
      initialized: true,
      isAuthenticated: true,
      user: UserModel(
        id: 'u-qa',
        email: 'qa@example.com',
        nombreCompleto: 'QA User',
        telefono: '',
        role: 'ADMIN',
        companyId: 'company-qa',
        companyName: 'FullPOS QA',
      ),
    );
  }
}

Future<void> _pumpCompanySettingsScreen(
  WidgetTester tester, {
  required Size viewport,
  required CompanySettings initialSettings,
  Object? saveError,
}) async {
  SharedPreferences.setMockInitialValues({});
  await _setViewport(tester, viewport);
  final repository = _FakeCompanySettingsRepository(
    initialSettings: initialSettings,
    saveError: saveError,
  );
  addTearDown(repository.close);

  final router = GoRouter(
    initialLocation: Routes.configuracionEmpresa,
    routes: [
      GoRoute(
        path: Routes.configuracion,
        builder: (_, __) => const AccountSettingsScreen(),
      ),
      GoRoute(
        path: Routes.configuracionEmpresa,
        builder: (_, __) => const AccountCompanySettingsScreen(),
      ),
    ],
  );
  addTearDown(router.dispose);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        companySettingsProvider.overrideWith((_) async => initialSettings),
        companySettingsRepositoryProvider.overrideWithValue(repository),
        authStateProvider.overrideWith((ref) => _TestAuthController(ref)),
        printingPlatformResolverProvider.overrideWithValue(
          const _FakePrintingPlatformResolver(PrintingPlatform.android),
        ),
        mobilePrinterSettingsRepositoryProvider.overrideWithValue(
          _FakeMobilePrinterSettingsRepository(),
        ),
      ],
      child: MaterialApp.router(
        theme: ThemeData(fontFamily: 'Manrope'),
        routerConfig: router,
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 120));
  await tester.pump(const Duration(milliseconds: 120));
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 160));
  await tester.pump(const Duration(milliseconds: 160));
}

// ---- Tests ------------------------------------------------------------------

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await binding.runAsync(() => _loadFonts());
  });

  group('persistent notification card visual QA', () {
    final cases = <String, AppFeedbackNotification>{
      'success-taxes': CompanySettingsFeedback.success(
        CompanySettings.empty().copyWith(taxEnabled: false),
        CompanySettings.empty().copyWith(taxEnabled: true),
      ),
      'warning-units-rejected': CompanySettingsFeedback.failure(
        CompanySettings.empty().copyWith(measurementUnitsEnabled: true),
        CompanySettings.empty().copyWith(measurementUnitsEnabled: false),
        ApiException(
          'No se puede desactivar unidades de medida mientras existan productos con unidades distintas de Unidad.',
          400,
        ),
      ),
      'error-fallback': const AppFeedbackNotification(
        title: 'No pudimos guardar el cambio',
        body:
            'Ocurrió un problema al actualizar esta configuración. Inténtalo nuevamente.',
        kind: AppFeedbackKind.error,
      ),
    };

    for (final entry in cases.entries) {
      for (final size in const [Size(1366, 768), Size(390, 844)]) {
        final suffix = size.width > 1000 ? 'desktop' : 'mobile';
        testWidgets('${entry.key} renders at $suffix (${size.width}px)', (
          tester,
        ) async {
          await _setViewport(tester, size);
          await tester.pumpWidget(
            _NotificationHost(
              buttonLabel: 'Mostrar ${entry.key}',
              notification: entry.value,
            ),
          );

          await tester.tap(find.text('Mostrar ${entry.key}'));
          await tester.pump();

          final card = find.byKey(
            const ValueKey('persistent_feedback_card'),
          );
          expect(card, findsOneWidget);
          expect(find.text(entry.value.title), findsOneWidget);
          expect(find.text(entry.value.body), findsOneWidget);
          // No technical leak in the rendered title/body.
          expect(find.textContaining('ApiException'), findsNothing);
          expect(find.textContaining('code: 400'), findsNothing);
          expect(find.textContaining('DioException'), findsNothing);

          // Top-right placement (approved shared notification position).
          final cardRect = tester.getRect(card);
          final margin = size.width < 640 ? 12.0 : 24.0;
          expect(
            cardRect.right,
            greaterThanOrEqualTo(size.width - margin - 4),
            reason: 'card must sit at the top-right (right edge)',
          );
          expect(
            cardRect.right,
            lessThanOrEqualTo(size.width + 1),
            reason: 'card must not overflow the right edge',
          );
          expect(
            cardRect.top,
            greaterThanOrEqualTo(40),
            reason: 'card must sit below the top edge/app bar zone',
          );
          expect(
            cardRect.top,
            lessThanOrEqualTo(160),
            reason: 'card must be near the top (top-right placement)',
          );
          expect(
            cardRect.bottom,
            lessThanOrEqualTo(size.height),
            reason: 'card must not overflow the viewport bottom',
          );

          // X close affordance is present and reachable.
          expect(find.byTooltip('Cerrar notificación'), findsOneWidget);

          // No overflow/clipping of the card at this width.
          expect(tester.takeException(), isNull);

          await _shot(tester, '${entry.key}-$suffix-${size.width.toInt()}');

          // Persists until manually dismissed.
          await tester.pump(const Duration(seconds: 35));
          expect(card, findsOneWidget);

          // X dismisses it.
          await tester.tap(find.byTooltip('Cerrar notificación'));
          await tester.pump();
          expect(card, findsNothing);
          expect(tester.takeException(), isNull);
        });
      }
    }
  });

  group('real company settings screen rejection QA', () {
    testWidgets(
      'blocked units disable shows friendly card, restores toggle (desktop)',
      (tester) async {
        final initial = CompanySettings.empty().copyWith(
          companyName: 'FullPOS QA',
          measurementUnitsEnabled: true,
        );
        await _pumpCompanySettingsScreen(
          tester,
          viewport: const Size(1366, 1600),
          initialSettings: initial,
          saveError: ApiException(
            'No se puede desactivar unidades de medida mientras existan productos con unidades distintas de Unidad.',
            400,
          ),
        );

        final unitsSwitch = find.widgetWithText(
          SwitchListTile,
          'Activar unidades de medida',
        );
        await tester.ensureVisible(unitsSwitch);
        await tester.tap(unitsSwitch);
        await tester.pump();

        final save = find.text('Guardar empresa');
        await tester.ensureVisible(save);
        await tester.tap(save.hitTestable());
        await _settle(tester);

        expect(
          find.text('No se pueden desactivar las unidades de medida'),
          findsOneWidget,
        );
        expect(find.textContaining('ApiException'), findsNothing);
        expect(find.textContaining('code: 400'), findsNothing);
        expect(
          find.byKey(const ValueKey('persistent_feedback_card')),
          findsOneWidget,
        );
        final tile = tester.widget<SwitchListTile>(unitsSwitch);
        expect(
          tile.value,
          isTrue,
          reason: 'toggle restored to persisted state',
        );
        expect(tester.takeException(), isNull);

        await _shot(tester, 'settings-screen-units-rejected-desktop');
      },
    );

    testWidgets(
      'real units-rejection notification overlays the screen at mobile width without overflow',
      (tester) async {
        final initial = CompanySettings.empty().copyWith(
          companyName: 'FullPOS QA',
          measurementUnitsEnabled: true,
        );
        await _pumpCompanySettingsScreen(
          tester,
          viewport: const Size(390, 844),
          initialSettings: initial,
        );

        // Show the exact rejection notification the app would produce through
        // the real presenter, layered over the real screen at a narrow width.
        final screenContext = tester.element(
          find.byType(AccountCompanySettingsScreen),
        );
        AppFeedback.showPersistentNotification(
          screenContext,
          CompanySettingsFeedback.failure(
            initial,
            initial.copyWith(measurementUnitsEnabled: false),
            ApiException(
              'No se puede desactivar unidades de medida mientras existan productos con unidades distintas de Unidad.',
              400,
            ),
          ),
          scope: 'company_settings',
        );
        await _settle(tester);

        expect(
          find.text('No se pueden desactivar las unidades de medida'),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('persistent_feedback_card')),
          findsOneWidget,
        );
        expect(find.byTooltip('Cerrar notificación'), findsOneWidget);
        expect(tester.takeException(), isNull);

        // Capture with the card visible over the narrow real screen.
        await _shot(tester, 'settings-screen-units-rejected-mobile');

        // X is reachable on a narrow screen and closes the card.
        await tester.tap(find.byTooltip('Cerrar notificación'));
        await tester.pump();
        expect(
          find.byKey(const ValueKey('persistent_feedback_card')),
          findsNothing,
        );
        expect(tester.takeException(), isNull);

        // Capture the closed state as well.
        await _shot(tester, 'settings-screen-units-rejected-mobile-closed');
      },
    );
  });

  group('known business rejection mappings QA', () {
    test('multi-warehouse disable rejection maps to friendly Spanish', () {
      final message = CompanySettingsFeedback.failure(
        CompanySettings.empty().copyWith(multiWarehouseEnabled: true),
        CompanySettings.empty().copyWith(multiWarehouseEnabled: false),
        ApiException(
          'No se puede desactivar multiples almacenes mientras existan productos con stock distribuido en mas de un almacen activo.',
          400,
        ),
      );

      expect(message.title, 'No se pueden desactivar los múltiples almacenes');
      expect(message.body, contains('stock en un solo almacén'));
      expect(message.body, isNot(contains('ApiException')));
      expect(message.body, isNot(contains('400')));
    });

    test('tax activation invalid-default rejection maps to friendly Spanish', () {
      final message = CompanySettingsFeedback.failure(
        CompanySettings.empty().copyWith(taxEnabled: false),
        CompanySettings.empty().copyWith(taxEnabled: true),
        ApiException('Impuesto predeterminado invalido', 400),
      );

      expect(message.title, 'No se pudo activar impuestos');
      expect(message.body, isNot(contains('ApiException')));
      expect(message.body, isNot(contains('400')));
    });

    test('multi-warehouse and NCF covered toggles get success titles', () {
      final base = CompanySettings.empty();
      expect(
        CompanySettingsFeedback.success(
          base.copyWith(multiWarehouseEnabled: true),
          base.copyWith(multiWarehouseEnabled: false),
        ).title,
        'Múltiples almacenes desactivados',
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
  });
}
