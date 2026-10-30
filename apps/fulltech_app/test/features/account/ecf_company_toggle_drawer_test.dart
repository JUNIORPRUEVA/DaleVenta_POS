import 'dart:io';
import 'dart:typed_data';

import 'package:daleventa_pos/core/auth/app_permissions.dart';
import 'package:daleventa_pos/core/auth/auth_provider.dart';
import 'package:daleventa_pos/core/auth/auth_repository.dart';
import 'package:daleventa_pos/core/company/company_settings_model.dart';
import 'package:daleventa_pos/core/company/company_settings_repository.dart';
import 'package:daleventa_pos/core/models/user_model.dart';
import 'package:daleventa_pos/core/printing/unified_ticket_printer.dart';
import 'package:daleventa_pos/core/routing/routes.dart';
import 'package:daleventa_pos/core/widgets/app_drawer.dart';
import 'package:daleventa_pos/features/account/account_menu_screens.dart';
import 'package:daleventa_pos/features/ecf/data/ecf_repository.dart';
import 'package:daleventa_pos/features/ecf/ecf_models.dart';
import 'package:daleventa_pos/modules/cash/cash_close_ticket_printer.dart';
import 'package:daleventa_pos/modules/cash/cash_models.dart';
import 'package:daleventa_pos/modules/cash/cash_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Prueba FUNCIONAL de la cadena:
///
///   Configuración de empresa → Activar e-CF → Guardar →
///   Aparece en el Drawer → Abrir el módulo → Desactivar → Desaparece.
///
/// Monta la pantalla REAL (`AccountCompanySettingsScreen`), el Drawer REAL
/// (`AppDrawer`, el mismo que sirve `buildAdaptiveDrawer`), el
/// `companySettingsProvider` REAL (con el backend simulado detrás), los
/// permisos reales del usuario y un repositorio e-CF simulado. No hay red.
///
/// El estado que se muestra viene SIEMPRE del backend simulado: el interruptor
/// nunca se pinta de forma optimista.

const _markerModule = 'marcador-modulo-ecf';
const _markerConfig = 'marcador-config-ecf';
const _ecfDrawerLabel = 'Facturación electrónica';
// El interruptor de e-CF dejó de ser una sección independiente: ahora vive
// dentro del bloque fiscal, que se llama «Impuestos y e-CF». La aserción sigue
// verificando que esa sección está en pantalla, solo que con su nombre actual.
const _ecfSectionTitle = 'Impuestos y e-CF';
const _ecfErrorText =
    'No se pudo guardar. Se mantiene el último estado confirmado por el servidor.';

class _FixedAuthController extends AuthController {
  _FixedAuthController(super.ref, AuthState fixedState) {
    state = fixedState;
  }

  void switchCompany(String? companyId, {String? role}) {
    state = AuthState(
      initialized: true,
      isAuthenticated: true,
      user: _user(companyId: companyId, role: role),
      loading: false,
      restoringSession: false,
      hasSessionHint: true,
    );
  }
}

UserModel _user({String? companyId = 'company-a', String? role = 'ADMIN'}) =>
    UserModel(
      id: 'user-a',
      email: 'admin@test.local',
      nombreCompleto: 'Usuario Test',
      telefono: '',
      role: role,
      companyId: companyId,
      companyName: 'Empresa Test',
    );

/// Backend simulado. Es la ÚNICA fuente del interruptor.
class _EcfBackendState {
  _EcfBackendState({required this.enabledByCompany});

  final Map<String, bool> enabledByCompany;
  final List<bool> patchCalls = <bool>[];
  final List<String?> patchCompanies = <String?>[];
  bool failNextPatch = false;

  CompanySettings settingsFor(String? companyId) {
    return CompanySettings.empty().copyWith(
      companyName: 'Empresa ${companyId ?? 'sin-empresa'}',
      // El interruptor de facturación electrónica vive dentro del bloque
      // fiscal y solo se muestra con impuestos activos, que es la única
      // combinación con sentido: sin impuestos no hay nada que facturar
      // electrónicamente. El escenario base refleja esa situación.
      taxEnabled: true,
      ecfEnabled: enabledByCompany[companyId] ?? false,
    );
  }
}

class _FakeEcfRepository extends EcfRepository {
  _FakeEcfRepository(this._backend, this._currentCompanyId) : super(Dio());

  final _EcfBackendState _backend;
  final String? Function() _currentCompanyId;

  static const EcfCapabilities _capabilities = EcfCapabilities(
    enabled: false,
    environment: 'SANDBOX',
    certificationStatus: 'NOT_STARTED',
    productionEnabled: false,
    allowedTypes: <String>[],
    emissionPathAvailable: false,
    documentTypes: <EcfDocumentTypeCapability>[],
  );

  @override
  Future<EcfCapabilities> capabilities() async => _capabilities;

  @override
  Future<void> updateEnabled({required bool enabled}) async {
    _backend.patchCalls.add(enabled);
    _backend.patchCompanies.add(_currentCompanyId());
    if (_backend.failNextPatch) {
      _backend.failNextPatch = false;
      throw DioException(
        requestOptions: RequestOptions(path: '/ecf/config'),
        type: DioExceptionType.connectionError,
        error: 'fallo de red simulado',
      );
    }
    // Confirmación del "servidor": solo aquí cambia el estado observable.
    final companyId = _currentCompanyId();
    _backend.enabledByCompany[companyId ?? 'sin-empresa'] = enabled;
  }
}

/// Dio que registra CUALQUIER petición. La navegación no debe emitir ninguna.
class _RecordingAdapter implements HttpClientAdapter {
  _RecordingAdapter(this.calls);

  final List<String> calls;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    calls.add('${options.method} ${options.uri}');
    return ResponseBody.fromString('{}', 500);
  }

  @override
  void close({bool force = false}) {}
}

class _MarkerPage extends StatelessWidget {
  const _MarkerPage(this.label);

  final String label;

  @override
  Widget build(BuildContext context) => Scaffold(body: Center(child: Text(label)));
}

class _CashRepo implements CashRepository {
  @override
  bool lastStateFromCache = false;

  @override
  void registerSyncHandlers() {}

  @override
  Future<CashGateState> state() async =>
      const CashGateState(businessDate: '2026-10-15', canOperate: true);

  @override
  Future<ActiveCashSession> openSession({
    required double openingAmount,
    String? note,
  }) async => throw UnimplementedError();

  @override
  Future<void> closeSession({
    required double closingAmount,
    required String sessionId,
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
  Future<CashPage<CashMovementModel>> movementHistoryPage({
    String? type,
    String? movementType,
    DateTime? from,
    DateTime? to,
    String? search,
    int page = 1,
    int limit = 50,
  }) async => const CashPage(items: [], page: 1, limit: 50, hasMore: false);

  @override
  Future<List<CashSessionHistoryModel>> closedSessions() async => const [];

  @override
  Future<CashPage<CashSessionHistoryModel>> closedSessionsPage({
    DateTime? from,
    DateTime? to,
    String? search,
    int page = 1,
    int limit = 50,
  }) async => const CashPage(items: [], page: 1, limit: 50, hasMore: false);

  @override
  Future<CashSessionDetailModel> sessionDetail(String id) =>
      throw UnimplementedError();

  @override
  Future<ActiveCashSession?> cachedActiveSession() async => null;

  @override
  Future<void> addMovement({
    required String type,
    required double amount,
    required String reason,
    String? sessionId,
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

class _Harness {
  _Harness(this.container, this.router, this.backend, this.httpCalls);

  final ProviderContainer container;
  final GoRouter router;
  final _EcfBackendState backend;
  final List<String> httpCalls;

  _FixedAuthController get auth =>
      container.read(authStateProvider.notifier) as _FixedAuthController;
}

Future<_Harness> _pumpSettings(
  WidgetTester tester, {
  required _EcfBackendState backend,
  String? role = 'ADMIN',
  Size viewport = const Size(430, 1600),
}) async {
  SharedPreferences.setMockInitialValues({});
  tester.view.physicalSize = viewport;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final httpCalls = <String>[];
  final dio = Dio()..httpClientAdapter = _RecordingAdapter(httpCalls);

  final container = ProviderContainer(
    overrides: [
      authStateProvider.overrideWith(
        (ref) => _FixedAuthController(
          ref,
          AuthState(
            initialized: true,
            isAuthenticated: true,
            user: _user(role: role),
            loading: false,
            restoringSession: false,
            hasSessionHint: true,
          ),
        ),
      ),
      dioProvider.overrideWithValue(dio),
      cashRepositoryProvider.overrideWithValue(_CashRepo()),
      cashCloseTicketPrinterProvider.overrideWithValue(_Printer()),
      // El "servidor": misma forma que el provider real (depende del usuario).
      companySettingsProvider.overrideWith(
        (ref) async => backend.settingsFor(
          ref.watch(authStateProvider).user?.companyId,
        ),
      ),
      ecfRepositoryProvider.overrideWith(
        (ref) => _FakeEcfRepository(
          backend,
          () => ref.read(authStateProvider).user?.companyId,
        ),
      ),
    ],
  );
  addTearDown(container.dispose);

  final router = GoRouter(
    initialLocation: Routes.configuracionEmpresa,
    routes: [
      GoRoute(
        path: Routes.configuracionEmpresa,
        builder: (_, __) => const AccountCompanySettingsScreen(),
      ),
      GoRoute(
        path: Routes.ecf,
        builder: (_, __) => const _MarkerPage(_markerModule),
      ),
      GoRoute(
        path: Routes.ecfConfig,
        builder: (_, __) => const _MarkerPage(_markerConfig),
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

  return _Harness(container, router, backend, httpCalls);
}

Finder _settingsScaffold() => find
    .descendant(
      of: find.byType(AccountCompanySettingsScreen),
      matching: find.byType(Scaffold),
    )
    .first;

Future<void> _openDrawer(WidgetTester tester) async {
  tester.state<ScaffoldState>(_settingsScaffold()).openDrawer();
  await tester.pumpAndSettle();
}

/// Con el Drawer abierto, el velo modal bloquea la pantalla (correcto). Para
/// tocar el interruptor hay que cerrarlo primero.
Future<void> _closeDrawer(WidgetTester tester) async {
  tester.state<ScaffoldState>(_settingsScaffold()).closeDrawer();
  await tester.pumpAndSettle();
}

/// El interruptor e-CF: el `Switch` de la fila compacta
/// «Utilizar factura electrónica».
///
/// Antes se localizaba por los textos «Activada/Desactivada»; al unificar el
/// bloque fiscal, el interruptor pasó a compartir el mismo componente que
/// «Utilizar impuestos», así que se busca por su etiqueta real. La aserción no
/// se relaja: sigue exigiendo el `Switch` de ESA fila concreta.
Finder _ecfSwitch() {
  final label = find.byWidgetPredicate(
    (widget) =>
        widget is Text && widget.data == 'Utilizar factura electrónica',
  );
  final row = find.ancestor(of: label, matching: find.byType(Row));
  return find.descendant(of: row.first, matching: find.byType(Switch));
}

Finder _drawerText(String text) =>
    find.descendant(of: find.byType(AppDrawer), matching: find.text(text));

/// El `ListView` del Drawer es PEREZOSO: una opción al final del menú puede no
/// estar construida todavía y entonces "no encontrarla" no significa que no
/// exista. Se recorre hasta el final para que TODO el menú quede construido.
Future<void> _scrollDrawerToBottom(WidgetTester tester) async {
  final list = find
      .descendant(of: find.byType(AppDrawer), matching: find.byType(ListView))
      .first;
  for (var i = 0; i < 8; i++) {
    await tester.drag(list, const Offset(0, -420));
    await tester.pumpAndSettle();
  }
}

Future<void> _settleToggle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 60));
  await tester.pumpAndSettle();
}

/// Activa el interruptor e-CF desde la pantalla real.
Future<void> _turnEcfOn(WidgetTester tester) async {
  await tester.ensureVisible(_ecfSwitch());
  await tester.pumpAndSettle();
  await tester.tap(_ecfSwitch());
  await _settleToggle(tester);
}

/// Desactiva el interruptor aceptando el diálogo de confirmación.
Future<void> _turnEcfOff(
  WidgetTester tester, {
  bool confirm = true,
}) async {
  await tester.ensureVisible(_ecfSwitch());
  await tester.pumpAndSettle();
  await tester.tap(_ecfSwitch());
  await tester.pumpAndSettle();
  expect(find.text('¿Desactivar la facturación electrónica?'), findsOneWidget);
  await tester.tap(find.text(confirm ? 'Desactivar' : 'Cancelar'));
  await _settleToggle(tester);
}

_EcfBackendState _backendWith({bool companyA = false}) =>
    _EcfBackendState(enabledByCompany: <String, bool>{
      'company-a': companyA,
      'company-b': false,
    });

void main() {
  group('interruptor e-CF de la empresa — regresión del modelo', () {
    test('copyWith propaga ecfEnabled (no lo pierde)', () {
      final enabled = CompanySettings.empty().copyWith(ecfEnabled: true);

      expect(enabled.ecfEnabled, isTrue);
      // El caso real: guardar CUALQUIER dato de empresa no debe apagar el e-CF.
      expect(
        enabled.copyWith(companyName: 'Otro nombre').ecfEnabled,
        isTrue,
      );
      expect(enabled.copyWith(rnc: '130000000').ecfEnabled, isTrue);
    });

    test('toMap lleva ecfEnabled a la caché local', () {
      final map = CompanySettings.empty()
          .copyWith(ecfEnabled: true)
          .copyWith(companyName: 'Empresa X')
          .toMap();

      expect(map['ecfEnabled'], isTrue);
      expect(CompanySettings.fromMap(map).ecfEnabled, isTrue);
    });
  });

  group('prueba funcional — pantalla real + Drawer real', () {
    testWidgets('1 — empresa desactivada: opción oculta en el Drawer', (
      tester,
    ) async {
      final harness = await _pumpSettings(
        tester,
        backend: _backendWith(companyA: false),
      );

      await _openDrawer(tester);
      expect(find.byType(AppDrawer), findsOneWidget);
      await _scrollDrawerToBottom(tester);

      expect(_drawerText(_ecfDrawerLabel), findsNothing);
      expect(harness.httpCalls, isEmpty);
    });

    testWidgets(
      '2/3/4 — el administrador activa, el backend confirma y el Drawer '
      'muestra el módulo SIN reiniciar',
      (tester) async {
        final harness = await _pumpSettings(
          tester,
          backend: _backendWith(companyA: false),
        );

        // El interruptor se monta en la pantalla real y arranca apagado.
        expect(find.text(_ecfSectionTitle), findsOneWidget);
        expect(tester.widget<Switch>(_ecfSwitch()).value, isFalse);

        await _turnEcfOn(tester);

        // 3: el PATCH se envió una sola vez, con el valor correcto y para la
        // empresa correcta.
        expect(harness.backend.patchCalls, [true]);
        expect(harness.backend.patchCompanies, ['company-a']);
        // El estado mostrado es el confirmado por el backend.
        expect(tester.widget<Switch>(_ecfSwitch()).value, isTrue);
        expect(find.text(_ecfErrorText), findsNothing);

        // 4: sin reiniciar nada, el mismo árbol ya tiene el módulo.
        await _openDrawer(tester);
        await _scrollDrawerToBottom(tester);
        expect(_drawerText(_ecfDrawerLabel), findsOneWidget);

        // Y sin una sola petición HTTP: el menú no consulta la red.
        expect(harness.httpCalls, isEmpty);
      },
    );

    testWidgets('5 — pulsar la opción abre /ecf', (tester) async {
      final harness = await _pumpSettings(
        tester,
        backend: _backendWith(companyA: true),
      );
      expect(find.text(_markerModule), findsNothing);

      await _openDrawer(tester);
      await _scrollDrawerToBottom(tester);
      await tester.ensureVisible(_drawerText(_ecfDrawerLabel).first);
      await tester.pumpAndSettle();
      await tester.tap(_drawerText(_ecfDrawerLabel).first);
      await tester.pumpAndSettle();

      expect(find.text(_markerModule), findsOneWidget);
      expect(find.byType(AccountCompanySettingsScreen), findsNothing);
      expect(harness.httpCalls, isEmpty);
    });

    testWidgets(
      '6/7/8 — desactivar: confirmación, PATCH y el Drawer oculta la opción',
      (tester) async {
        final harness = await _pumpSettings(
          tester,
          backend: _backendWith(companyA: true),
        );
        expect(tester.widget<Switch>(_ecfSwitch()).value, isTrue);

        await _openDrawer(tester);
        await _scrollDrawerToBottom(tester);
        expect(_drawerText(_ecfDrawerLabel), findsOneWidget);

        await _closeDrawer(tester);
        await _turnEcfOff(tester);

        expect(harness.backend.patchCalls, [false]);
        expect(tester.widget<Switch>(_ecfSwitch()).value, isFalse);

        await _openDrawer(tester);
        await _scrollDrawerToBottom(tester);
        expect(_drawerText(_ecfDrawerLabel), findsNothing);
        expect(harness.httpCalls, isEmpty);
      },
    );

    testWidgets('cancelar la desactivación no envía nada', (tester) async {
      final harness = await _pumpSettings(
        tester,
        backend: _backendWith(companyA: true),
      );

      await _turnEcfOff(tester, confirm: false);

      expect(harness.backend.patchCalls, isEmpty);
      expect(tester.widget<Switch>(_ecfSwitch()).value, isTrue);
    });

    testWidgets(
      '9 — si el PATCH falla, se mantiene el estado confirmado y no hay '
      'activación ficticia',
      (tester) async {
        final backend = _backendWith(companyA: false);
        backend.failNextPatch = true;
        final harness = await _pumpSettings(tester, backend: backend);

        await _turnEcfOn(tester);

        // Se intentó una vez y el servidor confirmado sigue apagado.
        expect(harness.backend.patchCalls, [true]);
        expect(harness.backend.enabledByCompany['company-a'], isFalse);
        expect(tester.widget<Switch>(_ecfSwitch()).value, isFalse);
        expect(find.text(_ecfErrorText), findsOneWidget);

        // Ni el interruptor ni el menú muestran una activación que no ocurrió.
        await _openDrawer(tester);
        await _scrollDrawerToBottom(tester);
        expect(_drawerText(_ecfDrawerLabel), findsNothing);
        expect(harness.httpCalls, isEmpty);
      },
    );

    testWidgets('10 — sin permiso el interruptor está deshabilitado', (
      tester,
    ) async {
      final cajero = _user(role: 'CAJERO');
      expect(
        hasUserPermission(cajero, AppPermission.manageEcfConfig),
        isFalse,
        reason: 'precondición: un cajero no gestiona la configuración e-CF',
      );

      final harness = await _pumpSettings(
        tester,
        backend: _backendWith(companyA: false),
        role: 'CAJERO',
      );

      final switchWidget = tester.widget<Switch>(_ecfSwitch());
      expect(switchWidget.value, isFalse);
      expect(switchWidget.onChanged, isNull);
      expect(
        find.text('Solo un administrador autorizado puede cambiarlo.'),
        findsOneWidget,
      );

      await tester.ensureVisible(_ecfSwitch());
      await tester.pumpAndSettle();
      await tester.tap(_ecfSwitch(), warnIfMissed: false);
      await _settleToggle(tester);

      expect(harness.backend.patchCalls, isEmpty);
      expect(tester.widget<Switch>(_ecfSwitch()).value, isFalse);
    });

    testWidgets(
      '11 — al cambiar de empresa NO se reutiliza la bandera anterior',
      (tester) async {
        final harness = await _pumpSettings(
          tester,
          backend: _backendWith(companyA: true),
        );

        await _openDrawer(tester);
        await _scrollDrawerToBottom(tester);
        expect(_drawerText(_ecfDrawerLabel), findsOneWidget);

        // Misma sesión, misma pantalla montada: otra empresa con e-CF apagado.
        harness.auth.switchCompany('company-b');
        await tester.pump();
        await tester.pumpAndSettle();

        // El interruptor refleja la empresa NUEVA, no la anterior.
        expect(find.text(_ecfSectionTitle), findsOneWidget);
        expect(tester.widget<Switch>(_ecfSwitch()).value, isFalse);

        await _scrollDrawerToBottom(tester);
        expect(_drawerText(_ecfDrawerLabel), findsNothing);
        expect(harness.backend.enabledByCompany['company-a'], isTrue);
        expect(harness.httpCalls, isEmpty);
      },
    );
  });

  group('garantía estructural — el menú no depende de la red', () {
    test('AppDrawer lee el interruptor de la configuración de empresa', () {
      final source = File(
        'lib/core/widgets/app_drawer.dart',
      ).readAsStringSync();

      expect(source, contains('companySettingsProvider'));
      expect(source, contains('ecfEnabled'));
      // Ni el menú ni la navegación pueden consultar el módulo por su cuenta.
      expect(source, isNot(contains('ecfCapabilitiesProvider')));
      expect(source, isNot(contains('ecfRepositoryProvider')));
    });
  });
}
