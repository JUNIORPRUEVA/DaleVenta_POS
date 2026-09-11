import 'dart:io';

import 'package:daleventa_pos/core/auth/auth_provider.dart';
import 'package:daleventa_pos/core/company/company_settings_model.dart';
import 'package:daleventa_pos/core/company/company_settings_repository.dart';
import 'package:daleventa_pos/core/models/user_model.dart';
import 'package:daleventa_pos/core/printing/unified_ticket_printer.dart';
import 'package:daleventa_pos/core/routing/app_route_observer.dart';
import 'package:daleventa_pos/core/routing/routes.dart';
import 'package:daleventa_pos/core/tax/product_tax_options_provider.dart';
import 'package:daleventa_pos/core/utils/build_phase.dart';
import 'package:daleventa_pos/core/widgets/app_drawer.dart';
import 'package:daleventa_pos/features/account/account_menu_screens.dart';
import 'package:daleventa_pos/modules/cash/cash_close_ticket_printer.dart';
import 'package:daleventa_pos/modules/cash/cash_models.dart';
import 'package:daleventa_pos/modules/cash/cash_providers.dart';
import 'package:daleventa_pos/modules/cash/cash_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Regresión del defecto reportado en móvil:
///
/// `setState() or markNeedsBuild() called during build`
///   - widget afectado: `AccountSettingsScreen`
///   - widget construyéndose: `AppDrawer`
///   - cadena: `buildAppNavigationSections` → Riverpod `ref.watch`
///
/// Causa raíz: `RouteObserver.subscribe()` (invocado desde
/// `didChangeDependencies`, fase de build) ejecuta `RouteAware.didPush()`
/// sincrónicamente; éste invalidaba `companySettingsProvider` **durante el
/// build**. Riverpod reconstruye un provider invalidado de forma sincrónica en
/// el primer `ref.watch` del mismo frame (`readSelf` → `flush`) y notifica a
/// TODOS sus listeners, marcando como "necesita build" a widgets que no son
/// descendientes del widget que está leyendo.
///
/// El flujo móvil es el que lo dispara porque en móvil la navegación es por
/// drawer (`_SettingsHubScaffold` → `Scaffold.drawer` → `AppDrawer`, que observa
/// la configuración de empresa y es descendiente de `AccountSettingsScreen`).
class _FixedAuthController extends AuthController {
  _FixedAuthController(super.ref, AuthState fixedState) {
    state = fixedState;
  }
}

UserModel _adminUser() => UserModel(
  id: 'user-a',
  email: 'admin@test.local',
  nombreCompleto: 'Admin Test',
  telefono: '',
  role: 'ADMIN',
  companyId: 'company-a',
  companyName: 'FULLTECH, SRL',
);

class _CashRepo implements CashRepository {
  @override
  bool lastStateFromCache = false;

  @override
  void registerSyncHandlers() {}

  @override
  Future<CashGateState> state() async =>
      const CashGateState(businessDate: '2026-08-22', canOperate: true);

  @override
  Future<ActiveCashSession> openSession({
    required double openingAmount,
    String? note,
  }) async => throw UnimplementedError();

  @override
  Future<void> closeSession({
    required double closingAmount,
    String? note,
  }) async {}

  @override
  Future<CashSummaryModel> summary() async => throw UnimplementedError();

  @override
  Future<List<CashMovementModel>> movements() async => const [];

  @override
  Future<List<CashMovementModel>> movementHistory({
    String? type,
    String? movementType,
    DateTime? from,
    DateTime? to,
    int take = 160,
  }) async => const [];

  @override
  Future<List<CashSessionHistoryModel>> closedSessions() async => const [];

  @override
  Future<CashSessionDetailModel> sessionDetail(String id) =>
      throw UnimplementedError();

  @override
  Future<void> addMovement({
    required String type,
    required double amount,
    required String reason,
    String movementType = 'expense',
    bool? affectsProfit,
  }) async {}
}

class _Printer implements CashCloseTicketPrinter {
  @override
  Future<PrintTicketResult> printCloseTicket(
    CashCloseTicketSnapshot snapshot, {
    bool automatic = true,
  }) async => const PrintTicketResult(success: true, message: 'ok');

  @override
  Future<PrintTicketResult> printHistoryTicket(CashSessionHistoryModel row) =>
      throw UnimplementedError();

  @override
  List<String> buildLines(CashCloseTicketSnapshot snapshot) => const [];

  @override
  List<String> buildHistoryLines(CashSessionHistoryModel row) => const [];
}

class _SettingsHolder {
  _SettingsHolder(this.value);

  CompanySettings value;
}

/// Réplica del patrón real de `CatalogoScreen`/`CotizacionesScreen`/
/// `RegistrarVentaScreen`: suscribirse al `RouteObserver` en
/// `didChangeDependencies` y refrescar configuración en `didPush`/`didPopNext`
/// usando `runOutsideBuildPhase` (la corrección aplicada).
class _RouteEntryScreen extends ConsumerStatefulWidget {
  const _RouteEntryScreen({required this.onInvalidate});

  final VoidCallback onInvalidate;

  @override
  ConsumerState<_RouteEntryScreen> createState() => _RouteEntryScreenState();
}

class _RouteEntryScreenState extends ConsumerState<_RouteEntryScreen>
    with RouteAware {
  RouteObserver<ModalRoute<dynamic>>? _observer;
  bool _subscribed = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _subscribeRouteObserver();
  }

  void _subscribeRouteObserver() {
    if (_subscribed) return;
    final route = ModalRoute.of(context);
    if (route == null) return;
    final observer = ref.read(appRouteObserverProvider);
    observer.subscribe(this, route);
    _observer = observer;
    _subscribed = true;
  }

  void _syncOnEnter() {
    if (!mounted) return;
    runOutsideBuildPhase(() {
      if (!mounted) return;
      ref.invalidate(companySettingsProvider);
      ref.invalidate(productTaxUiConfigProvider);
      widget.onInvalidate();
    });
  }

  @override
  void didPush() => _syncOnEnter();

  @override
  void didPopNext() => _syncOnEnter();

  @override
  void didPushNext() {}

  @override
  void didPop() {}

  @override
  void dispose() {
    _observer?.unsubscribe(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(companySettingsProvider);
    return const Scaffold(body: Center(child: Text('destino-ruta')));
  }
}

class _Harness {
  _Harness(this.container, this.router, this.holder);

  final ProviderContainer container;
  final GoRouter router;
  final _SettingsHolder holder;
}

Future<_Harness> _pumpHub(
  WidgetTester tester, {
  required CompanySettings settings,
  required Size viewport,
  bool withRouteEntryDestination = false,
  VoidCallback? onInvalidate,
}) async {
  SharedPreferences.setMockInitialValues({});
  tester.view.physicalSize = viewport;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final holder = _SettingsHolder(settings);
  final container = ProviderContainer(
    overrides: [
      authStateProvider.overrideWith(
        (ref) => _FixedAuthController(
          ref,
          AuthState(
            initialized: true,
            isAuthenticated: true,
            user: _adminUser(),
            loading: false,
            restoringSession: false,
            hasSessionHint: true,
          ),
        ),
      ),
      cashRepositoryProvider.overrideWithValue(_CashRepo()),
      cashCloseTicketPrinterProvider.overrideWithValue(_Printer()),
      companySettingsProvider.overrideWith((ref) async => holder.value),
    ],
  );
  addTearDown(container.dispose);

  final observer = container.read(appRouteObserverProvider);
  final router = GoRouter(
    initialLocation: Routes.configuracion,
    observers: [observer],
    routes: [
      GoRoute(
        path: Routes.configuracion,
        builder: (_, __) => const AccountSettingsScreen(),
      ),
      GoRoute(
        path: Routes.catalogo,
        builder: (_, __) => withRouteEntryDestination
            ? _RouteEntryScreen(onInvalidate: onInvalidate ?? () {})
            : const Scaffold(body: Center(child: Text('destino-ruta'))),
      ),
    ],
  );
  addTearDown(router.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        theme: ThemeData(platform: TargetPlatform.android),
        routerConfig: router,
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 120));

  return _Harness(container, router, holder);
}

Future<void> _openHubDrawer(WidgetTester tester) async {
  final scaffold = find
      .descendant(
        of: find.byType(AccountSettingsScreen),
        matching: find.byType(Scaffold),
      )
      .first;
  tester.state<ScaffoldState>(scaffold).openDrawer();
  await tester.pumpAndSettle();
}

Finder _drawerText(String text) =>
    find.descendant(of: find.byType(AppDrawer), matching: find.text(text));

/// Extrae el cuerpo de un método (miembro de clase, cierre a 2 espacios).
String _methodBody(String source, String signature) {
  final start = source.indexOf(signature);
  expect(start, greaterThanOrEqualTo(0), reason: 'no se encontró $signature');
  final end = source.indexOf('\n  }', start);
  expect(end, greaterThan(start));
  return source.substring(start, end);
}

void main() {
  // Guarda de origen: los puntos que dispararon el defecto en móvil deben
  // seguir difiriendo sus mutaciones de Riverpod fuera de la fase de build.
  group('guarda de origen — sin mutaciones de providers en fase de build', () {
    test('entrada de ruta en cotizaciones usa runOutsideBuildPhase', () {
      final source = File(
        'lib/modules/cotizaciones/cotizaciones_screen.dart',
      ).readAsStringSync();

      final syncBody = _methodBody(source, 'void _syncProductsOnEnter() {');
      expect(syncBody, contains('runOutsideBuildPhase'));
      expect(
        syncBody.indexOf('runOutsideBuildPhase'),
        lessThan(syncBody.indexOf('ref.invalidate(companySettingsProvider)')),
      );

      final lifecycleBody = _methodBody(
        source,
        'void didChangeAppLifecycleState(AppLifecycleState state) {',
      );
      expect(lifecycleBody, contains('runOutsideBuildPhase'));
      expect(
        lifecycleBody.indexOf('runOutsideBuildPhase'),
        lessThan(lifecycleBody.indexOf('ref.invalidate(companySettingsProvider)')),
      );
    });

    test('entrada de ruta en registrar venta usa runOutsideBuildPhase', () {
      final source = File(
        'lib/modules/ventas/registrar_venta_screen.dart',
      ).readAsStringSync();

      final syncBody = _methodBody(source, 'void _syncProductsOnEnter() {');
      expect(syncBody, contains('runOutsideBuildPhase'));
      expect(
        syncBody.indexOf('runOutsideBuildPhase'),
        lessThan(syncBody.indexOf('ref.invalidate(companySettingsProvider)')),
      );
    });

    test('buildAppNavigationSections es pura (sin ref.watch / WidgetRef)', () {
      final source = File(
        'lib/core/widgets/app_navigation.dart',
      ).readAsStringSync();
      // Se ignoran los comentarios: la garantía es sobre el código.
      final code = source.replaceAll(RegExp(r'^\s*///.*$', multiLine: true), '');

      expect(code, isNot(contains('ref.watch(')));
      expect(code, isNot(contains('WidgetRef')));
      expect(code, contains('required bool multiWarehouseEnabled'));
    });
  });

  group('AccountSettingsScreen + AppDrawer — sin markNeedsBuild en build', () {
    testWidgets(
      'CASO REPORTADO (mobile): entrada de ruta que invalida settings en '
      'didChangeDependencies no rompe el drawer',
      (tester) async {
        var invalidations = 0;
        final harness = await _pumpHub(
          tester,
          settings: CompanySettings.empty(),
          viewport: const Size(412, 915),
          withRouteEntryDestination: true,
          onInvalidate: () => invalidations++,
        );

        await _openHubDrawer(tester);
        expect(find.byType(AppDrawer), findsOneWidget);

        // Navegación real móvil desde el drawer: la ruta destino se monta y su
        // `didChangeDependencies` → `RouteObserver.subscribe` → `didPush()`
        // refresca la configuración de empresa.
        harness.router.go(Routes.catalogo);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 16));
        await tester.pump(const Duration(milliseconds: 16));
        await tester.pumpAndSettle();

        // La escena realmente se ejecutó.
        expect(find.text('destino-ruta'), findsOneWidget);
        expect(invalidations, greaterThan(0));
        // Y no hubo excepción durante el build.
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'drawer reactivo: multi-almacenes aparece y desaparece sin excepción',
      (tester) async {
        final harness = await _pumpHub(
          tester,
          settings: CompanySettings.empty(),
          viewport: const Size(412, 915),
        );

        await _openHubDrawer(tester);
        expect(_drawerText('Almacenes'), findsNothing);
        expect(_drawerText('Kardex'), findsNothing);

        // Activar multi-almacenes (equivale a guardar ese toggle en móvil).
        harness.holder.value = harness.holder.value.copyWith(
          multiWarehouseEnabled: true,
        );
        harness.container.invalidate(companySettingsProvider);
        await tester.pump();
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(_drawerText('Almacenes'), findsOneWidget);
        expect(_drawerText('Kardex'), findsOneWidget);

        // Desactivar de nuevo.
        harness.holder.value = harness.holder.value.copyWith(
          multiWarehouseEnabled: false,
        );
        harness.container.invalidate(companySettingsProvider);
        await tester.pump();
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(_drawerText('Almacenes'), findsNothing);
        expect(_drawerText('Kardex'), findsNothing);
      },
    );

    testWidgets('CASO F: cambios consecutivos de flags con el drawer abierto', (
      tester,
    ) async {
      final harness = await _pumpHub(
        tester,
        settings: CompanySettings.empty(),
        viewport: const Size(412, 915),
      );
      await _openHubDrawer(tester);

      final combinations = <CompanySettings>[
        CompanySettings.empty(),
        CompanySettings.empty().copyWith(
          inventoryEnabled: false,
          taxEnabled: true,
          ncfEnabled: true,
          multiWarehouseEnabled: true,
          measurementUnitsEnabled: true,
        ),
        CompanySettings.empty().copyWith(measurementUnitsEnabled: true),
        CompanySettings.empty().copyWith(
          measurementUnitsEnabled: true,
          multiWarehouseEnabled: true,
        ),
        CompanySettings.empty().copyWith(taxEnabled: true, ncfEnabled: true),
        CompanySettings.empty().copyWith(inventoryEnabled: false),
        CompanySettings.empty(),
      ];

      for (final settings in combinations) {
        harness.holder.value = settings;
        harness.container.invalidate(companySettingsProvider);
        await tester.pump();
        await tester.pumpAndSettle();

        expect(
          tester.takeException(),
          isNull,
          reason: 'multiWarehouseEnabled=${settings.multiWarehouseEnabled}',
        );
        expect(
          _drawerText('Almacenes'),
          settings.multiWarehouseEnabled ? findsOneWidget : findsNothing,
        );
      }
    });

    for (final viewport in const [Size(360, 800), Size(412, 915)]) {
      testWidgets(
        'layout móvil ${viewport.width.toInt()}x${viewport.height.toInt()}: '
        'hub + drawer sin excepción',
        (tester) async {
          final harness = await _pumpHub(
            tester,
            settings: CompanySettings.empty().copyWith(
              multiWarehouseEnabled: true,
            ),
            viewport: viewport,
          );

          expect(tester.takeException(), isNull);
          expect(find.text('Configuración'), findsOneWidget);
          expect(find.text('Empresa'), findsWidgets);

          await _openHubDrawer(tester);

          expect(tester.takeException(), isNull);
          expect(find.byType(AppDrawer), findsOneWidget);

          // El drawer permanece estable ante un cambio de estado observado por
          // él (mismo patrón que el refresh de turno en dispositivo real).
          harness.container.read(cashStateUnverifiedProvider.notifier).state =
              true;
          await tester.pump();
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        },
      );
    }
  });
}
