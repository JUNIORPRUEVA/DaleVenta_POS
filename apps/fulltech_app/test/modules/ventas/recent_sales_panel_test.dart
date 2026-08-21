import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:daleventa_pos/core/errors/api_exception.dart';
import 'package:daleventa_pos/modules/ventas/sales_models.dart';
import 'package:daleventa_pos/modules/ventas/widgets/recent_sales_panel.dart';

SaleModel _sale({
  String id = 'sale-1',
  double total = 100,
  bool isDeleted = false,
}) {
  return SaleModel(
    id: id,
    userId: 'user-1',
    userName: 'Caja',
    customerId: null,
    customerName: null,
    customerPhone: null,
    saleDate: DateTime(2026, 8, 1, 10),
    note: null,
    totalSold: total,
    totalCost: 0,
    totalProfit: total,
    commissionAmount: 0,
    paymentMethod: 'cash',
    paymentCashAmount: total,
    paymentTransferAmount: 0,
    creditAmount: 0,
    creditPaidAmount: 0,
    creditBalance: 0,
    creditStatus: 'none',
    isDeleted: isDeleted,
    deletedAt: null,
    items: const [],
  );
}

Future<void> _pumpPanel(
  WidgetTester tester, {
  required Future<List<SaleModel>> Function() loadSales,
  VoidCallback? onClose,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: RecentSalesPanel(
          loadSales: loadSales,
          money: (value) => '\$${value.toStringAsFixed(2)}',
          dateLabel: (_) => '01 ago',
          shortId: (sale) => sale.id.length > 6 ? sale.id.substring(0, 6) : sale.id,
          onViewSale: (_) {},
          onOpenPdf: (_) {},
          onReprintTicket: (_) {},
          onClose: onClose ?? () {},
          onOpenFullHistory: () {},
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('loading termina y con datos renderiza la lista', (tester) async {
    await _pumpPanel(tester, loadSales: () async => [_sale()]);

    // Primero muestra el spinner.
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await tester.pumpAndSettle();

    // Loading terminó: ya no hay spinner y la venta se renderiza.
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.textContaining('Factura'), findsOneWidget);
    expect(find.text('Activa'), findsOneWidget);
  });

  testWidgets('lista vacía muestra empty state', (tester) async {
    await _pumpPanel(tester, loadSales: () async => []);

    await tester.pumpAndSettle();

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('No hay ventas recientes'), findsOneWidget);
    // El botón al historial sigue disponible.
    expect(find.text('Ir al historial de ventas'), findsOneWidget);
  });

  testWidgets('error HTTP muestra error state con Reintentar', (tester) async {
    await _pumpPanel(
      tester,
      loadSales: () async => throw ApiException('No se pudieron cargar las ventas'),
    );

    await tester.pumpAndSettle();

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('No se pudieron cargar las ventas recientes.'), findsOneWidget);
    expect(find.text('Reintentar'), findsOneWidget);
  });

  testWidgets('excepción de mapping también termina en error state', (tester) async {
    await _pumpPanel(
      tester,
      loadSales: () async => throw StateError('campo inesperado'),
    );

    await tester.pumpAndSettle();

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('No se pudieron cargar las ventas recientes.'), findsOneWidget);
  });

  testWidgets('timeout (DioException) termina en error state', (tester) async {
    await _pumpPanel(
      tester,
      loadSales: () async => throw ApiException('timeout', 0),
    );

    await tester.pumpAndSettle();

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('No se pudieron cargar las ventas recientes.'), findsOneWidget);
  });

  testWidgets('Reintentar vuelve a cargar tras un error', (tester) async {
    var calls = 0;
    await _pumpPanel(
      tester,
      loadSales: () async {
        calls++;
        if (calls == 1) throw ApiException('falla');
        return [_sale(id: 'sale-42')];
      },
    );

    await tester.pumpAndSettle();
    expect(find.text('Reintentar'), findsOneWidget);

    await tester.tap(find.text('Reintentar'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Factura'), findsOneWidget);
    expect(find.text('Reintentar'), findsNothing);
    expect(calls, 2);
  });

  testWidgets('refresh manual no duplica requests mientras hay uno en vuelo', (tester) async {
    var calls = 0;
    final gate = Completer<List<SaleModel>>();
    await _pumpPanel(
      tester,
      loadSales: () {
        calls++;
        return gate.future;
      },
    );

    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    // Tocar refresh mientras carga NO lanza un segundo request.
    await tester.tap(find.byTooltip('Actualizar'));
    await tester.pump();
    expect(calls, 1);

    gate.complete([_sale()]);
    await tester.pumpAndSettle();
    expect(find.textContaining('Factura'), findsOneWidget);
    expect(calls, 1);
  });

  testWidgets('cerrar panel durante request no rompe ni pinta respuesta vieja', (tester) async {
    final gate = Completer<List<SaleModel>>();
    await _pumpPanel(tester, loadSales: () => gate.future);
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    // Cerrar/desmontar el panel mientras el request está en vuelo.
    await tester.pumpWidget(const SizedBox.shrink());

    // La respuesta vieja llega DESPUÉS del dispose: no debe lanzar
    // setState after dispose ni pintar nada.
    gate.complete([_sale()]);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  testWidgets('reabrir panel tras una venta nueva refresca la lista', (tester) async {
    // Primer panel: sin ventas.
    await _pumpPanel(tester, loadSales: () async => []);
    await tester.pumpAndSettle();
    expect(find.text('No hay ventas recientes'), findsOneWidget);

    // Se cierra (desmonta).
    await tester.pumpWidget(const SizedBox.shrink());

    // Se completa una venta y se reabre: el nuevo panel carga y muestra la venta.
    await _pumpPanel(tester, loadSales: () async => [_sale(id: 'sale-nueva')]);
    await tester.pumpAndSettle();

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.textContaining('Factura'), findsOneWidget);
  });
}
