import 'dart:async';
import 'dart:convert';

import 'package:daleventa_pos/core/auth/auth_provider.dart';
import 'package:daleventa_pos/core/auth/auth_repository.dart';
import 'package:daleventa_pos/core/auth/auth_interceptor.dart';
import 'package:daleventa_pos/core/auth/auth_session_events.dart';
import 'package:daleventa_pos/core/auth/token_storage.dart';
import 'package:daleventa_pos/core/company/company_settings_model.dart';
import 'package:daleventa_pos/core/company/company_settings_repository.dart';
import 'package:daleventa_pos/core/models/user_model.dart';
import 'package:daleventa_pos/core/theme/app_theme.dart';
import 'package:daleventa_pos/core/usage/client_telemetry_headers.dart';
import 'package:daleventa_pos/features/price_lists/data/price_lists_repository.dart';
import 'package:daleventa_pos/modules/cotizaciones/cotizacion_models.dart';
import 'package:daleventa_pos/modules/cotizaciones/cotizaciones_screen.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:package_info_plus/package_info_plus.dart';

const _productId = '11111111-1111-4111-8111-111111111111';

class _MemoryStorage extends TokenStorage {
  int clears = 0;
  bool hasAccessToken = true;
  @override
  Future<UserModel?> getUserSnapshot() async => null;
  @override
  Future<String?> getAccessToken() async =>
      hasAccessToken ? 'expired-test-token' : null;
  @override
  Future<String?> getRefreshToken() async => null;
  @override
  Future<void> clearTokens() async {
    clears++;
    hasAccessToken = false;
  }
}

class _Responses implements HttpClientAdapter {
  _Responses(this.expiredSession);
  final bool expiredSession;
  @override
  Future<ResponseBody> fetch(
    RequestOptions request,
    Stream<Uint8List>? stream,
    Future<void>? cancel,
  ) async {
    final expired = expiredSession && request.path.contains('resolve');
    return ResponseBody.fromString(
      jsonEncode(
        expired
            ? {'message': 'Unauthorized'}
            : {
                'items': [
                  {
                    'id': _productId,
                    'nombre': 'Cable de prueba',
                    'precio': 100,
                    'costo': 40,
                    'categoria': 'Prueba',
                    'trackInventory': false,
                  },
                ],
                'total': 1,
                'page': 1,
                'hasMore': false,
              },
      ),
      expired ? 401 : 200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

class _Auth extends AuthController {
  _Auth(super.ref) {
    state = AuthState(
      initialized: true,
      isAuthenticated: true,
      user: UserModel(
        id: 'billing-test-user',
        email: 'billing@example.test',
        nombreCompleto: 'Prueba',
        telefono: '',
        role: 'ADMIN',
        companyId: 'billing-test-company',
      ),
    );
  }
}

class _PendingPricing extends PriceListsRepository {
  _PendingPricing() : super(Dio());
  final requests = <Completer<ResolvedPriceLine>>[];
  final quantities = <double>[];

  @override
  Future<List<PriceListModel>> fetchPriceLists() async => const [];

  @override
  Future<ResolvedPriceLine> resolveLine({
    required String productId,
    required double qty,
    String? priceListId,
    String? clientId,
  }) {
    final pending = Completer<ResolvedPriceLine>();
    requests.add(pending);
    quantities.add(qty);
    return pending.future;
  }

  void complete(int index, double price) => requests[index].complete(
    ResolvedPriceLine(
      applied: true,
      unitPrice: price,
      originalUnitPrice: 100,
      reason: 'test',
    ),
  );
}

Future<_PendingPricing> _pumpBilling(
  WidgetTester tester, {
  bool expiredSession = false,
}) async {
  SharedPreferences.setMockInitialValues({});
  tester.view.physicalSize = const Size(1280, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final pricing = _PendingPricing();
  final storage = _MemoryStorage();
  final events = AuthSessionEvents();
  final dio = Dio(BaseOptions(baseUrl: 'https://billing.example.test'));
  dio.httpClientAdapter = _Responses(expiredSession);
  if (expiredSession) {
    dio.interceptors.add(AuthInterceptor(storage, events, dio));
  }
  final quotation = CotizacionModel(
    id: '',
    createdAt: DateTime(2026, 10, 18),
    customerId: null,
    customerName: 'Sin cliente',
    customerPhone: '',
    note: '',
    includeItbis: false,
    itbisRate: 0,
    items: const [
      CotizacionItem(
        productId: _productId,
        nombre: 'Cable de prueba',
        imageUrl: null,
        unitPrice: 80,
        originalUnitPrice: 100,
        qty: 1,
      ),
    ],
  );
  final container = ProviderContainer(
    overrides: [
      dioProvider.overrideWithValue(dio),
      tokenStorageProvider.overrideWithValue(storage),
      authSessionEventsProvider.overrideWith((_) => events),
      authStateProvider.overrideWith(_Auth.new),
      companySettingsProvider.overrideWith(
        (_) async =>
            CompanySettings.empty().copyWith(wholesalePriceListsEnabled: true),
      ),
      priceListsRepositoryProvider.overrideWithValue(
        expiredSession ? PriceListsRepository(dio) : pricing,
      ),
    ],
  );
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: AppTheme.light,
        home: CotizacionesScreen(
          initialQuotation: quotation,
          returnSavedQuotation: true,
        ),
      ),
    ),
  );
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
    container.dispose();
    dio.close(force: true);
  });
  return pricing;
}

void _press(WidgetTester tester, String tooltip) {
  final button = tester.widget<IconButton>(
    find.descendant(
      of: find.byTooltip(tooltip).last,
      matching: find.byType(IconButton),
    ),
  );
  button.onPressed!();
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
    // Platform futures must finish outside the widget test's fake clock before
    // AuthInterceptor caches them for requests started by the screen.
    await ClientTelemetryHeaders.instance.headers();
    final loader = FontLoader('Manrope')
      ..addFont(rootBundle.load('assets/fonts/manrope/Manrope-Regular.ttf'))
      ..addFont(rootBundle.load('assets/fonts/manrope/Manrope-Bold.ttf'));
    await loader.load();
  });
  testWidgets('typed quantity in the line editor requests the wholesale tier', (
    tester,
  ) async {
    final pricing = await _pumpBilling(tester);
    final line = find.ancestor(
      of: find.byTooltip('Quitar de la venta'),
      matching: find.byType(InkWell),
    );
    tester
        .widgetList<InkWell>(line)
        .singleWhere((widget) => widget.onDoubleTap != null)
        .onDoubleTap!();
    await tester.pump(const Duration(milliseconds: 300));
    final fields = find.descendant(
      of: find.byType(Dialog),
      matching: find.byType(TextField),
    );
    await tester.enterText(fields.first, '15');
    tester
        .widget<FilledButton>(
          find.descendant(
            of: find.byType(Dialog),
            matching: find.byType(FilledButton),
          ),
        )
        .onPressed!();
    await tester.pump(const Duration(milliseconds: 300));
    expect(pricing.quantities, [15]);
    pricing.complete(0, 70);
    await tester.pump();
    expect(find.textContaining('1,050.00'), findsWidgets);
  });

  testWidgets(
    'editing only a manual discount does not replace it with wholesale pricing',
    (tester) async {
      final pricing = await _pumpBilling(tester);
      final line = find.ancestor(
        of: find.byTooltip('Quitar de la venta'),
        matching: find.byType(InkWell),
      );
      tester
          .widgetList<InkWell>(line)
          .singleWhere((widget) => widget.onDoubleTap != null)
          .onDoubleTap!();
      await tester.pump(const Duration(milliseconds: 300));
      final fields = find.descendant(
        of: find.byType(Dialog),
        matching: find.byType(TextField),
      );
      await tester.enterText(fields.last, '30');
      tester
          .widget<FilledButton>(
            find.descendant(
              of: find.byType(Dialog),
              matching: find.byType(FilledButton),
            ),
          )
          .onPressed!();
      await tester.pump(const Duration(milliseconds: 300));
      expect(pricing.quantities, isEmpty);
      expect(find.textContaining('70.00'), findsWidgets);
    },
  );
  testWidgets(
    'late older response cannot replace the latest cart quantities and prices',
    (tester) async {
      final pricing = await _pumpBilling(tester);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(CotizacionesScreen)),
      );
      expect(
        container
            .read(companySettingsProvider)
            .valueOrNull
            ?.wholesalePriceListsEnabled,
        isTrue,
      );
      expect(
        const CotizacionItem(
          productId: _productId,
          nombre: 'Cable',
          imageUrl: null,
          unitPrice: 80,
          qty: 1,
        ).isExternal,
        isFalse,
      );
      _press(tester, 'Sumar unidad');
      await tester.pump();
      _press(tester, 'Sumar unidad');
      await tester.pump();
      expect(pricing.quantities, [2, 3]);
      pricing.complete(1, 70);
      await tester.pump();
      expect(find.textContaining('210.00'), findsWidgets);
      pricing.complete(0, 90);
      await tester.pump();
      expect(find.textContaining('210.00'), findsWidgets);
      expect(find.textContaining('180.00'), findsNothing);
    },
  );

  testWidgets(
    'removing a line prevents its pending response from restoring it',
    (tester) async {
      final pricing = await _pumpBilling(tester);
      _press(tester, 'Sumar unidad');
      await tester.pump();
      expect(pricing.quantities, [2]);
      _press(tester, 'Quitar de la venta');
      await tester.pump();
      expect(find.text('Agrega productos desde el catálogo'), findsOneWidget);
      pricing.complete(0, 70);
      await tester.pump();
      expect(find.text('Agrega productos desde el catálogo'), findsOneWidget);
      expect(find.byTooltip('Sumar unidad'), findsNothing);
    },
  );

  testWidgets(
    'decreasing quantity to zero invalidates every pending calculation',
    (tester) async {
      final pricing = await _pumpBilling(tester);
      _press(tester, 'Sumar unidad');
      await tester.pump();
      _press(tester, 'Restar unidad');
      await tester.pump();
      _press(tester, 'Restar unidad');
      await tester.pump();
      expect(pricing.quantities, [2, 1]);
      pricing.complete(1, 80);
      pricing.complete(0, 70);
      await tester.pump();
      expect(find.text('Agrega productos desde el catálogo'), findsOneWidget);
    },
  );

  testWidgets('expired session during pricing clears the old tenant cart', (
    tester,
  ) async {
    await _pumpBilling(tester, expiredSession: true);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(CotizacionesScreen)),
    );
    await tester.runAsync(() async {
      _press(tester, 'Sumar unidad');
      // Let Dio and platform futures finish on the real event queue; awaiting
      // a Completer created by the fake clock here would deadlock the test.
      await pumpEventQueue();
    });
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(container.read(authStateProvider).isAuthenticated, isFalse);
    expect((container.read(tokenStorageProvider) as _MemoryStorage).clears, 1);
    expect(await container.read(tokenStorageProvider).getAccessToken(), isNull);
    expect(find.text('Agrega productos desde el catálogo'), findsOneWidget);
    expect(find.byTooltip('Sumar unidad'), findsNothing);
  });
}
