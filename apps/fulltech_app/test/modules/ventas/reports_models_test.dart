import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import 'package:daleventa_pos/core/utils/money_formatters.dart';
import 'package:daleventa_pos/features/reports/ui/reports_page.dart';
import 'package:daleventa_pos/modules/ventas/sales_models.dart';

void main() {
  group('SaleModel.kind', () {
    test('por defecto es invoice cuando el backend no lo envía', () {
      final sale = SaleModel.fromJson(<String, dynamic>{
        'id': 's1',
        'items': <dynamic>[],
      });
      expect(sale.kind, 'invoice');
    });

    test('parsea kind=refund desde el backend', () {
      final sale = SaleModel.fromJson(<String, dynamic>{
        'id': 'r1',
        'kind': 'refund',
        'items': <dynamic>[],
      });
      expect(sale.kind, 'refund');
    });

    test('parsea kind=invoice desde el backend', () {
      final sale = SaleModel.fromJson(<String, dynamic>{
        'id': 's2',
        'kind': 'invoice',
        'items': <dynamic>[],
      });
      expect(sale.kind, 'invoice');
    });
  });

  group('SaleModel.returnStatus', () {
    test('parsea devolución parcial con monto neto vigente', () {
      final sale = SaleModel.fromJson(<String, dynamic>{
        'id': 's-partial',
        'kind': 'invoice',
        'totalSold': 1000,
        'returnedAmount': 300,
        'returnableAmount': 700,
        'returnStatus': 'PARTIALLY_RETURNED',
        'canReturn': true,
        'items': <dynamic>[],
      });

      expect(sale.isPartiallyReturned, isTrue);
      expect(sale.isCommerciallyActive, isFalse);
      expect(sale.netActiveAmount, 700);
      expect(sale.canReturn, isTrue);
    });

    test('documento refund nunca queda como factura activa ni retornable', () {
      final sale = SaleModel.fromJson(<String, dynamic>{
        'id': 'refund-1',
        'kind': 'refund',
        'totalSold': -300,
        'returnStatus': 'ACTIVE',
        'canReturn': false,
        'items': <dynamic>[],
      });

      expect(sale.isRefundDocument, isTrue);
      expect(sale.isCommerciallyActive, isFalse);
      expect(sale.netActiveAmount, 0);
      expect(sale.canReturn, isFalse);
    });

    test('factura devuelta queda sin monto neto ni acción de devolución', () {
      final sale = SaleModel.fromJson(<String, dynamic>{
        'id': 's-returned',
        'kind': 'invoice',
        'totalSold': 500,
        'returnedAmount': 500,
        'returnableAmount': 0,
        'returnStatus': 'RETURNED',
        'canReturn': false,
        'items': <dynamic>[],
      });

      expect(sale.isReturned, isTrue);
      expect(sale.netActiveAmount, 0);
      expect(sale.canReturn, isFalse);
    });
  });

  group('KpisData.fromReport', () {
    test('kpis vacíos producen ceros sin excepciones', () {
      final kpis = KpisData.fromReport(<String, dynamic>{});
      expect(kpis.totalSales, 0);
      expect(kpis.totalProfit, 0);
      expect(kpis.netProfit, 0);
      expect(kpis.totalExpenses, 0);
      expect(kpis.totalCost, 0);
      expect(kpis.avgTicket, 0);
      expect(kpis.margin, 0);
    });

    test('usa netSales como total de ventas y calcula avgTicket', () {
      final kpis = KpisData.fromReport(<String, dynamic>{
        'kpis': <String, dynamic>{
          'totalSales': 4,
          'netSales': 1000,
          'totalProfit': 300,
          'totalExpenses': 0,
          'totalCost': 700,
        },
      });
      expect(kpis.totalSales, 1000);
      expect(kpis.totalProfit, 300);
      expect(kpis.netProfit, 300);
      expect(kpis.totalExpenses, 0);
      expect(kpis.margin, closeTo(30.0, 0.001));
      // avgTicket no viene del backend -> totalSold / totalSales = 1000/4
      expect(kpis.avgTicket, closeTo(250.0, 0.001));
    });

    test('separa utilidad bruta, gastos y utilidad neta del reporte', () {
      final kpis = KpisData.fromReport(<String, dynamic>{
        'kpis': <String, dynamic>{
          'totalSales': 4,
          'netSales': 2100,
          'totalProfit': 1228,
          'totalExpenses': 700,
          'netProfit': 528,
          'totalCost': 872,
        },
      });
      expect(kpis.totalSales, 2100);
      expect(kpis.totalProfit, 1228);
      expect(kpis.totalExpenses, 700);
      expect(kpis.netProfit, 528);
      expect(kpis.netMargin, closeTo(25.142857, 0.001));
    });

    test('sin gastos mantiene utilidad bruta igual a utilidad neta', () {
      final kpis = KpisData.fromReport(<String, dynamic>{
        'kpis': <String, dynamic>{
          'totalSales': 1,
          'netSales': 1000,
          'totalProfit': 1000,
          'totalExpenses': 0,
          'netProfit': 1000,
        },
      });
      expect(kpis.totalProfit, 1000);
      expect(kpis.totalExpenses, 0);
      expect(kpis.netProfit, 1000);
    });

    test('respuesta con nulls no rompe el parseo', () {
      final kpis = KpisData.fromReport(<String, dynamic>{
        'kpis': <String, dynamic>{
          'totalSales': null,
          'netSales': null,
          'totalProfit': null,
          'totalCost': null,
        },
      });
      expect(kpis.totalSales, 0);
      expect(kpis.totalProfit, 0);
      expect(kpis.margin.isFinite, isTrue);
    });

    test(
      'utilidad bruta descuenta el efecto de devoluciones, no los gastos',
      () {
        // El backend entrega netProfit ya neto de devoluciones/anulaciones y de
        // gastos que afectan utilidad, por lo que:
        //   utilidad bruta = netProfit + totalExpenses
        // Aqui totalProfit (crudo, antes del efecto de devoluciones) = 1300.
        final kpis = KpisData.fromReport(<String, dynamic>{
          'kpis': <String, dynamic>{
            'totalSales': 4,
            'netSales': 2100,
            'totalProfit': 1300,
            'totalExpenses': 700,
            'netProfit': 528,
          },
        });
        expect(kpis.grossProfit, 1228);
        expect(kpis.netProfit, 528);
        expect(kpis.netMargin, closeTo(25.142857, 0.001));
      },
    );

    test('gastos que no afectan utilidad no reducen la utilidad neta', () {
      // El backend solo suma a totalExpenses los movimientos OUT de tipo
      // expense con affectsProfit=true; el resto nunca llega aqui.
      final kpis = KpisData.fromReport(<String, dynamic>{
        'kpis': <String, dynamic>{
          'totalSales': 2,
          'netSales': 1500,
          'totalProfit': 400,
          'totalExpenses': 0,
          'netProfit': 400,
        },
      });
      expect(kpis.totalExpenses, 0);
      expect(kpis.netProfit, 400);
      expect(kpis.grossProfit, 400);
    });

    test('descarta NaN/Infinity y normaliza ceros negativos', () {
      final kpis = KpisData.fromReport(<String, dynamic>{
        'kpis': <String, dynamic>{
          'netSales': double.infinity,
          'totalProfit': double.nan,
          'netProfit': '-0.0',
          'totalExpenses': double.nan,
        },
      });
      expect(kpis.totalSales, 0);
      expect(kpis.totalProfit, 0);
      expect(kpis.netProfit, 0);
      expect(kpis.margin.isFinite, isTrue);
      expect(kpis.margin.isNaN, isFalse);
    });
  });

  group('ReportsFilterState', () {
    test('el estado inicial es Hoy + Todas', () {
      final state = _initialFilterState();
      expect(kDefaultReportsPeriod, DateRangePeriod.today);
      expect(state.period, DateRangePeriod.today);
      expect(state.category, isNull);
      expect(state.isDefault, isTrue);
    });

    test('cambiar el periodo conserva la categoria', () {
      final state = _initialFilterState().withCategory('Accesorios');
      final changed = state.withPeriod(DateRangePeriod.week);
      expect(changed.period, DateRangePeriod.week);
      expect(changed.category, 'Accesorios');
    });

    test('cambiar la categoria conserva el periodo', () {
      final state = _initialFilterState().withPeriod(DateRangePeriod.month);
      final changed = state.withCategory('Celulares');
      expect(changed.period, DateRangePeriod.month);
      expect(changed.category, 'Celulares');
    });

    test('categoria vacia o en blanco equivale a Todas', () {
      expect(_initialFilterState().withCategory('   ').category, isNull);
      expect(_initialFilterState().withCategory('').category, isNull);
      expect(_initialFilterState().withCategory(null).category, isNull);
    });

    test('reset vuelve exactamente a Hoy + Todas', () {
      final state = _initialFilterState()
          .withPeriod(DateRangePeriod.year)
          .withCategory('Accesorios');
      final reset = state.reset();
      expect(reset.period, DateRangePeriod.today);
      expect(reset.category, isNull);
      expect(reset.customStart, isNull);
      expect(reset.customEnd, isNull);
      expect(reset.isDefault, isTrue);
    });

    test('cambiar de categoria conserva el rango personalizado', () {
      final state = _initialFilterState().withCustomRange(
        DateTime(2026, 9, 5),
        DateTime(2026, 9, 9),
      );
      final changed = state.withCategory('Accesorios');
      expect(changed.period, DateRangePeriod.custom);
      expect(changed.customStart, DateTime(2026, 9, 5));
      expect(changed.customEnd, DateTime(2026, 9, 9));
      expect(changed.category, 'Accesorios');
    });

    test('isDefault solo es true en Hoy + Todas', () {
      expect(_initialFilterState().isDefault, isTrue);
      expect(_initialFilterState().withCategory('X').isDefault, isFalse);
      expect(
        _initialFilterState().withPeriod(DateRangePeriod.week).isDefault,
        isFalse,
      );
    });
  });

  group('ReportsFinancialKpiCards', () {
    testWidgets('sin gastos muestra KPIs simples sin bruta ni gastos', (
      tester,
    ) async {
      final kpis = KpisData.fromReport(<String, dynamic>{
        'kpis': <String, dynamic>{
          'totalSales': 4,
          'netSales': 2100,
          'totalProfit': 1228,
          'totalExpenses': 0,
          'netProfit': 1228,
          'avgTicket': 525,
        },
      });

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: ReportsFinancialKpiCards(kpis: kpis)),
        ),
      );

      expect(find.text('Utilidad neta'), findsOneWidget);
      expect(find.text('Margen neto'), findsOneWidget);
      expect(find.text('Tickets'), findsOneWidget);
      expect(find.text('Utilidad bruta'), findsNothing);
      expect(find.text('Gastos'), findsNothing);
      expect(find.text('Utilidad'), findsNothing);
    });

    testWidgets('con gastos muestra desglose financiero', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ReportsFinancialKpiCards(kpis: _financialKpis()),
          ),
        ),
      );

      expect(find.text('Ventas'), findsOneWidget);
      expect(find.text('Utilidad neta'), findsOneWidget);
      expect(find.text('Margen neto'), findsOneWidget);
      expect(find.text('Tickets'), findsOneWidget);
      expect(find.text('Cómo se calcula la utilidad'), findsOneWidget);
      expect(find.text('Bruta'), findsOneWidget);
      expect(find.text('Gastos'), findsOneWidget);
      expect(find.text('Neta'), findsOneWidget);
      expect(find.text('-RD\$ 700.00'), findsOneWidget);
      expect(find.text('Utilidad bruta'), findsNothing);
      expect(find.text('Utilidad'), findsNothing);
    });

    testWidgets('CASE C: OUT con affectsProfit=false no activa el desglose', (
      tester,
    ) async {
      // El backend NO suma a totalExpenses los movimientos OUT con
      // affectsProfit=false, asi que el reporte llega con totalExpenses 0
      // aunque el egreso exista en caja: la UI debe quedar compacta.
      final kpis = KpisData.fromReport(<String, dynamic>{
        'kpis': <String, dynamic>{
          'totalSales': 3,
          'netSales': 1500,
          'totalProfit': 1000,
          'totalExpenses': 0,
          'netProfit': 1000,
        },
      });

      expect(kpis.hasProfitExpenses, isFalse);
      expect(kpis.totalExpenses, 0);
      expect(kpis.grossProfit, 1000);
      expect(kpis.netProfit, 1000);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: ReportsFinancialKpiCards(kpis: kpis)),
        ),
      );

      expect(tester.takeException(), isNull);
      expect(find.text('Cómo se calcula la utilidad'), findsNothing);
      expect(find.text('Bruta'), findsNothing);
      expect(find.text('Gastos'), findsNothing);
      expect(find.text('Neta'), findsNothing);
      expect(find.text('Utilidad bruta'), findsNothing);
      // La utilidad (1000) aparece UNA sola vez: sin duplicar la bruta.
      expect(
        find.text(formatRdCurrencyAccounting(kpis.netProfit)),
        findsOneWidget,
      );
    });

    testWidgets('usa distribución 2x2 en ancho móvil', (tester) async {
      final kpis = _financialKpis();
      tester.view.physicalSize = const Size(390, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 390,
              child: ReportsFinancialKpiCards(kpis: kpis),
            ),
          ),
        ),
      );

      final ventas = tester.getTopLeft(
        find.byKey(const ValueKey('reports-kpi-sales')),
      );
      final netProfit = tester.getTopLeft(
        find.byKey(const ValueKey('reports-kpi-net-profit')),
      );
      final netMargin = tester.getTopLeft(
        find.byKey(const ValueKey('reports-kpi-net-margin')),
      );
      final tickets = tester.getTopLeft(
        find.byKey(const ValueKey('reports-kpi-tickets')),
      );

      expect((ventas.dy - netProfit.dy).abs(), lessThan(2));
      expect((netMargin.dy - tickets.dy).abs(), lessThan(2));
      expect(netMargin.dy, greaterThan(ventas.dy));
      expect(netProfit.dx, greaterThan(ventas.dx));
      expect(tickets.dx, greaterThan(netMargin.dx));
      expect(tester.takeException(), isNull);
    });

    testWidgets('usa fila horizontal en desktop', (tester) async {
      final kpis = _financialKpis();
      tester.view.physicalSize = const Size(1000, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 1000,
              child: ReportsFinancialKpiCards(kpis: kpis),
            ),
          ),
        ),
      );

      final ventas = tester.getTopLeft(
        find.byKey(const ValueKey('reports-kpi-sales')),
      );
      final netProfit = tester.getTopLeft(
        find.byKey(const ValueKey('reports-kpi-net-profit')),
      );
      final netMargin = tester.getTopLeft(
        find.byKey(const ValueKey('reports-kpi-net-margin')),
      );
      final tickets = tester.getTopLeft(
        find.byKey(const ValueKey('reports-kpi-tickets')),
      );

      expect((ventas.dy - netProfit.dy).abs(), lessThan(2));
      expect((ventas.dy - netMargin.dy).abs(), lessThan(2));
      expect((ventas.dy - tickets.dy).abs(), lessThan(2));
      expect(netProfit.dx, greaterThan(ventas.dx));
      expect(netMargin.dx, greaterThan(netProfit.dx));
      expect(tickets.dx, greaterThan(netMargin.dx));
      expect(tester.takeException(), isNull);
    });
  });

  group('DateRangeHelper', () {
    test('Hoy inicia a medianoche y termina a 23:59:59.999', () {
      final range = DateRangeHelper.getRangeForPeriod(DateRangePeriod.today);
      final now = DateTime.now();
      expect(range.start.year, now.year);
      expect(range.start.month, now.month);
      expect(range.start.day, now.day);
      expect(range.start.hour, 0);
      expect(range.start.minute, 0);
      expect(range.end.day, now.day);
      expect(range.end.hour, 23);
      expect(range.end.minute, 59);
    });

    test('Ayer dura exactamente un día calendario', () {
      final yesterday = DateRangeHelper.getRangeForPeriod(
        DateRangePeriod.yesterday,
      );
      final duration = yesterday.end.difference(yesterday.start);
      // 23:59:59.999 - 00:00:00.000 = 24h - 1ms
      expect(duration.inHours, 23);
      expect(duration.inMinutes, 23 * 60 + 59);
      expect(yesterday.start.isBefore(yesterday.end), isTrue);
    });

    test('rango nunca es invertido (start <= end)', () {
      for (final period in DateRangePeriod.values) {
        final range = DateRangeHelper.getRangeForPeriod(period);
        expect(
          range.start.isBefore(range.end) || range.start == range.end,
          isTrue,
          reason: 'periodo $period',
        );
      }
    });

    test('7 días incluye EXACTAMENTE 7 fechas locales contando hoy', () {
      final range = DateRangeHelper.getRangeForPeriod(DateRangePeriod.week);
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);

      expect(range.start, DateTime(now.year, now.month, now.day - 6));
      expect(
        range.end,
        DateTime(now.year, now.month, now.day, 23, 59, 59, 999),
      );

      // Conteo inequivoco de las fechas locales incluidas en [start, end].
      final included = <DateTime>[];
      for (var offset = 0; offset < 400; offset++) {
        final day = DateTime(
          range.start.year,
          range.start.month,
          range.start.day + offset,
        );
        if (day.isAfter(range.end)) break;
        included.add(day);
      }
      expect(included.length, 7);
      expect(included.toSet().length, 7);
      expect(included.first, DateTime(now.year, now.month, now.day - 6));
      expect(included.last, today);
      expect(included.contains(today.add(const Duration(days: 1))), isFalse);
      // El dia anterior al inicio NO puede estar incluido (eran 8 dias).
      expect(
        included.contains(DateTime(now.year, now.month, now.day - 7)),
        isFalse,
      );
    });

    test(
      '7 días para el 10 Sep => 04..10 Sep (7 fechas), fin exclusivo 11 Sep',
      () {
        // Ejemplo textual del requerimiento: si hoy = 10 Sep, el rango debe ser
        // 04 Sep 00:00 hasta 11 Sep 00:00 exclusivo = 7 fechas locales.
        final range = DateRangeHelper.getRangeForPeriod(
          DateRangePeriod.week,
          now: DateTime(2026, 9, 10, 15, 30),
        );

        expect(range.start, DateTime(2026, 9, 4));
        expect(range.end, DateTime(2026, 9, 10, 23, 59, 59, 999));

        // El backend recibe solo la fecha (yyyy-MM-dd) y aplica fin EXCLUSIVO:
        // 'to' = 2026-09-10 => cuenta fecha < 2026-09-11 00:00 RD.
        final exclusiveEnd = DateTime(
          range.end.year,
          range.end.month,
          range.end.day,
        ).add(const Duration(days: 1));
        expect(exclusiveEnd, DateTime(2026, 9, 11));

        final dates = <String>[];
        for (var offset = 0; offset < 400; offset++) {
          final day = DateTime(2026, 9, 4 + offset);
          if (day.isAfter(range.end)) break;
          dates.add(
            '${day.year}-${day.month.toString().padLeft(2, '0')}-'
            '${day.day.toString().padLeft(2, '0')}',
          );
        }
        expect(dates, <String>[
          '2026-09-04',
          '2026-09-05',
          '2026-09-06',
          '2026-09-07',
          '2026-09-08',
          '2026-09-09',
          '2026-09-10',
        ]);
        expect(dates.length, 7);
        expect(dates.contains('2026-09-11'), isFalse);
        expect(dates.contains('2026-09-03'), isFalse);
      },
    );

    test('Este mes inicia el dia 1 del mes local actual', () {
      final range = DateRangeHelper.getRangeForPeriod(DateRangePeriod.month);
      final now = DateTime.now();
      expect(range.start, DateTime(now.year, now.month, 1));
      expect(range.start.hour, 0);
      expect(range.end.day, now.day);
      expect(range.end.hour, 23);
    });

    test('rango personalizado respeta Desde/Hasta con dia completo', () {
      final range = DateRangeHelper.getRangeForPeriod(
        DateRangePeriod.custom,
        customStart: DateTime(2026, 9, 5),
        customEnd: DateTime(2026, 9, 9),
      );
      expect(range.start, DateTime(2026, 9, 5));
      expect(range.end, DateTime(2026, 9, 9, 23, 59, 59, 999));
      expect(range.start.isBefore(range.end), isTrue);
    });

    test('rango personalizado invertido se normaliza (nunca invalido)', () {
      final range = DateRangeHelper.getRangeForPeriod(
        DateRangePeriod.custom,
        customStart: DateTime(2026, 9, 9),
        customEnd: DateTime(2026, 9, 5),
      );
      expect(range.start, DateTime(2026, 9, 9));
      expect(range.start.isBefore(range.end), isTrue);
      expect(range.end.day, 9);
    });
  });

  group('Reportes responsive (sin overflow)', () {
    const mobileSizes = <Size>[
      Size(360, 800),
      Size(390, 844),
      Size(412, 915),
      Size(430, 932),
    ];
    const desktopSizes = <Size>[
      Size(900, 800),
      Size(1024, 900),
      Size(1280, 1024),
      Size(1440, 1024),
    ];

    for (final size in <Size>[...mobileSizes, ...desktopSizes]) {
      testWidgets('KPIs financieros sin overflow en ${size.width.toInt()}px', (
        tester,
      ) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: SizedBox(
                  width: size.width,
                  child: ReportsFinancialKpiCards(kpis: _financialKpis()),
                ),
              ),
            ),
          ),
        );

        expect(tester.takeException(), isNull);
        expect(find.text('Ventas'), findsOneWidget);
        expect(find.text('Bruta'), findsOneWidget);
        expect(find.text('Gastos'), findsOneWidget);
        expect(find.text('Utilidad neta'), findsOneWidget);
        expect(find.text('Cómo se calcula la utilidad'), findsOneWidget);
      });
    }

    // Revalidacion del estado SIN gastos (CASE A) en los mismos anchos:
    // sin overflow, sin huecos, grilla intacta y sin info de utilidad duplicada.
    for (final size in <Size>[...mobileSizes, ...desktopSizes]) {
      testWidgets(
        'sin gastos: grilla y sin overflow en ${size.width.toInt()}px',
        (tester) async {
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);

          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: SingleChildScrollView(
                  child: SizedBox(
                    width: size.width,
                    child: ReportsFinancialKpiCards(
                      kpis: _kpisWithoutExpenses(),
                    ),
                  ),
                ),
              ),
            ),
          );

          expect(tester.takeException(), isNull);
          expect(find.text('Ventas'), findsOneWidget);
          expect(find.text('Utilidad neta'), findsOneWidget);
          expect(find.text('Margen neto'), findsOneWidget);
          expect(find.text('Tickets'), findsOneWidget);
          // CASE A: nada de datos redundantes de bruta/gastos.
          expect(find.text('Utilidad bruta'), findsNothing);
          expect(find.text('Bruta'), findsNothing);
          expect(find.text('Gastos'), findsNothing);
          expect(find.text('Neta'), findsNothing);
          expect(find.text('Cómo se calcula la utilidad'), findsNothing);

          final sales = tester.getTopLeft(
            find.byKey(const ValueKey('reports-kpi-sales')),
          );
          final net = tester.getTopLeft(
            find.byKey(const ValueKey('reports-kpi-net-profit')),
          );
          final margin = tester.getTopLeft(
            find.byKey(const ValueKey('reports-kpi-net-margin')),
          );
          final tickets = tester.getTopLeft(
            find.byKey(const ValueKey('reports-kpi-tickets')),
          );

          if (size.width >= 900) {
            // Desktop: una sola fila de 4 tarjetas.
            for (final pos in <Offset>[net, margin, tickets]) {
              expect((pos.dy - sales.dy).abs(), lessThan(2));
            }
            expect(net.dx, greaterThan(sales.dx));
            expect(margin.dx, greaterThan(net.dx));
            expect(tickets.dx, greaterThan(margin.dx));
          } else {
            // Movil: grilla 2x2 -> fila 1 (Ventas, Neta), fila 2 (Margen,
            // Tickets). Columna izquierda = Ventas/Margen, derecha = Neta/Tickets.
            expect((net.dy - sales.dy).abs(), lessThan(2));
            expect(margin.dy, greaterThan(sales.dy));
            expect((tickets.dy - margin.dy).abs(), lessThan(2));
            expect(net.dx, greaterThan(sales.dx));
            expect((margin.dx - sales.dx).abs(), lessThan(2));
            expect((tickets.dx - net.dx).abs(), lessThan(2));
          }
        },
      );
    }

    testWidgets('KPIs en cero no muestran NaN ni Infinity', (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 360,
              child: ReportsFinancialKpiCards(
                kpis: KpisData.fromReport(<String, dynamic>{}),
              ),
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      final zero = formatRdCurrencyAccounting(0);
      expect(find.text(zero), findsNWidgets(2));
      expect(find.text('0.0%'), findsOneWidget);
      expect(find.text('0'), findsOneWidget);
      expect(find.text('Gastos'), findsNothing);
      expect(find.textContaining('NaN'), findsNothing);
      expect(find.textContaining('Infinity'), findsNothing);
    });

    testWidgets('selectores de periodo y categoria caben en 360px', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 360,
              child: Column(
                children: [
                  DateRangeSelector(
                    selectedPeriod: kDefaultReportsPeriod,
                    customLabel: null,
                    onPeriodChanged: (_) {},
                  ),
                  CategoryFilterSelector(
                    categories: const ['Accesorios', 'Celulares'],
                    selectedCategory: null,
                    onChanged: (_) {},
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      expect(find.text('Hoy'), findsOneWidget);
      expect(find.text('Semana'), findsOneWidget);
      expect(find.text('Mes'), findsOneWidget);
      expect(find.text('Personalizado'), findsOneWidget);
      expect(find.text('Todas las categorías'), findsOneWidget);
    });
  });

  group('Filtros de Reportes (UI)', () {
    const periodLabels = <String>[
      'Hoy',
      'Ayer',
      'Semana',
      'Mes',
      'Año',
      'Personalizado',
    ];
    const allSizes = <Size>[
      Size(360, 800),
      Size(390, 844),
      Size(412, 915),
      Size(430, 932),
      Size(900, 800),
      Size(1024, 900),
      Size(1280, 1024),
      Size(1440, 1024),
    ];

    Future<void> pumpSelector(
      WidgetTester tester,
      Size size, {
      String? customLabel,
      DateRangePeriod selected = DateRangePeriod.today,
      ValueChanged<DateRangePeriod>? onPeriodChanged,
    }) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: size.width,
              child: DateRangeSelector(
                selectedPeriod: selected,
                customLabel: customLabel,
                onPeriodChanged: onPeriodChanged ?? (_) {},
              ),
            ),
          ),
        ),
      );
    }

    Future<void> pumpDrawer(WidgetTester tester, Size size) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ReportsFilterDrawer(
              selectedPeriod: DateRangePeriod.today,
              categories: const ['Accesorios', 'Celulares'],
              selectedCategory: null,
            ),
          ),
        ),
      );
    }

    testWidgets('muestra EXACTAMENTE los 6 labels pedidos y en ese orden', (
      tester,
    ) async {
      await pumpSelector(tester, const Size(360, 800));

      for (final label in periodLabels) {
        expect(find.text(label), findsOneWidget, reason: 'falta $label');
      }
      expect(kReportPeriodOrder.map((period) => period.name).toList(), <String>[
        'today',
        'yesterday',
        'week',
        'month',
        'year',
        'custom',
      ]);
      // Orden visual real: dx creciente dentro de la MISMA fila.
      var previousDx = double.negativeInfinity;
      for (final label in periodLabels) {
        final dx = tester.getTopLeft(find.text(label)).dx;
        expect(dx, greaterThan(previousDx), reason: 'orden de $label');
        previousDx = dx;
      }

      // Accesos eliminados: no deben existir en la UI.
      expect(find.text('7 días'), findsNothing);
      expect(find.text('15 días'), findsNothing);
      expect(find.text('Este mes'), findsNothing);
      expect(find.text('Este año'), findsNothing);
    });

    for (final size in allSizes) {
      testWidgets(
        'una sola fila, sin overflow y sin texto partido en ${size.width.toInt()}px',
        (tester) async {
          await pumpSelector(tester, size);

          expect(tester.takeException(), isNull);

          // Los 6 accesos comparten la misma Y => nunca hacen Wrap.
          final baselineDy = tester.getTopLeft(find.text('Hoy')).dy;
          for (final label in periodLabels.skip(1)) {
            expect(
              (tester.getTopLeft(find.text(label)).dy - baselineDy).abs(),
              lessThan(2),
              reason: '$label deberia estar en la misma fila',
            );
          }

          // Ningun label se parte en dos lineas (incl. "Personalizado").
          for (final label in periodLabels) {
            expect(_lineCount(tester, find.text(label)), 1, reason: label);
          }

          // A partir de 1024 los 6 accesos caben sin scroll (en el ancho
          // completo del selector). En 900 con la fuente real de la app
          // tambien caben; la fila degrada a scroll horizontal si no cupieran.
          if (size.width >= 1024) {
            expect(_selectorScrollExtent(tester), 0);
          }
        },
      );
    }

    testWidgets('en 360px la fila se desliza horizontalmente con el dedo', (
      tester,
    ) async {
      await pumpSelector(tester, const Size(360, 800));

      final scrollView = tester.widget<SingleChildScrollView>(
        find.descendant(
          of: find.byType(DateRangeSelector),
          matching: find.byType(SingleChildScrollView),
        ),
      );
      expect(scrollView.scrollDirection, Axis.horizontal);

      final position = tester
          .state<ScrollableState>(
            find.descendant(
              of: find.byType(DateRangeSelector),
              matching: find.byType(Scrollable),
            ),
          )
          .position;
      expect(position.maxScrollExtent, greaterThan(0));

      await tester.drag(find.byType(DateRangeSelector), const Offset(-90, 0));
      await tester.pumpAndSettle();
      expect(position.pixels, greaterThan(0));
    });

    testWidgets('el chip seleccionado se marca con check, no solo con color', (
      tester,
    ) async {
      await pumpSelector(
        tester,
        const Size(360, 800),
        selected: DateRangePeriod.week,
      );

      // Solo el chip activo muestra el icono check (indicador no cromatico).
      expect(find.byIcon(Icons.check_rounded), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('tocar un periodo emite ese periodo', (tester) async {
      DateRangePeriod? picked;
      await pumpSelector(
        tester,
        const Size(390, 844),
        onPeriodChanged: (period) => picked = period,
      );

      await tester.tap(find.text('Mes'));
      await tester.pump();
      expect(picked, DateRangePeriod.month);
    });

    for (final size in const <Size>[
      Size(360, 800),
      Size(390, 844),
      Size(412, 915),
      Size(430, 932),
    ]) {
      testWidgets(
        'drawer movil sin overflow ni texto partido en ${size.width.toInt()}px',
        (tester) async {
          await pumpDrawer(tester, size);

          expect(tester.takeException(), isNull);
          for (final label in periodLabels) {
            expect(_lineCount(tester, find.text(label)), 1, reason: label);
          }
          for (final label in const <String>[
            'Hoy',
            'Ayer',
            'Semana',
            'Mes',
            'Año',
            'Personalizado',
          ]) {
            expect(find.text(label), findsOneWidget);
          }
          // Categorias del tenant (solo las recibidas).
          expect(find.text('Todas las categorías'), findsOneWidget);
          expect(find.text('Accesorios'), findsOneWidget);
          expect(find.text('Celulares'), findsOneWidget);

          // Footer: ninguna de las dos acciones se parte en varias lineas.
          expect(_lineCount(tester, find.text('Restablecer')), 1);
          expect(_lineCount(tester, find.text('Aplicar filtros')), 1);
        },
      );
    }

    testWidgets('drawer respeta notch (arriba) y home indicator (abajo)', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      // Simula iPhone: notch/Dynamic Island arriba y home indicator abajo.
      tester.view.padding = const FakeViewPadding(top: 47, bottom: 34);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPadding);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ReportsFilterDrawer(
              selectedPeriod: DateRangePeriod.today,
              categories: const <String>['Accesorios'],
              selectedCategory: null,
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);

      // El encabezado NO queda debajo del notch.
      expect(
        tester.getTopLeft(find.text('Filtros')).dy,
        greaterThanOrEqualTo(47),
      );

      // El footer NO queda debajo del home indicator ni de la barra de
      // navegacion de Android.
      final footerBottom = tester
          .getBottomLeft(find.text('Aplicar filtros'))
          .dy;
      expect(footerBottom, lessThanOrEqualTo(844 - 34));
    });

    for (final size in const <Size>[
      Size(360, 800),
      Size(390, 844),
      Size(412, 915),
      Size(430, 932),
    ]) {
      testWidgets(
        'footer sin reduccion de fuente ni texto partido en ${size.width.toInt()}px',
        (tester) async {
          await pumpDrawer(tester, size);

          expect(tester.takeException(), isNull);

          // El layout resuelve por ancho/Wrap: FittedBox NO encoge la fuente
          // (escala 1.0), asi que ambos textos se leen completos y comodos.
          expect(_labelScale(tester, 'Restablecer'), closeTo(1.0, 0.01));
          expect(_labelScale(tester, 'Aplicar filtros'), closeTo(1.0, 0.01));

          expect(_lineCount(tester, find.text('Restablecer')), 1);
          expect(_lineCount(tester, find.text('Aplicar filtros')), 1);

          // Jerarquia: la principal lleva relleno solido, la secundaria no.
          final primary = tester.widget<Material>(
            find
                .descendant(
                  of: find.byType(FilledButton),
                  matching: find.byType(Material),
                )
                .first,
          );
          expect(primary.color, isNotNull);
          expect(primary.color, isNot(Colors.transparent));

          final secondary = tester.widget<Material>(
            find
                .descendant(
                  of: find.byType(TextButton),
                  matching: find.byType(Material),
                )
                .first,
          );
          expect(secondary.color, Colors.transparent);
        },
      );
    }

    testWidgets('radio moderado: chips y panel no son "pill"', (tester) async {
      await pumpSelector(tester, const Size(390, 844));

      // Chip: radio 10 (rango 8-12 pedido), nunca el 999 del theme global.
      final chipMaterial = tester.widget<Material>(
        find
            .ancestor(of: find.text('Hoy'), matching: find.byType(Material))
            .first,
      );
      final chipShape = chipMaterial.shape! as RoundedRectangleBorder;
      final chipRadius = (chipShape.borderRadius as BorderRadius).topLeft.x;
      expect(chipRadius, kReportsFilterRadius);
      expect(chipRadius, inInclusiveRange(8, 12));

      // Panel de filtros: mismo radio moderado.
      final surfaceDecoration =
          tester
                  .widget<DecoratedBox>(
                    find
                        .descendant(
                          of: find.byType(DateRangeSelector),
                          matching: find.byType(DecoratedBox),
                        )
                        .first,
                  )
                  .decoration
              as BoxDecoration;
      final panelRadius =
          (surfaceDecoration.borderRadius! as BorderRadius).topLeft.x;
      expect(panelRadius, kReportsFilterRadius);
      expect(panelRadius, inInclusiveRange(8, 12));
    });

    testWidgets('desktop >=900 muestra periodo y categoria en una fila', (
      tester,
    ) async {
      const size = Size(1280, 1024);
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: size.width,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: DateRangeSelector(
                      selectedPeriod: DateRangePeriod.today,
                      customLabel: null,
                      onPeriodChanged: (_) {},
                    ),
                  ),
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 260,
                    child: CategoryFilterSelector(
                      categories: const ['Accesorios', 'Celulares'],
                      selectedCategory: null,
                      onChanged: (_) {},
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      for (final label in periodLabels) {
        expect(find.text(label), findsOneWidget, reason: label);
      }
      expect(find.text('Todas las categorías'), findsOneWidget);
      // En una sola fila: los periodos y la categoria comparten altura.
      final selectorDy = tester.getTopLeft(find.text('Hoy')).dy;
      final categoryDy = tester
          .getTopLeft(find.text('Todas las categorías'))
          .dy;
      expect((selectorDy - categoryDy).abs(), lessThan(40));
      expect(tester.getTopLeft(find.text('Semana')).dx, lessThan(600));
    });

    testWidgets('la categoria se alimenta solo de la lista del tenant', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 360,
              child: CategoryFilterSelector(
                categories: const <String>['Celulares'],
                selectedCategory: null,
                onChanged: (_) {},
              ),
            ),
          ),
        ),
      );

      // La lista cerrada solo muestra "Todas"; al desplegar aparecen
      // UNICAMENTE las categorias recibidas (del companyId activo).
      expect(find.text('Todas las categorías'), findsOneWidget);
      expect(find.text('Accesorios'), findsNothing);

      await tester.tap(find.byType(DropdownButton<String?>));
      await tester.pumpAndSettle();

      expect(find.text('Celulares'), findsWidgets);
      expect(find.text('Accesorios'), findsNothing);
    });

    test('Mes = mes calendario actual y Año = año actual', () {
      // DateTime no tiene constructor const.
      final reference = DateTime(2026, 9, 10, 15, 30);

      final month = DateRangeHelper.getRangeForPeriod(
        DateRangePeriod.month,
        now: reference,
      );
      expect(month.start, DateTime(2026, 9, 1));
      expect(month.end, DateTime(2026, 9, 10, 23, 59, 59, 999));

      final year = DateRangeHelper.getRangeForPeriod(
        DateRangePeriod.year,
        now: reference,
      );
      expect(year.start, DateTime(2026, 1, 1));
      expect(year.end, DateTime(2026, 9, 10, 23, 59, 59, 999));

      final yesterday = DateRangeHelper.getRangeForPeriod(
        DateRangePeriod.yesterday,
        now: reference,
      );
      expect(yesterday.start, DateTime(2026, 9, 9));
      expect(yesterday.end, DateTime(2026, 9, 9, 23, 59, 59, 999));

      // Semana = hoy + 6 anteriores = 7 fechas locales.
      final week = DateRangeHelper.getRangeForPeriod(
        DateRangePeriod.week,
        now: reference,
      );
      expect(week.start, DateTime(2026, 9, 4));
      expect(week.end, DateTime(2026, 9, 10, 23, 59, 59, 999));

      // Personalizado respeta Desde/Hasta.
      final custom = DateRangeHelper.getRangeForPeriod(
        DateRangePeriod.custom,
        customStart: DateTime(2026, 9, 5),
        customEnd: DateTime(2026, 9, 8),
        now: reference,
      );
      expect(custom.start, DateTime(2026, 9, 5));
      expect(custom.end, DateTime(2026, 9, 8, 23, 59, 59, 999));
    });
  });
}

/// Numero de lineas realmente renderizadas por un Text (1 = no se partio).
/// Compara la altura renderizada contra la altura de una sola linea del mismo
/// texto (que se mide con ancho ilimitado).
int _lineCount(WidgetTester tester, Finder finder) {
  final paragraph = tester.renderObject<RenderParagraph>(finder);
  final singleLine = TextPainter(
    text: paragraph.text,
    textDirection: TextDirection.ltr,
    textScaler: paragraph.textScaler,
    maxLines: null,
  )..layout();
  if (singleLine.height <= 0) return 1;
  return (paragraph.size.height / singleLine.height).round();
}

/// Desplazamiento maximo disponible dentro del selector de periodos.
double _selectorScrollExtent(WidgetTester tester) {
  return tester
      .state<ScrollableState>(
        find.descendant(
          of: find.byType(DateRangeSelector),
          matching: find.byType(Scrollable),
        ),
      )
      .position
      .maxScrollExtent;
}

/// Escala realmente aplicada por el FittedBox de una etiqueta de boton.
/// 1.0 = no se redujo la fuente (el layout ya le dio espacio suficiente).
double _labelScale(WidgetTester tester, String label) {
  final textSize = tester.getSize(find.text(label));
  final boxSize = tester.getSize(
    find.ancestor(of: find.text(label), matching: find.byType(FittedBox)).first,
  );
  return boxSize.width / textSize.width;
}

KpisData _financialKpis() {
  return KpisData.fromReport(<String, dynamic>{
    'kpis': <String, dynamic>{
      'totalSales': 4,
      'netSales': 2100,
      'totalProfit': 1228,
      'totalExpenses': 700,
      'netProfit': 528,
      'avgTicket': 525,
    },
  });
}

/// CASE A: sin gastos que afecten utilidad => utilidad bruta == utilidad neta
/// y la UI debe quedar compacta (sin tarjetas redundantes de bruta/gastos).
KpisData _kpisWithoutExpenses() {
  return KpisData.fromReport(<String, dynamic>{
    'kpis': <String, dynamic>{
      'totalSales': 3,
      'netSales': 1500,
      'totalProfit': 1000,
      'totalExpenses': 0,
      'netProfit': 1000,
      'avgTicket': 500,
    },
  });
}

ReportsFilterState _initialFilterState() => ReportsFilterState.initial;
