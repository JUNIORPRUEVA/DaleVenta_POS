// Regresión: la pantalla de facturación debe mostrar el selector de
// comprobante electrónico en cuanto el servidor devuelve las capacidades.
//
// Antes este caso fallaba: `ecfCapabilitiesProvider` es `autoDispose` y la
// pantalla lo leía con `ref.read` sin suscribirse, así que se destruía antes de
// resolver. El carrito mostraba «Comprobante electrónico no disponible» y el
// cobro quedaba bloqueado aunque la empresa facturara electrónicamente.
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:daleventa_pos/core/auth/auth_provider.dart';
import 'package:daleventa_pos/core/auth/auth_repository.dart';
import 'package:daleventa_pos/core/auth/auth_session_events.dart';
import 'package:daleventa_pos/core/auth/token_storage.dart';
import 'package:daleventa_pos/core/company/company_settings_model.dart';
import 'package:daleventa_pos/core/company/company_settings_repository.dart';
import 'package:daleventa_pos/core/models/user_model.dart';
import 'package:daleventa_pos/core/theme/app_theme.dart';
import 'package:daleventa_pos/core/widgets/branded_menu_button.dart';
import 'package:daleventa_pos/core/usage/client_telemetry_headers.dart';
import 'package:daleventa_pos/features/ecf/data/ecf_repository.dart';
import 'package:daleventa_pos/features/ecf/ecf_models.dart';
import 'package:daleventa_pos/features/price_lists/data/price_lists_repository.dart';
import 'package:daleventa_pos/modules/cotizaciones/cotizacion_models.dart';
import 'package:daleventa_pos/modules/cash/cash_models.dart';
import 'package:daleventa_pos/modules/cash/cash_repository.dart';
import 'package:daleventa_pos/modules/cotizaciones/cotizaciones_screen.dart';
import 'package:daleventa_pos/modules/cotizaciones/presentation/widgets/sales_catalog_command_bar.dart';
import 'package:daleventa_pos/modules/cotizaciones/presentation/widgets/sales_client_selector.dart';
import 'package:daleventa_pos/modules/cotizaciones/presentation/widgets/sales_detail_header.dart';
import 'package:daleventa_pos/modules/cotizaciones/presentation/widgets/sales_detail_shortcut.dart';
import 'package:daleventa_pos/modules/cotizaciones/presentation/widgets/mobile_sales_controls.dart';
import 'package:daleventa_pos/core/ai_assistant/presentation/widgets/ai_assistant_sheet.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:daleventa_pos/modules/ventas/ecf_pos_fiscal.dart';
import 'package:daleventa_pos/modules/ventas/ecf_pos_fiscal_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _productId = '11111111-1111-4111-8111-111111111111';
final _capture = GlobalKey();

class _MemoryStorage extends TokenStorage {
  @override
  Future<UserModel?> getUserSnapshot() async => null;
  @override
  Future<String?> getAccessToken() async => 'test-token';
  @override
  Future<String?> getRefreshToken() async => null;
  @override
  Future<void> clearTokens() async {}
}

class _Auth extends AuthController {
  _Auth(super.ref) {
    state = AuthState(
      initialized: true,
      isAuthenticated: true,
      user: UserModel(
        id: 'selector-test-user',
        email: 'selector@example.test',
        nombreCompleto: 'Prueba',
        telefono: '',
        role: 'ADMIN',
        companyId: 'selector-test-company',
      ),
    );
  }
}

class _Catalog implements HttpClientAdapter {
  _Catalog({this.productCount = 1});
  final int productCount;
  @override
  Future<ResponseBody> fetch(
    RequestOptions request,
    Stream<Uint8List>? stream,
    Future<void>? cancel,
  ) async {
    return ResponseBody.fromString(
      jsonEncode({
        'items': List.generate(
          productCount,
          (index) => {
            'id': index == 0 ? _productId : 'product-$index',
            'nombre': 'Cable de prueba',
            'precio': 900,
            'costo': 400,
            'categoria': 'Prueba',
            'trackInventory': false,
          },
        ),
        'total': productCount,
        'page': 1,
        'hasMore': false,
      }),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

class _PriceLists extends PriceListsRepository {
  _PriceLists(super.dio);
  @override
  Future<List<PriceListModel>> fetchPriceLists() async => const [];
}

class _OpenCash implements CashRepository {
  _OpenCash({this.open = true});
  final bool open;
  @override
  Future<CashGateState> state() async => CashGateState(
    businessDate: '2026-11-21', canOperate: true,
    activeSession: !open ? null : ActiveCashSession(userId: 'selector-test-user',
      shiftId: 'local-test-shift', openedAt: DateTime.utc(2026, 11, 21),
      status: 'OPEN', userName: 'Prueba', businessDate: '2026-11-21'),
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Capacidades con E31, E32 y la excepción de venta normal habilitada.
EcfCapabilities _capabilities({bool ready = true}) => EcfCapabilities(
  enabled: true,
  posReady: ready,
  posAvailableTypes: ['E31', 'E32'],
  environment: 'SANDBOX',
  certificationStatus: 'PRODUCTION_READY',
  productionEnabled: false,
  allowedTypes: ['E31', 'E32'],
  emissionPathAvailable: false,
  allowSalesWithoutEcf: true,
  documentTypes: [
    EcfDocumentTypeCapability(
      documentType: 'E31',
      contractStatus: 'ACTIVE',
      contractAllowsEmission: true,
      allowedForCompany: true,
      allocatable: true,
    ),
    EcfDocumentTypeCapability(
      documentType: 'E32',
      contractStatus: 'ACTIVE',
      contractAllowsEmission: true,
      allowedForCompany: true,
      allocatable: true,
    ),
  ],
);

final _quotation = CotizacionModel(
  id: '',
  createdAt: DateTime(2026, 11, 10),
  customerId: null,
  customerName: 'Sin cliente',
  customerPhone: '',
  note: '',
  includeItbis: false,
  itbisRate: 0,
  items: [
    CotizacionItem(
      productId: _productId,
      nombre: 'Cable de prueba',
      imageUrl: null,
      unitPrice: 900,
      originalUnitPrice: 900,
      qty: 1,
    ),
  ],
);

Future<void> _pumpScreen(
  WidgetTester tester, {
  bool ready = true,
  bool quotationEditor = true,
  Size viewport = const Size(1280, 900),
  int productCount = 1,
  bool cashOpen = true,
}) async {
  tester.view.physicalSize = viewport;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final dio = Dio(BaseOptions(baseUrl: 'https://billing.example.test'));
  dio.httpClientAdapter = _Catalog(productCount: productCount);
  final container = ProviderContainer(
    overrides: [
      dioProvider.overrideWithValue(dio),
      cashRepositoryProvider.overrideWithValue(_OpenCash(open: cashOpen)),
      tokenStorageProvider.overrideWithValue(_MemoryStorage()),
      authSessionEventsProvider.overrideWith((_) => AuthSessionEvents()),
      authStateProvider.overrideWith(_Auth.new),
      companySettingsProvider.overrideWith(
        (_) async => CompanySettings.empty().copyWith(ecfEnabled: true),
      ),
      priceListsRepositoryProvider.overrideWithValue(_PriceLists(dio)),
      // Se resuelve de forma asíncrona, como la llamada real al backend.
      ecfCapabilitiesProvider.overrideWith(
        (_) async => _capabilities(ready: ready),
      ),
    ],
  );
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: RepaintBoundary(
        key: _capture,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light,
          home: CotizacionesScreen(
            initialQuotation: _quotation,
            returnSavedQuotation: quotationEditor,
          ),
        ),
      ),
    ),
  );
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
    container.dispose();
    dio.close(force: true);
  });
}

Future<void> _savePhonePreview(WidgetTester tester, String name) async {
  final output = Platform.environment['FULLPOS_MOBILE_VISUAL_QA'];
  if (output == null) return;
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
  await tester.pump();
  final boundary = _capture.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final picture = await boundary.toImage();
    final bytes = await picture.toByteData(format: ui.ImageByteFormat.png);
    await Directory(output).create(recursive: true);
    await File('$output/$name-${defaultTargetPlatform.name}.png').writeAsBytes(bytes!.buffer.asUint8List());
    picture.dispose();
  });
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    PackageInfo.setMockInitialValues(
      appName: 'Test',
      packageName: 'example.test',
      version: '1',
      buildNumber: '1',
      buildSignature: '',
    );
    await ClientTelemetryHeaders.instance.headers();
    final loader = FontLoader('Manrope')
      ..addFont(rootBundle.load('assets/fonts/manrope/Manrope-Regular.ttf'))
      ..addFont(rootBundle.load('assets/fonts/manrope/Manrope-Bold.ttf'));
    await loader.load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });

  test('una respuesta antigua no da por preparada a la empresa', () {
    final caps = EcfCapabilities.fromJson({'enabled': true});
    expect(caps.posReady, isFalse);
    expect(caps.posAvailableTypes, isEmpty);
  });

  testWidgets(
    'native phone header, actions and tickets preserve separate carts',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      await _pumpScreen(
        tester,
        viewport: const Size(390, 844),
        quotationEditor: false,
      );
      expect(find.byKey(const ValueKey('phone-sales-header')), findsNothing);
      expect(find.text('Comprobante'), findsNothing);
      expect(find.byType(MobileSalesProductCard), findsOneWidget);
      Future<void> openTickets() async {
        await tester.tap(find.byTooltip('Acciones'));
        for (var i = 0; i < 6; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        await tester.tap(find.text('Tickets'));
        await tester.pumpAndSettle();
      }
      expect(find.byType(BrandedMenuButton), findsOneWidget);
      expect(find.text('Turno abierto'), findsOneWidget);
      expect(find.byTooltip('Escanear producto'), findsNothing);
      await tester.tap(find.byTooltip('Estado del turno'));
      await tester.pumpAndSettle();
      expect(find.text('Cerrar turno'), findsOneWidget);
      expect(find.text('Registrar entrada'), findsOneWidget);
      expect(find.text('Abrir turno'), findsNothing);
      await tester.tapAt(const Offset(4, 400));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Abrir menú principal'));
      await tester.pumpAndSettle();
      final drawerRect = tester.getRect(find.byType(Drawer));
      expect(drawerRect.width, closeTo(390 * 0.75, 1));
      final footerRect = tester.getRect(find.byKey(const ValueKey('phone-drawer-account-footer')));
      expect(footerRect.left, drawerRect.left);
      expect(footerRect.right, drawerRect.right);
      expect(find.text('Turno'), findsNothing);
      await tester.tapAt(const Offset(389, 400));
      await tester.pumpAndSettle();
      await _savePhonePreview(tester, 'half-main');
      expect(find.byTooltip('Tickets'), findsNothing);
      final search = find.byKey(const ValueKey('phone-catalog-search'));
      final category = find.byKey(const ValueKey('phone-catalog-category'));
      expect(tester.getSize(search).height, 36);
      expect(tester.getSize(category).height, 36);
      final searchIcon = find.descendant(of: search, matching: find.byType(ImageIcon));
      expect(tester.getSize(searchIcon), const Size(16, 16));
      expect(find.descendant(of: search, matching: category), findsNothing);
      expect(tester.getCenter(search).dy, closeTo(tester.getCenter(category).dy, 2));
      expect(tester.getSize(category).height, 36);
      await openTickets();
      await tester.pumpAndSettle();
      expect(find.text('Ticket 1'), findsOneWidget);
      expect(find.textContaining('1 artículos'), findsOneWidget);
      await tester.tap(find.text('Nuevo ticket'));
      await tester.pumpAndSettle();
      await openTickets();
      await tester.pumpAndSettle();
      expect(find.text('Ticket 2'), findsOneWidget);
      expect(find.textContaining('0 artículos ·'), findsOneWidget);
      await tester.tap(find.text('Ticket 1'));
      await tester.pumpAndSettle();
      await openTickets();
      await tester.pumpAndSettle();
      expect(find.textContaining('1 artículos'), findsOneWidget);
      await tester.tap(find.byTooltip('Cerrar tickets'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Acciones'));
      // The existing calculator access continuously animates while this panel
      // is open; wait for its entrance rather than for all animations to stop.
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.byType(MobileSalesActionRow), findsNWidgets(5));
      expect(find.text('Escanear producto'), findsOneWidget);
      expect(find.byKey(const ValueKey('phone-sale-details')), findsOneWidget);
      final panel = tester.getRect(find.byKey(const ValueKey('phone-sale-details')));
      expect(panel.width, closeTo(390 * 0.75 - 32, 1));
      await _savePhonePreview(tester, 'half-actions');
      expect(find.text('Datos de la venta'), findsNothing);
      expect(find.text('Herramientas'), findsNothing);
      expect(find.text('Cliente general'), findsOneWidget);
      expect(find.text('Comprobante'), findsOneWidget);
      expect(find.text('Lista de precios'), findsNothing);
      await tester.tap(find.text('Normal'));
      await tester.pump(const Duration(milliseconds: 250));
      await tester.tap(find.text(EcfPosFiscalMode.e32.label));
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pump(const Duration(milliseconds: 350));
      expect(find.text(EcfPosFiscalMode.e32.label), findsOneWidget,
        reason: tester.widgetList<Text>(find.byType(Text)).map((text) => text.data).join(' | '));
      await tester.tap(find.byTooltip('Cerrar'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Acciones'));
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.text(EcfPosFiscalMode.e32.label), findsOneWidget);
      expect(find.text('Nuevo ticket'), findsNothing);
      expect(find.byTooltip('Asistente IA'), findsOneWidget);
      expect(find.text('Cobro rápido'), findsNothing);
      final tools = find.byType(MobileSalesFloatingTools);
      final assistant = tester.getSize(find.byTooltip('Asistente IA'));
      final calculator = tester.getSize(find.byTooltip('Abrir calculadora'));
      expect(tools, findsOneWidget);
      expect(assistant, calculator);
      expect(assistant.width, 64);
      await tester.tap(find.byTooltip('Asistente IA'));
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.byType(GlobalAiChatSheet), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant({
      TargetPlatform.android,
      TargetPlatform.iOS,
    }),
  );

  testWidgets(
    'phone catalog keeps search visible without sale selectors while scrolling',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      await _pumpScreen(
        tester,
        viewport: const Size(390, 844),
        productCount: 24,
      );
      final header = find.byKey(const ValueKey('phone-sales-header'));
      final footer = find.byKey(const ValueKey('phone-checkout-footer'));
      expect(header, findsNothing);
      expect(find.text('Comprobante'), findsNothing);
      expect(find.byType(MobileSalesEdgeHint), findsOneWidget);
      tester.view.systemGestureInsets = const FakeViewPadding(right: 24);
      addTearDown(tester.view.resetSystemGestureInsets);
      await tester.pump();
      final hintRect = tester.getRect(find.byType(MobileSalesEdgeHint));
      expect(hintRect.right, 390);
      expect(find.byTooltip('Editar'), findsNothing);
      expect(tester.getTopLeft(find.byKey(const ValueKey('phone-cart-count'))).dx, 8);
      expect(tester.getCenter(find.byKey(const ValueKey('phone-cart-drag-indicator'))).dx, 195);
      final footerRect = tester.getRect(footer);
      expect(footerRect.left, 0);
      expect(footerRect.right, 390);
      await tester.drag(find.byType(GridView), const Offset(0, -300));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('phone-sales-header-collapsed')),
        findsNothing,
      );
      expect(find.byType(GridView), findsOneWidget);
      expect(
        find.widgetWithText(TextField, 'Buscar productos...'),
        findsOneWidget,
      );
      expect(tester.getRect(footer), footerRect);
      await tester.drag(find.byType(GridView), const Offset(0, 180));
      await tester.pumpAndSettle();
      expect(header, findsNothing);
      expect(find.text('Comprobante'), findsNothing);
      expect(tester.getRect(footer), footerRect);
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant({
      TargetPlatform.android,
      TargetPlatform.iOS,
    }),
  );

  testWidgets(
    'phone quick checkout shows general customer without requiring selection',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      await _pumpScreen(tester, viewport: const Size(390, 844), quotationEditor: false);
      await tester.tap(find.text('Cobrar'));
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.byKey(const ValueKey('phone-checkout-sale-summary')), findsOneWidget,
        reason: tester.widgetList<Text>(find.byType(Text)).map((text) => text.data).join(' | '));
      expect(find.text('Cliente general'), findsOneWidget);
      expect(find.descendant(of: find.byType(Dialog), matching: find.text('Comprobante')), findsNothing);
      final confirm = find.widgetWithText(FilledButton, 'Cobrar y facturar');
      expect(tester.widget<FilledButton>(confirm).onPressed, isNotNull);
      expect(find.descendant(of: find.byType(Dialog), matching: find.byType(EcfPosFiscalSelector)), findsNothing);
      await _savePhonePreview(tester, 'pos-square-checkout');
      expect(tester.takeException(), isNull);
      // Cancel only: this test never confirms or posts a sale.
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('phone-checkout-sale-summary')), findsNothing);
    },
    variant: TargetPlatformVariant({TargetPlatform.android, TargetPlatform.iOS}),
  );

  testWidgets(
    'phone turn menu reuses open and close options without duplicate drawer group',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      await _pumpScreen(tester, viewport: const Size(390, 844), cashOpen: false);
      expect(find.text('Turno cerrado'), findsOneWidget);
      await tester.tap(find.byTooltip('Estado del turno'));
      await tester.pumpAndSettle();
      expect(find.text('Abrir turno'), findsOneWidget);
      expect(find.text('Cerrar turno'), findsNothing);
      // Dismiss: never execute a cash operation in this layout test.
      await tester.tapAt(const Offset(4, 800));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Abrir menú principal'));
      await tester.pumpAndSettle();
      expect(find.text('Turno'), findsNothing);
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant({TargetPlatform.android, TargetPlatform.iOS}),
  );

  testWidgets(
    'narrow Windows keeps the original controls',
    (tester) async {
      await _pumpScreen(tester, viewport: const Size(390, 844));
      expect(find.byKey(const ValueKey('phone-sales-header')), findsNothing);
      expect(find.byTooltip('Tickets'), findsNothing);
      expect(find.byType(MobileSalesProductCard), findsNothing);
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );

  testWidgets('phone line editor remains usable with keyboard and square controls', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await _pumpScreen(tester, viewport: const Size(390, 844));
    final lineName = find.text('Cable de prueba').last;
    await tester.ensureVisible(lineName);
    await tester.pumpAndSettle();
    await tester.tap(lineName);
    // The row supports both tap and double-tap; let the gesture recognizer
    // resolve its double-tap window before expecting the editor route.
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    final dialog = find.byType(Dialog);
    expect(dialog, findsOneWidget, reason: tester.allWidgets.map((w) => w.runtimeType.toString())
      .where((name) => name.contains('Dialog') || name.contains('Entry') || name.contains('Edit')).toSet().join(', '));
    final shape = tester.widget<Dialog>(dialog).shape! as RoundedRectangleBorder;
    expect(shape.borderRadius, BorderRadius.circular(1));
    await _savePhonePreview(tester, 'pos-square-item-discount');
    final fields = find.descendant(of: dialog, matching: find.byType(TextField));
    await tester.tap(fields.first);
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpAndSettle();
    await tester.ensureVisible(fields.first);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(MobileSalesLineEditorContent), findsOneWidget);
    await tester.tap(find.descendant(of: dialog, matching: find.byTooltip('Cerrar')));
    await tester.pumpAndSettle();
    expect(dialog, findsNothing);
  }, variant: TargetPlatformVariant({TargetPlatform.android, TargetPlatform.iOS}));

  testWidgets(
    'una empresa nueva no muestra el selector ni el aviso de numeración',
    (tester) async {
      await _pumpScreen(tester, ready: false);
      expect(find.text('COMPROBANTE ELECTRÓNICO'), findsNothing);
      expect(
        find.textContaining('Comprobante electrónico no disponible'),
        findsNothing,
      );
    },
  );

  testWidgets('discount dialog cancels safely and checkout keeps the detail selection', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await _pumpScreen(tester, quotationEditor: false);
    final originalMode = tester.widget<EcfPosFiscalSelector>(find.byType(EcfPosFiscalSelector)).selected;
    final collect = find.widgetWithText(FilledButton, 'Cobrar');
    final discountGesture = find.ancestor(of: collect, matching: find.byWidgetPredicate((w) => w is GestureDetector && w.onDoubleTap != null)).first;
    tester.widget<GestureDetector>(discountGesture).onDoubleTap!();
    for (var i = 0; i < 12; i++) { await tester.pump(const Duration(milliseconds: 100)); }
    expect(find.text('Descuento general'), findsOneWidget);
    final applyDiscount = find.widgetWithText(FilledButton, 'Aplicar descuento');
    final applyWidget = tester.widget<FilledButton>(applyDiscount);
    final shape = (applyWidget.style?.shape ?? FilledButtonTheme.of(tester.element(applyDiscount)).style!.shape)!.resolve({}) as RoundedRectangleBorder;
    expect(shape.borderRadius, BorderRadius.circular(1));
    expect(tester.getSize(applyDiscount).height, 44);
    expect(tester.getSize(find.byWidgetPredicate((w) => w is SegmentedButton)).height, 44);
    expect(tester.getSize(find.descendant(of: find.byType(Dialog), matching: find.byType(TextField))).height, 44);
    await _savePhonePreview(tester, 'pos-square-general-discount');
    await tester.tap(find.byTooltip('Cerrar').last);
    for (var i = 0; i < 12; i++) { await tester.pump(const Duration(milliseconds: 100)); }
    await tester.tap(collect);
    for (var i = 0; i < 12; i++) { await tester.pump(const Duration(milliseconds: 100)); }
    expect(find.byType(Dialog), findsOneWidget);
    expect(find.descendant(of: find.byType(Dialog), matching: find.byType(EcfPosFiscalSelector)), findsNothing);
    await _savePhonePreview(tester, 'pos-square-desktop-checkout');
    await tester.tap(find.text('Cancelar'));
    for (var i = 0; i < 12; i++) { await tester.pump(const Duration(milliseconds: 100)); }
    expect(tester.widget<EcfPosFiscalSelector>(find.byType(EcfPosFiscalSelector)).selected, originalMode);
    expect(tester.takeException(), isNull);
  });

  testWidgets('muestra el selector cuando el servidor devuelve capacidades', (
    tester,
  ) async {
    await _pumpScreen(tester);

    // La integración de ramas debe conservar la interfaz aprobada en la
    // pantalla real, además del selector fiscal. Probar solo los componentes
    // por separado no detecta que el POS haya dejado de utilizarlos.
    expect(find.byType(SalesCatalogCommandBar), findsOneWidget);
    expect(find.byType(SalesDetailHeader), findsOneWidget);
    expect(find.byType(SalesClientSelector), findsOneWidget);
    expect(find.byType(SalesDetailShortcut), findsNWidgets(2));

    expect(
      find.byType(EcfPosFiscalSelector).hitTestable(),
      findsOneWidget,
      reason: 'el selector debe estar visible en el carrito',
    );
    expect(
      tester
          .widget<EcfPosFiscalSelector>(find.byType(EcfPosFiscalSelector))
          .modes,
      containsAll([EcfPosFiscalMode.e31, EcfPosFiscalMode.e32]),
    );
    expect(
      find.textContaining('Comprobante electrónico no disponible'),
      findsNothing,
      reason: 'las capacidades llegaron: no debe avisarse de que no hay tipos',
    );
  });
  testWidgets(
    'Normal defaults on a new ticket after an explicit electronic selection',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      await _pumpScreen(tester, quotationEditor: false);
      EcfPosFiscalSelector selector() => tester.widget<EcfPosFiscalSelector>(
        find.byType(EcfPosFiscalSelector).first,
      );
      expect(selector().selected, EcfPosFiscalMode.normal);
      selector().onSelected(EcfPosFiscalMode.e32);
      await tester.pump();
      expect(selector().selected, EcfPosFiscalMode.e32);
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.sendKeyEvent(LogicalKeyboardKey.f5);
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(selector().selected, EcfPosFiscalMode.normal);
      expect(tester.takeException(), isNull);
      final output = Platform.environment['FULLPOS_ECF_NORMAL_QA'];
      if (output != null) {
        final boundary =
            _capture.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        await tester.runAsync(() async {
          final picture = await boundary.toImage();
          final bytes = await picture.toByteData(
            format: ui.ImageByteFormat.png,
          );
          await Directory(output).create(recursive: true);
          await File(
            '$output/normal-new-ticket-1280.png',
          ).writeAsBytes(bytes!.buffer.asUint8List());
          picture.dispose();
        });
      }
      debugDefaultTargetPlatformOverride = null;
    },
  );
}
