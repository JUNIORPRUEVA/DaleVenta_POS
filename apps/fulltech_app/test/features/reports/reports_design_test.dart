import 'dart:ui' show PointerDeviceKind;
import 'package:daleventa_pos/core/offline/offline_store.dart';
import 'package:daleventa_pos/core/offline/sync_queue_service.dart';
import 'package:daleventa_pos/core/theme/app_theme.dart';
import 'package:daleventa_pos/core/widgets/provided_action_icon.dart';
import 'package:daleventa_pos/features/reports/ui/reports_page.dart';
import 'package:daleventa_pos/features/reports/ui/reports_interactive_chart.dart';
import 'package:daleventa_pos/features/warehouses/data/warehouse_repository.dart';
import 'package:daleventa_pos/modules/ventas/data/ventas_repository.dart';
import 'package:daleventa_pos/modules/ventas/sales_models.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../support/platform_goldens.dart';

final _referenceDate = DateTime(2026, 11, 14, 12);

class _ReportsRepository extends VentasRepository {
  _ReportsRepository({this.empty = false})
    : super(
        Dio(),
        SyncQueueService(OfflineStore.instance),
        WarehouseRepository(Dio()),
      );
  final bool empty;
  final requests = <({DateTime from, DateTime to, String? category})>[];
  @override
  Future<Map<String, dynamic>> reportsSalesOverview({
    required DateTime from,
    required DateTime to,
    String? category,
    bool summaryOnly = false,
  }) async {
    if (!summaryOnly) requests.add((from: from, to: to, category: category));
    return {
      'kpis': {
        'totalSales': empty ? 0 : 20,
        'netSales': empty ? 0 : 125000,
        'grossProfit': empty ? 0 : 45000,
        'netProfit': empty ? 0 : 35000,
        'totalProfit': empty ? 0 : 45000,
        'totalExpenses': empty ? 0 : 10000,
        'totalCost': empty ? 0 : 80000,
        'avgTicket': empty ? 0 : 6250,
      },
      'categories': [
        'Computadoras',
        'Herramientas',
        'Accesorios',
        ...List.generate(30, (i) => 'Categoría ${i + 1}'),
      ],
      'salesSeries': empty
          ? []
          : [
              for (var i = 0; i < 7; i++)
                {
                  'label': '2026-11-${(i + 1).toString().padLeft(2, '0')}',
                  'value': [10000, 25000, 8000, 30000, 15000, 22000, 15000][i],
                },
            ],
      'profitSeries': empty
          ? []
          : [
              for (var i = 0; i < 7; i++)
                {
                  'label': '2026-11-${(i + 1).toString().padLeft(2, '0')}',
                  'value': [5000, -2000, 12000, 0, 15000, 8000, 7000][i],
                },
            ],
      'paymentMethods': empty
          ? []
          : [
              {'method': 'Efectivo', 'amount': 60000, 'count': 10},
              {'method': 'Transferencia', 'amount': 45000, 'count': 7},
              {'method': 'Tarjeta', 'amount': 20000, 'count': 3},
            ],
      'topProducts': empty
          ? []
          : [
              {
                'productName': 'Equipo profesional para tu negocio',
                'totalSales': 125000,
                'totalQty': 20,
                'totalProfit': 45000,
              },
            ],
      'topClients': empty
          ? []
          : [
              {
                'clientName': 'Cliente de prueba',
                'totalSpent': 125000,
                'purchaseCount': 20,
              },
            ],
      'categoryProfits': empty
          ? []
          : [
              {
                'category': 'Computadoras',
                'totalSales': 125000,
                'totalCost': 80000,
                'totalProfit': 45000,
                'totalQty': 20,
                'salesCount': 20,
              },
            ],
    };
  }

  @override
  Future<List<SaleModel>> listInvoices({
    required DateTime from,
    required DateTime to,
    String? customerId,
    bool includeDeleted = true,
    int? limit,
  }) async => [];
}

Future<void> _pump(
  WidgetTester tester,
  Size size,
  _ReportsRepository repo, {
  bool useSystemDate = false,
}) async {
  final reference = useSystemDate ? DateTime.now() : _referenceDate;
  SharedPreferences.setMockInitialValues({});
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [ventasRepositoryProvider.overrideWithValue(repo)],
      child: MaterialApp(
        theme: AppTheme.light,
        debugShowCheckedModeBanner: false,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(size.width == 1024 ? 1.15 : 1),
          ),
          child: child!,
        ),
        home: ReportsPage(currentDate: useSystemDate ? null : _referenceDate),
      ),
    ),
  );
  await tester.pumpAndSettle();
  expect(
    repo.requests.first.from,
    DateTime(reference.year, reference.month, reference.day),
  );
  expect(repo.requests.first.to.day, reference.day);
  await tester.runAsync(() async {
    final context = tester.element(find.byType(ReportsPage));
    for (final action in ProvidedAction.values) {
      await precacheImage(
        AssetImage('assets/image/action_${action.name}.png'),
        context,
      );
    }
  });
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() async {
    final font = FontLoader('Manrope');
    for (final weight in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
      font.addFont(rootBundle.load('assets/fonts/manrope/Manrope-$weight.ttf'));
    }
    await font.load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
  testWidgets('sin fecha inyectada conserva el día real de la aplicación', (
    tester,
  ) async {
    await _pump(
      tester,
      const Size(1024, 640),
      _ReportsRepository(),
      useSystemDate: true,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  for (final size in [
    const Size(390, 844),
    const Size(1024, 640),
    const Size(1920, 1080),
    const Size(2560, 1440),
  ]) {
    testWidgets('reportes centrados y responsive a ${size.width}', (
      tester,
    ) async {
      await _pump(tester, size, _ReportsRepository());
      final content = tester.getRect(
        find.byKey(const ValueKey('reports-content')),
      );
      expect(content.width, lessThanOrEqualTo(1360));
      expect(content.center.dx, closeTo(size.width / 2, 1));
      if (size.width >= 640) {
        final header = tester.getRect(
          find.byKey(const ValueKey('reports-full-width-header')),
        );
        expect(header.left, 0);
        expect(header.top, 0);
        expect(header.width, size.width);
      }
      expect(find.textContaining('125,000.00'), findsWidgets);
      expect(find.textContaining('35,000.00'), findsWidgets);
      expect(tester.takeException(), isNull);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile(
          platformGolden('goldens/reports_${size.width.toInt()}.png'),
        ),
      );
      await tester.drag(
        find.byKey(const ValueKey('reports-dashboard-scroll')),
        const Offset(0, -480),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile(
          platformGolden('goldens/reports_details_${size.width.toInt()}.png'),
        ),
      );
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
  testWidgets('sin ventas conserva ceros y un panel compacto', (tester) async {
    await _pump(tester, const Size(1024, 640), _ReportsRepository(empty: true));
    expect(find.text('No hay ventas para este período'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile(platformGolden('goldens/reports_empty_1024.png')),
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('buscar categoría aplica solo una categoría real al servidor', (
    tester,
  ) async {
    final repo = _ReportsRepository();
    await _pump(tester, const Size(1024, 640), repo);
    await tester.tap(find.text('Todas las categorías'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'herra');
    await tester.pumpAndSettle();
    expect(find.text('Herramientas'), findsOneWidget);
    expect(find.text('Accesorios'), findsNothing);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile(platformGolden('goldens/reports_category_1024.png')),
    );
    await tester.tap(find.text('Herramientas'));
    await tester.pumpAndSettle();
    expect(repo.requests.last.category, 'Herramientas');
    await tester.tap(find.text('Ayer'));
    await tester.pumpAndSettle();
    expect(repo.requests.last.category, 'Herramientas');
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('intervalo permite calendario y entradas con el lápiz original', (
    tester,
  ) async {
    final repo = _ReportsRepository();
    await _pump(tester, const Size(1024, 640), repo);
    await tester.tap(find.text('Intervalo'));
    await tester.pumpAndSettle();
    expect(find.byType(DateRangePickerDialog), findsOneWidget);
    final edit = find.byWidgetPredicate(
      (w) => w is ProvidedActionIcon && w.action == ProvidedAction.edit,
    );
    expect(edit, findsOneWidget);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile(platformGolden('goldens/reports_range_1024.png')),
    );
    await tester.tap(edit);
    await tester.pumpAndSettle();
    final now = _referenceDate;
    final start = DateTime(now.year, now.month, 1);
    final fields = find.byType(TextField);
    expect(fields, findsNWidgets(2));
    await tester.enterText(fields.at(0), DateFormat.yMd('en_US').format(start));
    await tester.enterText(fields.at(1), DateFormat.yMd('en_US').format(now));
    await tester.tap(find.text('Aplicar').last);
    await tester.pumpAndSettle();
    expect(find.byType(DateRangePickerDialog), findsNothing);
    expect(repo.requests.last.from.day, 1);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('gráfico muestra valores negativos y permite tocar cada punto', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 500,
            height: 240,
            child: ReportsInteractiveChart(
              label: 'Prueba',
              color: Colors.blue,
              line: true,
              points: const [
                (label: '2026-11-01', value: 100.0),
                (label: '2026-11-02', value: -250.0),
                (label: '2026-11-03', value: 300.0),
              ],
            ),
          ),
        ),
      ),
    );
    final chart = tester.getRect(find.byType(ReportsInteractiveChart));
    await tester.tapAt(
      Offset(chart.left + 66 + (chart.width - 82) / 2, chart.center.dy),
    );
    await tester.pump();
    expect(find.textContaining('02/11/2026'), findsOneWidget);
    expect(find.textContaining('250.00'), findsOneWidget);
    expect(tester.takeException(), isNull);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(Offset(chart.right - 20, chart.center.dy));
    await tester.pump();
    expect(find.textContaining('03/11/2026'), findsOneWidget);
    await mouse.removePointer();
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('métodos de pago muestran su monto al seleccionarlos', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 380,
            height: 220,
            child: PaymentMethodPieChart(
              data: const [
                PaymentMethodData(method: 'Efectivo', amount: 600, count: 6),
                PaymentMethodData(
                  method: 'Transferencia',
                  amount: 400,
                  count: 4,
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Transferencia'));
    await tester.pump();
    expect(find.textContaining('400.00'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
