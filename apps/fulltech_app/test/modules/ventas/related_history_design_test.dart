import 'package:daleventa_pos/core/auth/auth_provider.dart';
import 'package:daleventa_pos/core/company/company_settings_model.dart';
import 'package:daleventa_pos/core/company/company_settings_repository.dart';
import 'package:daleventa_pos/core/models/user_model.dart';
import 'package:daleventa_pos/core/pagination/paged_result.dart';
import 'package:daleventa_pos/core/printing/models/ticket_data.dart';
import 'package:daleventa_pos/core/theme/app_theme.dart';
import 'package:daleventa_pos/core/widgets/history_presentation.dart';
import 'package:daleventa_pos/core/widgets/history_filter_panel.dart';
import 'package:daleventa_pos/modules/clientes/cliente_model.dart';
import 'package:daleventa_pos/modules/cash/cash_providers.dart';
import 'package:daleventa_pos/modules/cash/cash_turn_menu_button.dart';
import 'package:daleventa_pos/modules/clientes/data/clientes_repository.dart';
import 'package:daleventa_pos/modules/cotizaciones/cotizacion_models.dart';
import 'package:daleventa_pos/modules/cotizaciones/cotizaciones_historial_screen.dart';
import 'package:daleventa_pos/modules/cotizaciones/data/cotizaciones_repository.dart';
import 'package:daleventa_pos/modules/ventas/data/ventas_repository.dart';
import 'package:daleventa_pos/modules/ventas/sales_credit_screen.dart';
import 'package:daleventa_pos/modules/ventas/sales_models.dart';
import 'package:daleventa_pos/modules/ventas/credit_history_filters.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:go_router/go_router.dart';
import 'package:daleventa_pos/core/routing/routes.dart';

import '../../support/platform_goldens.dart';

class _Auth extends AuthController {
  _Auth(super.ref, {String role = 'ADMIN'}) {
    state = AuthState(
      initialized: true,
      isAuthenticated: true,
      user: UserModel(
        id: 'admin-prueba',
        email: 'admin@test.local',
        nombreCompleto: 'Ana Santos',
        telefono: '',
        role: role,
        companyId: 'empresa-prueba',
      ),
    );
  }
}

class _Credits implements VentasRepository {
  final rows = List.generate(
    3,
    (index) => SaleModel.fromJson({
      'id': 'CRE-00$index',
      'userId': 'admin-prueba',
      'userName': 'Ana Santos',
      'customerName': index == 0 ? 'Comercial del Caribe' : 'Cliente $index',
      'customer': {
        'id': 'client-$index',
        'nombre': index == 0 ? 'Comercial del Caribe' : 'Cliente $index',
      },
      'saleDate': '2026-11-13T14:30:00Z',
      'paymentMethod': 'credit',
      'totalSold': 1250,
      'creditBalance': 1000,
      'creditPaidAmount': 250,
      'items': [
        {
          'id': 'item-$index',
          'productNameSnapshot': 'Producto de prueba',
          'qty': 2,
          'priceSoldUnit': 625,
          'subtotalSold': 1250,
        },
      ],
    }),
  );
  @override
  Future<List<SaleModel>> cachedCredits() async => [];
  @override
  Future<List<SaleModel>> listCredits({bool includePaid = false}) async => rows;
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('${invocation.memberName}');
}

class _Quotes implements CotizacionesRepository {
  final rows = List.generate(
    3,
    (index) => CotizacionModel(
      id: 'COT-00$index',
      createdAt: DateTime(2026, 11, 13, 10),
      createdByUserId: 'admin-prueba',
      createdByUserName: 'Ana Santos',
      customerId: 'client-$index',
      customerName: index == 0 ? 'Comercial del Caribe' : 'Cliente $index',
      customerPhone: '',
      note: '',
      includeItbis: false,
      itbisRate: 0.18,
      items: const [
        CotizacionItem(
          productId: 'producto',
          nombre: 'Producto de prueba',
          imageUrl: '',
          unitPrice: 625,
          qty: 2,
        ),
      ],
    ),
  );
  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #getCachedList) {
      return Future.value(<CotizacionModel>[]);
    }
    if (invocation.memberName == #upsertLocal) return Future<void>.value();
    if (invocation.memberName == #listPage) {
      final query = (invocation.namedArguments[#search] as String? ?? '')
          .toLowerCase();
      return Future.value(
        PagedResult<CotizacionModel>(
          items: rows
              .where((row) => row.customerName.toLowerCase().contains(query))
              .toList(),
          page: 1,
          limit: 50,
          hasMore: false,
        ),
      );
    }
    throw UnsupportedError('${invocation.memberName}');
  }
}

class _Cash extends ActiveCashSessionController {
  _Cash(super.ref);
  @override
  Future<void> refresh({bool silent = false}) async {
    state = const AsyncData(null);
  }
}

class _Clients implements ClientesRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => Future.value(<ClienteModel>[]);
}

Future<void> _pump(
  WidgetTester tester,
  bool credit,
  Size size, {
  double scale = 1,
  bool empty = false,
  bool live = false,
  bool admin = true,
  VentasRepository? credits,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authStateProvider.overrideWith(
          (ref) => _Auth(ref, role: admin ? 'ADMIN' : 'CAJERO'),
        ),
        companySettingsProvider.overrideWith(
          (ref) async => CompanySettings.empty(),
        ),
        ventasRepositoryProvider.overrideWithValue(
          credits ?? (empty ? (_Credits()..rows.clear()) : _Credits()),
        ),
        activeCashSessionControllerProvider.overrideWith((ref) => _Cash(ref)),
        cotizacionesRepositoryProvider.overrideWithValue(
          empty ? (_Quotes()..rows.clear()) : _Quotes(),
        ),
        clientesRepositoryProvider.overrideWithValue(_Clients()),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        supportedLocales: const [Locale('es', 'DO')],
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: TickerMode(enabled: !credit || live, child: child!),
        ),
        home: credit
            ? const SalesCreditScreen()
            : const CotizacionesHistorialScreen(),
      ),
    ),
  );
  if (live) {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
  } else {
    await tester.pumpAndSettle();
  }
  await tester.runAsync(() async {
    final context = tester.element(
      find.byType(credit ? SalesCreditScreen : CotizacionesHistorialScreen),
    );
    for (final name in ['back', 'search', 'filter', 'refresh', 'more']) {
      await precacheImage(
        AssetImage('assets/image/mobile_navigation/$name.png'),
        context,
      );
    }
  });
  await tester.pump();
}

void main() {
  test('créditos: rango inclusivo, estado y cajero se combinan', () {
    final sale = _Credits().rows.first;
    expect(
      CreditHistoryFilters(
        from: DateTime(2026, 11, 13),
        to: DateTime(2026, 11, 13),
        status: 1,
      ).matches(sale),
      isTrue,
    );
    expect(
      CreditHistoryFilters(from: DateTime(2026, 11, 14)).matches(sale),
      isFalse,
    );
    expect(
      CreditHistoryFilters(to: DateTime(2026, 11, 12)).matches(sale),
      isFalse,
    );
    expect(const CreditHistoryFilters(status: 2).matches(sale), isFalse);
    expect(
      const CreditHistoryFilters(cashier: 'Otro cajero').matches(sale),
      isFalse,
    );
    expect(
      CreditHistoryFilters(
        cashier: sale.userName ?? sale.userId,
        status: 1,
      ).matches(sale),
      isTrue,
    );
  });
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
  testWidgets(
    'credit controles mínimos y filtro cuadrado alineado al buscador',
    (tester) async {
      await _pump(tester, true, const Size(1920, 1080));
      final filter = find.widgetWithText(FilledButton, 'Filtro');
      final search = find.byType(TextField).first;
      expect(tester.getSize(filter).height, tester.getSize(search).height);
      final button = tester.widget<FilledButton>(filter);
      final shape = button.style!.shape!.resolve({})! as RoundedRectangleBorder;
      expect(shape.borderRadius, BorderRadius.zero);
      expect(find.byType(HistoryMetric), findsNothing);
      expect(find.text('Crear nuevo crédito'), findsNothing);
      expect(find.text('Crédito seleccionado'), findsOneWidget);
      expect(find.text('Total abonado'), findsOneWidget);
      expect(
        find.text('Pagos registrados'),
        findsNothing,
      ); // Legacy totals without channel details.
      expect(find.byTooltip('PDF'), findsNWidgets(3));
      expect(
        find.descendant(
          of: find.byType(HistoryDocumentRow),
          matching: find.byTooltip('Registrar abono'),
        ),
        findsNothing,
      );
      expect(find.byTooltip('Registrar abono').hitTestable(), findsOneWidget);
      expect(find.text('Saldar').hitTestable(), findsOneWidget);
      expect(find.text('Eliminar crédito').hitTestable(), findsOneWidget);
      expect(find.text('WhatsApp'), findsNothing);
      expect(
        tester.getRect(find.text('Crédito seleccionado')).center.dy,
        closeTo(tester.getRect(search).center.dy - 8, 6),
      );
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'credit busca la factura visible y actualiza detalle y contador',
    (tester) async {
      await _pump(tester, true, const Size(1024, 600));
      final number = TicketData.fromSale(_Credits().rows[1]).ticketNumber;
      await tester.enterText(find.byType(TextField).first, number);
      await tester.pumpAndSettle();
      expect(find.byType(HistoryDocumentRow), findsOneWidget);
      expect(find.text('1 crédito visible'), findsOneWidget);
      expect(find.text('Cliente 1'), findsNWidgets(2));
      expect(find.text('#$number'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'credit conserva el permiso de eliminación solo para administrador',
    (tester) async {
      await _pump(tester, true, const Size(1024, 600), admin: false);
      expect(find.text('Eliminar crédito'), findsNothing);
      expect(find.byTooltip('Registrar abono').hitTestable(), findsOneWidget);
      expect(find.text('Saldar').hitTestable(), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'credit saldado deshabilita nuevos cobros y conserva nota del cliente',
    (tester) async {
      final repository = _Credits()..rows.clear();
      repository.rows.add(
        SaleModel.fromJson({
          'id': 'SALE-PAID',
          'userId': 'admin-prueba',
          'customerName': 'Cliente saldado',
          'paymentMethod': 'credit',
          'totalSold': 1250,
          'creditPaidAmount': 1250,
          'creditBalance': 0,
          'creditStatus': 'paid',
          'note': 'Entregar por la tarde',
        }),
      );
      await _pump(tester, true, const Size(1024, 600), credits: repository);
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, 'Abonar'))
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<OutlinedButton>(
              find.widgetWithText(OutlinedButton, 'Saldar'),
            )
            .onPressed,
        isNull,
      );
      expect(find.text('Entregar por la tarde'), findsOneWidget);
      expect(find.text('Saldado'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets('credit detalle móvil comparte solo las tres soluciones', (
    tester,
  ) async {
    await _pump(tester, true, const Size(390, 844), live: true);
    await tester.tap(find.text('Comercial del Caribe').first);
    await tester.pumpAndSettle();
    expect(find.byTooltip('Registrar abono').hitTestable(), findsOneWidget);
    expect(find.text('Saldar').hitTestable(), findsOneWidget);
    expect(find.byTooltip('Eliminar crédito').hitTestable(), findsOneWidget);
    expect(find.text('PDF').hitTestable(), findsNothing);
    expect(find.text('Imprimir').hitTestable(), findsNothing);
    expect(find.text('Total abonado').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
    await expectLater(
      find.byType(BottomSheet),
      matchesGoldenFile(platformGolden('goldens/credit_detail_390.png')),
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });
  for (final size in [const Size(860, 560), const Size(1266, 713)]) {
    for (final scale in [1.0, 1.35]) {
      testWidgets(
        'credit detalle compacto mantiene columnas y acciones en una línea $size x$scale',
        (tester) async {
          final repository = _Credits()..rows.clear();
          repository.rows.add(
            SaleModel.fromJson({
              'id': 'COMPACT-01',
              'userId': 'admin-prueba',
              'userName': 'Ana Santos',
              'customer': {
                'nombre': 'Cliente de prueba',
                'telefono': '8095550101',
              },
              'paymentMethod': 'credit',
              'totalSold': 1250,
              'creditPaidAmount': 250,
              'creditBalance': 1000,
              'paymentCashAmount': 100,
              'paymentTransferAmount': 150,
              'items': [
                {
                  'productNameSnapshot': 'Producto de prueba',
                  'qty': 2,
                  'priceSoldUnit': 625,
                  'subtotalSold': 1250,
                },
              ],
            }),
          );
          await _pump(tester, true, size, scale: scale, credits: repository);
          final abonar = tester.getRect(find.byTooltip('Registrar abono'));
          final saldar = tester.getRect(find.byTooltip('Saldar crédito'));
          final eliminar = tester.getRect(find.byTooltip('Eliminar crédito'));
          expect(abonar.top, closeTo(saldar.top, .1));
          expect(abonar.top, closeTo(eliminar.top, .1));
          expect(abonar.right, lessThanOrEqualTo(saldar.left));
          expect(saldar.right, lessThanOrEqualTo(eliminar.left));
          final detail = tester.getRect(find.byType(HistoryPanel).last);
          expect(detail.width, greaterThanOrEqualTo(420));
          expect(size.width - detail.right, closeTo(12, .1));
          expect(
            tester.getRect(find.text('Cliente')).top,
            closeTo(tester.getRect(find.text('Teléfono')).top, .1),
          );
          expect(
            tester.getRect(find.text('Cajero')).top,
            closeTo(tester.getRect(find.text('Estado')).top, .1),
          );
          expect(
            tester.getRect(find.byType(CashTurnMenuButton)).left,
            lessThan(tester.getRect(find.byTooltip('Actualizar')).left),
          );
          expect(tester.takeException(), isNull);
          if (scale == 1) {
            await expectLater(
              find.byType(Scaffold).first,
              matchesGoldenFile(
                platformGolden(
                  'goldens/credit_compact_${size.width.toInt()}.png',
                ),
              ),
            );
          }
          await tester.pumpWidget(const SizedBox.shrink());
        },
      );
    }
  }
  for (final credit in [true, false]) {
    final name = credit ? 'credit' : 'quote';
    for (final size in [const Size(1024, 600), const Size(1920, 1080)]) {
      testWidgets('$name panel de filtros coherente en $size', (tester) async {
        await _pump(tester, credit, size, live: credit);
        expect(
          tester.getSize(find.byType(TextField).first).width,
          lessThanOrEqualTo(560),
        );
        await tester.tap(find.text('Filtro'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));
        await tester.pump(const Duration(milliseconds: 500));
        expect(find.byType(HistoryFilterPanel), findsOneWidget);
        expect(tester.getSize(find.byType(HistoryFilterPanel)).width, 380);
        expect(find.text('Cancelar').hitTestable(), findsOneWidget);
        expect(find.text('Aplicar').hitTestable(), findsOneWidget);
        await expectLater(
          find.byType(HistoryFilterPanel),
          matchesGoldenFile(
            platformGolden('goldens/${name}_filter_${size.width.toInt()}.png'),
          ),
        );
        await tester.tap(find.text('Cancelar'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));
        await tester.pump(const Duration(milliseconds: 500));
        expect(find.byType(HistoryDocumentRow), findsNWidgets(3));
        if (credit) {
          await tester.tap(find.text('Filtro'));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 500));
          await tester.pump(const Duration(milliseconds: 500));
          await tester.tap(find.text('Todos los créditos'));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 500));
          await tester.pump(const Duration(milliseconds: 500));
          await tester.tap(find.text('Saldados').last);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 500));
          await tester.pump(const Duration(milliseconds: 500));
          await tester.tap(find.text('Aplicar'));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 500));
          await tester.pump(const Duration(milliseconds: 500));
          expect(find.byType(HistoryDocumentRow), findsNothing);
          await tester.tap(find.text('Filtro'));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 500));
          await tester.pump(const Duration(milliseconds: 500));
          await tester.tap(find.text('Limpiar filtros'));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 500));
          await tester.pump(const Duration(milliseconds: 500));
          await tester.tap(find.text('Aplicar'));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 500));
          await tester.pump(const Duration(milliseconds: 500));
          expect(find.byType(HistoryDocumentRow), findsNWidgets(3));
        }
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
    for (final size in [const Size(1024, 600), const Size(1920, 1080)]) {
      testWidgets('$name vacío centrado como ventas en $size', (tester) async {
        await _pump(tester, credit, size, empty: true);
        final panel = find.byType(HistoryPanel).first;
        final content = find.byKey(const ValueKey('history-empty-content'));
        final area = tester.getRect(panel);
        expect(tester.getCenter(content).dx, closeTo(area.center.dx, 1));
        expect(
          tester.getCenter(content).dy,
          closeTo(
            credit
                ? area.center.dy
                : (tester.getRect(find.byType(HistoryListHeader).first).bottom +
                          area.bottom) /
                      2,
            2,
          ),
        );
        final cta = find.text(
          credit ? 'Crear nuevo crédito' : 'Crear nueva cotización',
        );
        if (credit) {
          expect(cta, findsNothing);
        } else {
          expect(cta, findsOneWidget);
          expect(tester.getCenter(cta).dx, closeTo(area.center.dx + 12, 15));
        }
        expect(tester.takeException(), isNull);
        await expectLater(
          find.byType(Scaffold).first,
          matchesGoldenFile(
            platformGolden('goldens/${name}_empty_${size.width.toInt()}.png'),
          ),
        );
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
    for (final size in [
      const Size(390, 844),
      const Size(1024, 600),
      const Size(1920, 1080),
      const Size(2560, 1440),
    ]) {
      testWidgets('$name conserva lista y detalle en $size', (tester) async {
        await _pump(tester, credit, size);
        expect(find.text('Comercial del Caribe'), findsWidgets);
        if (size.width >= 860) {
          if (credit) {
            expect(find.text('FACTURA A CRÉDITO'), findsOneWidget);
            expect(
              find.text(
                '#${TicketData.fromSale(_Credits().rows.first).ticketNumber}',
              ),
              findsOneWidget,
            );
          }
          expect(find.byType(HistoryPanel), findsNWidgets(2));
          expect(find.byType(HistoryDocumentRow), findsNWidgets(3));
          expect(
            find
                .text(credit ? 'Total factura' : 'Total cotización')
                .hitTestable(),
            findsOneWidget,
          );
          expect(
            find
                .text(
                  credit
                      ? (size.width < 1360 ? 'Abonar' : 'Registrar abono')
                      : 'Pasar a ticket',
                )
                .hitTestable(),
            findsOneWidget,
          );
        }
        expect(tester.takeException(), isNull);
        await expectLater(
          find.byType(Scaffold).first,
          matchesGoldenFile(
            platformGolden('goldens/${name}_history_${size.width.toInt()}.png'),
          ),
        );
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
    testWidgets('$name búsqueda y selección conservadas en 11 pulgadas', (
      tester,
    ) async {
      await _pump(tester, credit, const Size(1024, 600), scale: 1.15);
      final field = find.byType(TextField).first;
      await tester.enterText(field, 'Cliente 1');
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();
      expect(find.text('Cliente 1'), findsWidgets);
      await tester.enterText(field, '');
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();
      await tester.tap(
        find
            .descendant(
              of: find.byType(HistoryDocumentRow),
              matching: find.text('Cliente 1'),
            )
            .first,
      );
      await tester.pumpAndSettle();
      expect(find.text('Cliente 1'), findsNWidgets(2));
      for (final row in find.byType(HistoryDocumentRow).evaluate()) {
        expect(
          find.descendant(
            of: find.byWidget(row.widget),
            matching: find.byType(IconButton),
          ),
          findsNWidgets(2),
        );
      }
      if (credit) {
        expect(find.text('WhatsApp'), findsNothing);
        expect(
          find.byTooltip('Eliminar crédito').hitTestable(),
          findsOneWidget,
        );
        expect(find.text('Saldar').hitTestable(), findsOneWidget);
        expect(find.byTooltip('Más acciones'), findsNothing);
      } else {
        final more = find.descendant(
          of: find.byType(HistoryActionBar),
          matching: find.byTooltip('Más acciones'),
        );
        await tester.tap(more);
        await tester.pumpAndSettle();
        expect(find.text(credit ? 'WhatsApp' : 'Duplicar'), findsOneWidget);
        expect(
          find.text(credit ? 'Eliminar crédito' : 'Eliminar'),
          findsOneWidget,
        );
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
      }
      expect(
        find.text(credit ? 'Total factura' : 'Total cotización').hitTestable(),
        findsOneWidget,
      );
      expect(
        (credit
                ? find.byTooltip('Registrar abono')
                : find.text('Pasar a ticket'))
            .hitTestable(),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
  for (final credit in [true, false]) {
    testWidgets(
      credit
          ? 'Créditos no permite crear operaciones desde el historial'
          : 'Crear cotización abre Facturar sin crear operaciones',
      (tester) async {
        final router = GoRouter(
          initialLocation: '/credits',
          routes: [
            GoRoute(
              path: '/credits',
              builder: (_, __) => credit
                  ? const SalesCreditScreen()
                  : const CotizacionesHistorialScreen(),
            ),
            GoRoute(
              path: Routes.cotizaciones,
              builder: (_, __) =>
                  const Scaffold(body: Text('Facturar existente')),
            ),
          ],
        );
        addTearDown(router.dispose);
        tester.view.physicalSize = const Size(1024, 600);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              authStateProvider.overrideWith((ref) => _Auth(ref)),
              ventasRepositoryProvider.overrideWithValue(_Credits()),
              cotizacionesRepositoryProvider.overrideWithValue(
                _Quotes()..rows.clear(),
              ),
              clientesRepositoryProvider.overrideWithValue(_Clients()),
              activeCashSessionControllerProvider.overrideWith(
                (ref) => _Cash(ref),
              ),
              companySettingsProvider.overrideWith(
                (ref) async => CompanySettings.empty(),
              ),
            ],
            child: MaterialApp.router(
              theme: AppTheme.light,
              routerConfig: router,
              localizationsDelegates: GlobalMaterialLocalizations.delegates,
              supportedLocales: const [Locale('es', 'DO')],
              builder: (_, child) => TickerMode(enabled: false, child: child!),
            ),
          ),
        );
        await tester.pumpAndSettle();
        if (credit) {
          expect(find.text('Crear nuevo crédito'), findsNothing);
          expect(find.text('Facturar existente'), findsNothing);
        } else {
          await tester.tap(
            find
                .text(credit ? 'Crear nuevo crédito' : 'Crear nueva cotización')
                .first,
          );
          await tester.pumpAndSettle();
          expect(find.text('Facturar existente'), findsOneWidget);
        }
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
}
