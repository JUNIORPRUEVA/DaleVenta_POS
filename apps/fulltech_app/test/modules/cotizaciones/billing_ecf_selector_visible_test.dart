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
import 'package:daleventa_pos/core/usage/client_telemetry_headers.dart';
import 'package:daleventa_pos/features/ecf/data/ecf_repository.dart';
import 'package:daleventa_pos/features/ecf/ecf_models.dart';
import 'package:daleventa_pos/features/price_lists/data/price_lists_repository.dart';
import 'package:daleventa_pos/modules/cotizaciones/cotizacion_models.dart';
import 'package:daleventa_pos/modules/cotizaciones/cotizaciones_screen.dart';
import 'package:daleventa_pos/modules/cotizaciones/presentation/widgets/sales_catalog_command_bar.dart';
import 'package:daleventa_pos/modules/cotizaciones/presentation/widgets/sales_client_selector.dart';
import 'package:daleventa_pos/modules/cotizaciones/presentation/widgets/sales_detail_header.dart';
import 'package:daleventa_pos/modules/cotizaciones/presentation/widgets/sales_detail_shortcut.dart';
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
  @override
  Future<ResponseBody> fetch(
    RequestOptions request,
    Stream<Uint8List>? stream,
    Future<void>? cancel,
  ) async {
    return ResponseBody.fromString(
      jsonEncode({
        'items': [
          {
            'id': _productId,
            'nombre': 'Cable de prueba',
            'precio': 900,
            'costo': 400,
            'categoria': 'Prueba',
            'trackInventory': false,
          },
        ],
        'total': 1,
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
}) async {
  tester.view.physicalSize = const Size(1280, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final dio = Dio(BaseOptions(baseUrl: 'https://billing.example.test'));
  dio.httpClientAdapter = _Catalog();
  final container = ProviderContainer(
    overrides: [
      dioProvider.overrideWithValue(dio),
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
      find.text('COMPROBANTE ELECTRÓNICO'),
      findsOneWidget,
      reason: 'el selector debe estar visible en el carrito',
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
