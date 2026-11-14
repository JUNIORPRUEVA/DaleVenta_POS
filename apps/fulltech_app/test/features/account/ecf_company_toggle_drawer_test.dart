import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:daleventa_pos/core/theme/app_theme.dart';

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
///   El interruptor activa el módulo y su acceso en el Drawer.
///
/// Monta la pantalla REAL (`AccountCompanySettingsScreen`), el Drawer REAL
/// (`AppDrawer`, el mismo que sirve `buildAdaptiveDrawer`), el
/// `companySettingsProvider` REAL (con el backend simulado detrás), los
/// permisos reales del usuario y un repositorio e-CF simulado. No hay red.
///
/// El estado que se muestra viene SIEMPRE del backend simulado: el interruptor
/// nunca se pinta de forma optimista.

final _qaBoundaryKey = GlobalKey();

class _QaBoundary extends SingleChildRenderObjectWidget {
  const _QaBoundary({super.key, required super.child});

  @override
  RenderRepaintBoundary createRenderObject(BuildContext context) =>
      _QaRenderBoundary();
}

class _QaRenderBoundary extends RenderRepaintBoundary {
  Future<ui.Image> captureRegion(Rect region) =>
      (layer! as OffsetLayer).toImage(region);
}

const _markerModule = 'marcador-modulo-ecf';
const _markerConfig = 'marcador-config-ecf';
const _ecfDrawerLabel = 'Facturación electrónica';
// El interruptor de e-CF dejó de ser una sección independiente: ahora vive
// dentro del bloque fiscal, que se llama «Impuestos y e-CF». La aserción sigue
// verificando que esa sección está en pantalla, solo que con su nombre actual.
const _ecfSectionTitle = 'Facturación electrónica';
const _ecfPrepareLabel = 'Preparar habilitación e-CF';
const _ecfErrorText =
    'No se pudo guardar. Se mantiene el último estado confirmado por el servidor.';
const _allowWarning =
    'Advertencia fiscal: esta opción permite registrar ventas sin emitir un '
    'comprobante fiscal electrónico.';

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
  _EcfBackendState({
    required this.enabledByCompany,
    Map<String, bool>? allowByCompany,
  }) : allowByCompany = allowByCompany ?? <String, bool>{};

  final Map<String, bool> enabledByCompany;

  /// Excepción «vender sin comprobante», por empresa.
  final Map<String, bool> allowByCompany;
  final List<bool> patchCalls = <bool>[];
  final List<String?> patchCompanies = <String?>[];
  final List<bool> allowPatchCalls = <bool>[];
  bool failNextPatch = false;

  bool allowFor(String? companyId) =>
      allowByCompany[companyId ?? 'sin-empresa'] ?? false;

  CompanySettings settingsFor(String? companyId) {
    return CompanySettings.empty().copyWith(
      companyName: 'Empresa ${companyId ?? 'sin-empresa'}',
      // La activación confirma también los impuestos, como hace el backend.
      taxEnabled: enabledByCompany[companyId] ?? false,
      ecfEnabled: enabledByCompany[companyId] ?? false,
    );
  }
}

class _FakeEcfRepository extends EcfRepository {
  _FakeEcfRepository(this._backend, this._currentCompanyId) : super(Dio());

  final _EcfBackendState _backend;
  final String? Function() _currentCompanyId;

  /// Las capacidades salen del backend simulado y son POR EMPRESA: igual que el
  /// endpoint real, incluyen si la excepción de venta sin e-CF está habilitada.
  @override
  Future<EcfCapabilities> capabilities() async {
    final companyId = _currentCompanyId();
    final moduleEnabled = _backend.enabledByCompany[companyId] ?? false;
    return EcfCapabilities(
      enabled: moduleEnabled,
      environment: 'SANDBOX',
      certificationStatus: 'NOT_STARTED',
      productionEnabled: false,
      allowedTypes: const <String>['E31', 'E32'],
      emissionPathAvailable: false,
      documentTypes: const <EcfDocumentTypeCapability>[],
      allowSalesWithoutEcf: _backend.allowFor(companyId),
      salesWithoutEcfWarning: _allowWarning,
    );
  }

  @override
  Future<void> updateAllowSalesWithoutEcf({required bool allow}) async {
    _backend.allowPatchCalls.add(allow);
    _backend.allowByCompany[_currentCompanyId() ?? 'sin-empresa'] = allow;
  }

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
  Widget build(BuildContext context) =>
      Scaffold(body: Center(child: Text(label)));
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
  Future<CashSummaryModel?> cachedSummary() async => null;

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
        (ref) async =>
            backend.settingsFor(ref.watch(authStateProvider).user?.companyId),
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
      child: _QaBoundary(
        key: _qaBoundaryKey,
        child: MaterialApp.router(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light.copyWith(platform: TargetPlatform.android),
          routerConfig: router,
        ),
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
/// «Activar módulo de facturación electrónica».
///
/// Antes se localizaba por los textos «Activada/Desactivada»; al unificar el
/// bloque fiscal, el interruptor pasó a compartir el mismo componente que
/// «Utilizar impuestos», así que se busca por su etiqueta real. La aserción no
/// se relaja: sigue exigiendo el `Switch` de ESA fila concreta.
Finder _ecfSwitch() {
  final label = find.byWidgetPredicate(
    (widget) => widget is Text && widget.data == 'Activar módulo de facturación electrónica',
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
  // Se arrastra el área desplazable del menú: la lista es perezosa y el menú
  // agrupa las entradas, así que las de abajo solo se construyen al acercarse.
  final scroll = find
      .descendant(of: find.byType(AppDrawer), matching: find.byType(Scrollable))
      .first;
  for (var i = 0; i < 12; i++) {
    await tester.drag(scroll, const Offset(0, -420));
    await tester.pumpAndSettle();
  }
}

/// El drawer no recupera módulos adicionales al cambiar la configuración.
void _expectNoExtraModules() {
  expect(_drawerText('Más módulos'), findsNothing);
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
Future<void> _turnEcfOff(WidgetTester tester, {bool confirm = true}) async {
  await tester.ensureVisible(_ecfSwitch());
  await tester.pumpAndSettle();
  await tester.tap(_ecfSwitch());
  await tester.pumpAndSettle();
  expect(find.text('¿Desactivar la facturación electrónica?'), findsOneWidget);
  await tester.tap(find.text(confirm ? 'Desactivar' : 'Cancelar'));
  await _settleToggle(tester);
}

_EcfBackendState _backendWith({bool companyA = false}) => _EcfBackendState(
  enabledByCompany: <String, bool>{'company-a': companyA, 'company-b': false},
);

/// Interruptor de la excepción fiscal, distinto del general.
Finder _allowSwitch() {
  final label = find.text('Vender sin comprobante');
  final row = find.ancestor(of: label, matching: find.byType(Row));
  return find.descendant(of: row.first, matching: find.byType(Switch));
}

Future<void> _captureQa(WidgetTester tester, String name) async {
  final output = Platform.environment['FULLPOS_QA_OUTPUT'];
  if (output == null) return;
  await tester.pumpAndSettle();
  final boundary = _qaBoundaryKey.currentContext!.findRenderObject() as _QaRenderBoundary;
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await Directory(output).create(recursive: true);
    await File('$output/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
    if (name.startsWith('empresa-') && !name.endsWith('confirmacion')) {
      final panel = find.ancestor(
        of: find.text(_ecfSectionTitle),
        matching: find.byType(Material),
      ).first;
      final detail = await boundary.captureRegion(tester.getRect(panel));
      final detailBytes = await detail.toByteData(format: ui.ImageByteFormat.png);
      await File('$output/$name-panel.png').writeAsBytes(detailBytes!.buffer.asUint8List());
      detail.dispose();
    }
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final manrope = FontLoader('Manrope');
    for (final weight in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
      manrope.addFont(rootBundle.load('assets/fonts/manrope/Manrope-$weight.ttf'));
    }
    await manrope.load();
    await (FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
  for (final size in [const Size(390, 844), const Size(834, 1112), const Size(1264, 681)]) {
    testWidgets('configuración fiscal adaptable ${size.width}x${size.height}', (tester) async {
      final backend = _backendWith();
      await _pumpSettings(tester, backend: backend, viewport: size);
      await tester.ensureVisible(find.text(_ecfSectionTitle));
      await _captureQa(tester, 'empresa-${size.width.toInt()}-apagado');
      await _turnEcfOn(tester);
      await tester.ensureVisible(find.text(_ecfSectionTitle));
      await _captureQa(tester, 'empresa-${size.width.toInt()}-activo');
      expect(tester.takeException(), isNull);
      await tester.tap(_allowSwitch());
      await tester.pumpAndSettle();
      expect(find.text(_allowWarning), findsOneWidget);
      await _captureQa(tester, 'empresa-${size.width.toInt()}-confirmacion');
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      expect(backend.allowPatchCalls, isEmpty);
      await _openDrawer(tester);
      await _scrollDrawerToBottom(tester);
      expect(_drawerText(_ecfDrawerLabel), findsOneWidget);
      await _captureQa(tester, 'drawer-${size.width.toInt()}');
      expect(tester.takeException(), isNull);
    });
  }

  group('interruptor e-CF de la empresa — regresión del modelo', () {
    test('copyWith propaga ecfEnabled (no lo pierde)', () {
      final enabled = CompanySettings.empty().copyWith(ecfEnabled: true);

      expect(enabled.ecfEnabled, isTrue);
      // El caso real: guardar CUALQUIER dato de empresa no debe apagar el e-CF.
      expect(enabled.copyWith(companyName: 'Otro nombre').ecfEnabled, isTrue);
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
    testWidgets('1 — empresa desactivada: el módulo NO aparece en el Drawer', (
      tester,
    ) async {
      final harness = await _pumpSettings(
        tester,
        backend: _backendWith(companyA: false),
      );

      await _openDrawer(tester);
      expect(find.byType(AppDrawer), findsOneWidget);
      await _scrollDrawerToBottom(tester);

      // Un cliente que no ha solicitado e-CF conserva su POS tradicional: la
      // entrada del módulo no existe para nadie de esa empresa.
      _expectNoExtraModules();
      expect(_drawerText(_ecfDrawerLabel), findsNothing);
      expect(harness.httpCalls, isEmpty);
    });

    testWidgets(
      '2/3/4 — el administrador activa, el backend confirma y el Drawer '
      'muestra el módulo confirmado',
      (tester) async {
        final harness = await _pumpSettings(
          tester,
          backend: _backendWith(companyA: false),
        );

        // El interruptor se monta en la pantalla real y arranca apagado.
        expect(find.text(_ecfSectionTitle), findsOneWidget);
        expect(tester.widget<Switch>(_ecfSwitch()).value, isFalse);

        // Antes de activarlo la empresa no tiene el módulo en el menú.
        await _openDrawer(tester);
        await _scrollDrawerToBottom(tester);
        _expectNoExtraModules();
        expect(_drawerText(_ecfDrawerLabel), findsNothing);
        await _closeDrawer(tester);

        await _turnEcfOn(tester);

        // 3: el PATCH se envió una sola vez, con el valor correcto y para la
        // empresa correcta.
        expect(harness.backend.patchCalls, [true]);
        expect(harness.backend.patchCompanies, ['company-a']);
        // El estado mostrado es el confirmado por el backend.
        expect(tester.widget<Switch>(_ecfSwitch()).value, isTrue);
        expect(find.text(_ecfErrorText), findsNothing);

        // La activación confirmada añade la entrada propia del módulo.
        await _openDrawer(tester);
        await _scrollDrawerToBottom(tester);
        _expectNoExtraModules();
        expect(_drawerText(_ecfDrawerLabel), findsOneWidget);

        // Y sin una sola petición HTTP: el menú no consulta la red.
        expect(harness.httpCalls, isEmpty);
      },
    );

    testWidgets('5 — el Drawer abre el módulo activado', (tester) async {
      final harness = await _pumpSettings(
        tester,
        backend: _backendWith(companyA: true),
      );
      expect(find.text(_markerModule), findsNothing);

      await _openDrawer(tester);
      await _scrollDrawerToBottom(tester);
      _expectNoExtraModules();
      await tester.tap(_drawerText(_ecfDrawerLabel));
      await tester.pumpAndSettle();

      expect(find.text(_markerModule), findsOneWidget);
      expect(find.byType(AccountCompanySettingsScreen), findsNothing);
      expect(harness.httpCalls, isEmpty);
    });

    testWidgets(
      '6/7/8 — desactivar: confirmación, PATCH y el módulo desaparece',
      (tester) async {
        final harness = await _pumpSettings(
          tester,
          backend: _backendWith(companyA: true),
        );
        expect(tester.widget<Switch>(_ecfSwitch()).value, isTrue);

        await _openDrawer(tester);
        await _scrollDrawerToBottom(tester);
        _expectNoExtraModules();
        expect(_drawerText(_ecfDrawerLabel), findsOneWidget);

        await _closeDrawer(tester);
        await _turnEcfOff(tester);

        expect(harness.backend.patchCalls, [false]);
        expect(tester.widget<Switch>(_ecfSwitch()).value, isFalse);

        await _openDrawer(tester);
        await _scrollDrawerToBottom(tester);
        // El drawer permanece sin módulos adicionales al desactivar e-CF.
        _expectNoExtraModules();
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

        // El interruptor sigue apagado y, por tanto, el módulo sigue oculto.
        await _openDrawer(tester);
        await _scrollDrawerToBottom(tester);
        _expectNoExtraModules();
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
      // Tampoco existe el camino administrativo para iniciar la habilitación.
      expect(find.text(_ecfPrepareLabel), findsNothing);

      await tester.ensureVisible(_ecfSwitch());
      await tester.pumpAndSettle();
      await tester.tap(_ecfSwitch(), warnIfMissed: false);
      await _settleToggle(tester);

      expect(harness.backend.patchCalls, isEmpty);
      expect(tester.widget<Switch>(_ecfSwitch()).value, isFalse);
    });

    testWidgets('el módulo apagado solo ofrece su interruptor', (tester) async {
      await _pumpSettings(tester, backend: _backendWith());
      expect(find.text(_ecfPrepareLabel), findsNothing);
      expect(find.text('Utilizar impuestos'), findsNothing);
      expect(find.text('ITBIS incluido'), findsNothing);
      await _turnEcfOn(tester);
      expect(find.text('ITBIS incluido'), findsOneWidget);
      expect(find.text('Precio + ITBIS'), findsOneWidget);
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
        _expectNoExtraModules();
        expect(_drawerText(_ecfDrawerLabel), findsOneWidget);

        // Misma sesión, misma pantalla montada: otra empresa con e-CF apagado.
        harness.auth.switchCompany('company-b');
        await tester.pump();
        await tester.pumpAndSettle();

        // El interruptor refleja la empresa NUEVA, no la anterior.
        expect(find.text(_ecfSectionTitle), findsOneWidget);
        expect(tester.widget<Switch>(_ecfSwitch()).value, isFalse);

        await _scrollDrawerToBottom(tester);
        // La empresa nueva no tiene e-CF: el módulo no se hereda de la anterior.
        _expectNoExtraModules();
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

  group('ventas sin comprobante electrónico — dentro de Empresa', () {
    testWidgets('con el módulo apagado la excepción no se ofrece', (
      tester,
    ) async {
      await _pumpSettings(tester, backend: _backendWith(companyA: false));

      // Sin e-CF no hay nada que exceptuar: el control ni siquiera se pinta.
      expect(find.text('Vender sin comprobante'), findsNothing);
    });

    testWidgets(
      'con el módulo encendido aparece y no se confunde con el interruptor '
      'general',
      (tester) async {
        await _pumpSettings(tester, backend: _backendWith(companyA: true));

        // Los dos controles conviven, con etiquetas distintas.
        expect(find.text('Activar módulo de facturación electrónica'), findsOneWidget);
        expect(find.text('Vender sin comprobante'), findsOneWidget);
        // El valor mostrado es el del servidor: apagado por defecto.
        expect(tester.widget<Switch>(_allowSwitch()).value, isFalse);
      },
    );

    testWidgets(
      'activar exige confirmación, guarda en el mismo endpoint y relee el '
      'valor confirmado',
      (tester) async {
        final harness = await _pumpSettings(
          tester,
          backend: _backendWith(companyA: true),
        );

        await tester.ensureVisible(
          find.text('Vender sin comprobante'),
        );
        await tester.tap(_allowSwitch());
        await tester.pumpAndSettle();

        // El aviso fiscal completo se muestra antes de habilitar.
        expect(find.text(_allowWarning), findsWidgets);

        await tester.tap(find.text('Entiendo y habilito'));
        await tester.pumpAndSettle();

        expect(harness.backend.allowPatchCalls, [true]);
        expect(tester.widget<Switch>(_allowSwitch()).value, isTrue);
        // Nada de peticiones fuera del repositorio e-CF configurado.
        expect(harness.httpCalls, isEmpty);
      },
    );

    testWidgets('cambiar de empresa no conserva el valor anterior', (
      tester,
    ) async {
      final backend = _backendWith(companyA: true);
      // La empresa A tiene la excepción; la B también factura electrónico pero
      // NO la tiene habilitada.
      backend.enabledByCompany['company-b'] = true;
      backend.allowByCompany['company-a'] = true;
      backend.allowByCompany['company-b'] = false;

      final harness = await _pumpSettings(tester, backend: backend);
      expect(tester.widget<Switch>(_allowSwitch()).value, isTrue);

      harness.auth.switchCompany('company-b');
      await tester.pump();
      await tester.pumpAndSettle();

      // El control se relee para la empresa nueva: no hereda el «sí» anterior.
      expect(tester.widget<Switch>(_allowSwitch()).value, isFalse);
      expect(tester.widget<Switch>(_ecfSwitch()).value, isTrue);
      expect(backend.allowByCompany['company-a'], isTrue);
    });
  });
}
