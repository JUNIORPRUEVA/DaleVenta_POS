import 'package:daleventa_pos/core/auth/auth_provider.dart';
import 'package:daleventa_pos/core/company/company_settings_model.dart';
import 'package:daleventa_pos/core/company/company_settings_repository.dart';
import 'package:daleventa_pos/core/theme/app_theme.dart';
import 'package:daleventa_pos/core/models/user_model.dart';
import 'package:daleventa_pos/core/routing/routes.dart';
import 'package:daleventa_pos/modules/ventas/data/ventas_repository.dart';
import 'package:daleventa_pos/modules/ventas/sales_models.dart';
import 'package:daleventa_pos/modules/ventas/tpv_sales_history_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:go_router/go_router.dart';

import '../../support/platform_goldens.dart';

class _Auth extends AuthController {
  _Auth(super.ref, {UserModel? user}) {
    state = AuthState(
      initialized: true,
      isAuthenticated: user != null,
      user: user,
    );
  }
}

SaleModel _sale(
  String id,
  String customer, {
  bool returned = false,
  bool fiscal = false,
}) => SaleModel.fromJson({
  'id': id,
  'userId': 'cashier',
  'userName': 'María Santos',
  'customer': {'id': id, 'nombre': customer},
  'customerName': customer,
  'saleDate': '2026-11-13T14:30:00Z',
  'paymentMethod': 'cash',
  'totalSold': 1250,
  'totalCost': 750,
  'totalProfit': 500,
  'returnStatus': returned ? 'RETURNED' : 'ACTIVE',
  'canReturn': !returned,
  'returnedAmount': returned ? 1250 : 0,
  if (fiscal) ...{
    'fiscalVoucherType': 'B01',
    'ncf': 'B0100000001',
    'fiscalCustomerTaxId': '101000001',
    'fiscalCustomerName': 'Cliente fiscal de prueba con nombre largo',
  },
  'items': [
    {
      'id': 'item-$id',
      'productNameSnapshot': 'Producto de prueba con nombre largo',
      'qty': 2,
      'priceSoldUnit': 625,
      'subtotalSold': 1250,
    },
  ],
});

class _Repository implements VentasRepository {
  _Repository({this.empty = false, this.fail = false});
  final bool empty;
  final bool fail;
  int loads = 0;
  final rows = [
    _sale('INV-001', 'Comercial del Caribe'),
    _sale('INV-002', 'Cliente con un nombre comercial bastante largo'),
    _sale('INV-003', 'Cliente devolución', returned: true),
  ];
  SalesPageResult page(List<SaleModel> items) => SalesPageResult(
    items: items,
    page: 1,
    limit: 50,
    hasMore: false,
    nextPage: null,
  );
  @override
  Future<SalesPageResult> cachedInvoicesPage({
    required DateTime from,
    required DateTime to,
    String? customerId,
    bool includeDeleted = true,
    int page = 1,
    int limit = 50,
  }) async => this.page(const []);
  @override
  Future<SalesPageResult> listInvoicesPage({
    required DateTime from,
    required DateTime to,
    String? customerId,
    bool includeDeleted = true,
    int page = 1,
    int limit = 50,
  }) async {
    loads++;
    if (fail) throw StateError('offline');
    return this.page(empty ? const [] : rows);
  }

  @override
  Future<SalesSummaryModel> summary({
    required DateTime from,
    required DateTime to,
    String? userId,
    String? customerId,
  }) async => const SalesSummaryModel(
    totalSales: 40,
    totalSold: 50000,
    totalCost: 30000,
    totalProfit: 20000,
    totalCommission: 0,
  );
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('$invocation');
}

Future<void> _pump(
  WidgetTester tester,
  Size size,
  _Repository repo, {
  double textScale = 1,
  GoRouter? router,
  UserModel? user,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authStateProvider.overrideWith((ref) => _Auth(ref, user: user)),
        companySettingsProvider.overrideWith(
          (ref) async => CompanySettings.empty(),
        ),
        ventasRepositoryProvider.overrideWithValue(repo),
      ],
      child: router == null
          ? MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: AppTheme.light,
              localizationsDelegates: GlobalMaterialLocalizations.delegates,
              supportedLocales: const [Locale('es', 'DO')],
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(textScale)),
                child: child!,
              ),
              home: const TpvSalesHistoryScreen(),
            )
          : MaterialApp.router(
              routerConfig: router,
              theme: AppTheme.light,
              localizationsDelegates: GlobalMaterialLocalizations.delegates,
              supportedLocales: const [Locale('es', 'DO')],
            ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('es_DO');
    final font = FontLoader('Manrope');
    for (final weight in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
      font.addFont(rootBundle.load('assets/fonts/manrope/Manrope-$weight.ttf'));
    }
    await font.load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
  for (final width in [1920.0, 1280.0, 960.0, 760.0, 390.0]) {
    testWidgets('historial conserva lista y acciones a $width px', (
      tester,
    ) async {
      await _pump(tester, Size(width, 900), _Repository());
      // Set the range through the real filter so goldens do not depend on today.
      await tester.tap(
        width < 760 ? find.byTooltip('Filtros') : find.text('Filtro'),
      );
      await tester.pumpAndSettle();
      for (final entry in {
        'Desde': DateTime(2026, 11, 1),
        'Hasta': DateTime(2026, 11, 13),
      }.entries) {
        await tester.tap(find.text(entry.key));
        await tester.pumpAndSettle();
        final localizations = MaterialLocalizations.of(
          tester.element(find.byType(DatePickerDialog)),
        );
        await tester.tap(
          find.byTooltip(localizations.inputDateModeButtonLabel),
        );
        await tester.pumpAndSettle();
        await tester.enterText(
          find.descendant(
            of: find.byType(DatePickerDialog),
            matching: find.byType(TextField),
          ),
          localizations.formatCompactDate(entry.value),
        );
        await tester.tap(
          find.descendant(
            of: find.byType(DatePickerDialog),
            matching: find.text('Aplicar'),
          ),
        );
        await tester.pumpAndSettle();
      }
      await tester.tap(find.text('Aplicar'));
      await tester.pumpAndSettle();
      expect(find.text('Historial de ventas'), findsOneWidget);
      expect(find.textContaining('INV001'), findsWidgets);
      if (width >= 760) {
        expect(
          tester.getSize(find.byType(TextField).first).width,
          lessThanOrEqualTo(560),
        );
        // Keep the original layout: metrics in the AppBar and one toolbar row.
        expect(
          tester.getRect(find.text('FACTURAS DEL PERÍODO')).bottom,
          lessThanOrEqualTo(56),
        );
        expect(tester.getRect(find.byType(TextField).first).top, lessThan(80));
        expect(
          tester.getRect(find.text('Filtro')).center.dy,
          closeTo(tester.getRect(find.byType(TextField).first).center.dy, 2),
        );
      }
      expect(tester.takeException(), isNull);
      await expectLater(
        find.byType(Scaffold).first,
        matchesGoldenFile(
          platformGolden('goldens/sales_history_${width.toInt()}.png'),
        ),
      );
    });
  }
  testWidgets('buscar, limpiar, seleccionar y filtros mantienen sus acciones', (
    tester,
  ) async {
    final repo = _Repository();
    await _pump(tester, const Size(1280, 900), repo);
    await tester.enterText(find.byType(TextField).first, 'INV-002');
    await tester.pumpAndSettle();
    expect(find.text('Factura INV001'), findsNothing);
    expect(find.text('Factura INV002'), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, '');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Factura INV002'));
    await tester.pumpAndSettle();
    expect(find.text('INV002'), findsOneWidget);
    expect(find.byTooltip('Imprimir'), findsWidgets);
    expect(find.byTooltip('PDF'), findsWidgets);
    expect(find.text('Devolver'), findsOneWidget);
    final row = find
        .ancestor(
          of: find.text('Factura INV002'),
          matching: find.byType(InkWell),
        )
        .first;
    expect(
      find.descendant(of: row, matching: find.byType(IconButton)),
      findsNWidgets(2),
    );
    expect(
      find.descendant(of: row, matching: find.byTooltip('PDF')),
      findsNothing,
    );
    expect(find.byTooltip('Ver detalle'), findsNothing);
    expect(find.text('ACTIVA'), findsOneWidget);
    expect(find.text('María Santos'), findsOneWidget);
    for (final finder in [
      find.ancestor(
        of: find.text('Devolver'),
        matching: find.byType(FilledButton),
      ),
      find.ancestor(
        of: find.text('Imprimir'),
        matching: find.byType(OutlinedButton),
      ),
      find.descendant(
        of: find.byTooltip('PDF'),
        matching: find.byType(OutlinedButton),
      ),
    ]) {
      final button = tester.widget<ButtonStyleButton>(finder);
      final shape = button.style!.shape!.resolve({})! as RoundedRectangleBorder;
      expect(shape.borderRadius, BorderRadius.zero);
      expect(tester.getRect(finder).height, 40);
    }
    await tester.tap(find.text('Filtro'));
    await tester.pumpAndSettle();
    expect(find.text('Aplicar'), findsOneWidget);
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Limpiar'));
    await tester.pumpAndSettle();
    expect(repo.loads, greaterThan(1));
    expect(tester.takeException(), isNull);
  });
  for (final fail in [false, true]) {
    testWidgets('estado ${fail ? 'error' : 'vacío'} permite reintentar', (
      tester,
    ) async {
      final repo = _Repository(empty: true, fail: fail);
      await _pump(tester, const Size(960, 800), repo);
      expect(find.text('Vender ahora'), fail ? findsNothing : findsOneWidget);
      if (fail) {
        await tester.tap(find.text('Reintentar'));
        await tester.pumpAndSettle();
        expect(repo.loads, 2);
      } else {
        expect(find.text('Actualizar'), findsNothing);
        expect(repo.loads, 1);
      }
      expect(tester.takeException(), isNull);
    });
  }
  for (final width in [1024.0, 1920.0, 2560.0]) {
    testWidgets('columna cajero se adapta al espacio real: $width', (
      tester,
    ) async {
      await _pump(tester, Size(width, 800), _Repository());
      expect(
        find.byKey(const ValueKey('history-cashier-INV-001')),
        width >= 1920 ? findsOneWidget : findsNothing,
      );
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('texto ampliado en portátil mantiene los controles', (
    tester,
  ) async {
    await _pump(tester, const Size(960, 900), _Repository(), textScale: 1.3);
    expect(tester.takeException(), isNull);
  });
  for (final size in [
    const Size(1024, 560),
    const Size(1024, 600),
    const Size(1280, 720),
  ]) {
    testWidgets('pantalla pequeña $size conserva detalle y acciones', (
      tester,
    ) async {
      await _pump(tester, size, _Repository(), textScale: 1.15);
      expect(find.text('Subtotal'), findsOneWidget);
      expect(find.text('Devolver').hitTestable(), findsOneWidget);
      expect(find.text('Imprimir').hitTestable(), findsOneWidget);
      expect(find.byTooltip('PDF').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('detalle fiscal completo se desplaza sin ocultar los botones', (
    tester,
  ) async {
    final repo = _Repository();
    repo.rows[0] = _sale('INV-001', 'Comercial del Caribe', fiscal: true);
    await _pump(tester, const Size(1024, 560), repo, textScale: 1.15);
    await tester.ensureVisible(
      find.text('Cliente fiscal de prueba con nombre largo'),
    );
    await tester.pumpAndSettle();
    expect(find.text('Devolver').hitTestable(), findsOneWidget);
    expect(find.text('Imprimir').hitTestable(), findsOneWidget);
    expect(find.byTooltip('PDF').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  for (final authorized in [true, false]) {
    testWidgets('Vender ahora respeta el acceso a Facturación: $authorized', (
      tester,
    ) async {
      final router = GoRouter(
        initialLocation: '/historial-diseno',
        routes: [
          GoRoute(
            path: '/historial-diseno',
            builder: (_, __) => const TpvSalesHistoryScreen(),
          ),
          GoRoute(
            path: Routes.cotizaciones,
            builder: (_, __) =>
                const Scaffold(body: Text('Facturación existente')),
          ),
        ],
      );
      addTearDown(router.dispose);
      final user = authorized
          ? UserModel(
              id: 'admin-prueba',
              email: 'admin@test.local',
              nombreCompleto: 'Admin de prueba',
              telefono: '',
              role: 'ADMIN',
              companyId: 'empresa-prueba',
            )
          : null;
      final repo = _Repository();
      await _pump(
        tester,
        const Size(1024, 600),
        repo,
        router: router,
        user: user,
      );
      await tester.enterText(find.byType(TextField).first, 'sin-coincidencias');
      await tester.pumpAndSettle();
      expect(find.text('Vender ahora'), findsOneWidget);
      await tester.tap(find.text('Vender ahora'));
      await tester.pumpAndSettle();
      expect(
        find.text('Facturación existente'),
        authorized ? findsOneWidget : findsNothing,
      );
      expect(repo.loads, 1);
      expect(tester.takeException(), isNull);
    });
  }
}
