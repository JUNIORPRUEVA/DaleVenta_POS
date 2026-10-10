import 'dart:async';

import 'package:daleventa_pos/core/errors/api_exception.dart';
import 'package:daleventa_pos/core/offline/offline_store.dart';
import 'package:daleventa_pos/core/offline/sync_queue_service.dart';
import 'package:daleventa_pos/features/reports/ui/reports_page.dart';
import 'package:daleventa_pos/features/warehouses/data/warehouse_repository.dart';
import 'package:daleventa_pos/modules/ventas/data/ventas_repository.dart';
import 'package:daleventa_pos/modules/ventas/sales_models.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Pruebas de CARGA de la pantalla de Reportes.
///
/// Incidente reportado: "Reportes a veces no entra / no carga". Causa raiz
/// comprobada: el primer render esperaba en cadena el resumen + el detalle +
/// 6 comparativas (8 peticiones), de modo que un enlace lento dejaba la
/// pantalla en spinner. Ahora el resumen (agregado del backend) pinta la
/// pantalla y detalle/comparativas se cargan aparte.
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('el resumen pinta la pantalla aunque las comparativas no lleguen', (
    tester,
  ) async {
    final repo = _FakeReportsRepository(comparisonsNeverComplete: true);
    await _pumpReports(tester, repo);

    expect(
      find.textContaining('999'),
      findsWidgets,
      reason: 'los KPIs del backend deben verse sin esperar comparaciones',
    );
    expect(find.text('No se pudieron cargar los reportes'), findsNothing);
  });

  testWidgets('un detalle lento no bloquea el primer render', (tester) async {
    final repo = _FakeReportsRepository(salesNeverComplete: true);
    await _pumpReports(tester, repo);

    expect(find.textContaining('999'), findsWidgets);
    expect(find.text('No se pudieron cargar los reportes'), findsNothing);
  });

  testWidgets('un fallo en las comparativas no rompe la pantalla', (
    tester,
  ) async {
    final repo = _FakeReportsRepository(
      comparisonsError: ApiException('boom', 500),
    );
    await _pumpReports(tester, repo);

    expect(find.textContaining('999'), findsWidgets);
    expect(find.text('No se pudieron cargar los reportes'), findsNothing);
  });

  testWidgets('si falla el resumen se muestra el error de la pantalla', (
    tester,
  ) async {
    final repo = _FakeReportsRepository(
      overviewError: ApiException('boom', 500),
    );
    await _pumpReports(tester, repo);

    expect(find.text('No se pudieron cargar los reportes'), findsOneWidget);
    expect(find.textContaining('999'), findsNothing);
  });

  testWidgets('los totales del periodo vienen del backend, no del detalle', (
    tester,
  ) async {
    // Sin detalle cargado: si la pantalla sumara filas locales, el total seria 0.
    final repo = _FakeReportsRepository(detail: const []);
    await _pumpReports(tester, repo);

    expect(
      find.textContaining('999'),
      findsWidgets,
      reason: 'el KPI es el agregado del backend (no un fold de la pagina)',
    );
  });
}

Future<void> _pumpReports(
  WidgetTester tester,
  _FakeReportsRepository repo,
) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [ventasRepositoryProvider.overrideWithValue(repo)],
      child: const MaterialApp(home: ReportsPage()),
    ),
  );
  // La pantalla usa indicadores animados: se avanza con pumps explicitos en
  // lugar de pumpAndSettle (que no terminaria mientras haya un spinner).
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
  await tester.pump(const Duration(milliseconds: 50));
}

class _FakeReportsRepository extends VentasRepository {
  _FakeReportsRepository({
    this.overviewError,
    this.comparisonsError,
    this.comparisonsNeverComplete = false,
    this.salesNeverComplete = false,
    this.detail = const [],
  }) : super(
         Dio(),
         SyncQueueService(OfflineStore.instance),
         WarehouseRepository(Dio()),
       );

  final Object? overviewError;
  final Object? comparisonsError;
  final bool comparisonsNeverComplete;
  final bool salesNeverComplete;
  final List<SaleModel> detail;

  static const Map<String, dynamic> _overviewPayload = {
    'kpis': {
      'totalSales': 3,
      'netSales': 999.0,
      'totalProfit': 123.0,
      'grossProfit': 123.0,
      'avgTicket': 333.0,
    },
    'categories': <dynamic>[],
    'salesSeries': <dynamic>[],
    'profitSeries': <dynamic>[],
    'paymentMethods': <dynamic>[],
    'topProducts': <dynamic>[],
    'topClients': <dynamic>[],
    'categoryProfits': <dynamic>[],
  };

  @override
  Future<Map<String, dynamic>> reportsSalesOverview({
    required DateTime from,
    required DateTime to,
    String? category,
    bool summaryOnly = false,
  }) async {
    if (!summaryOnly) {
      if (overviewError != null) throw overviewError!;
      return _overviewPayload;
    }
    if (comparisonsNeverComplete) {
      return Completer<Map<String, dynamic>>().future;
    }
    if (comparisonsError != null) throw comparisonsError!;
    return const {
      'kpis': {'totalSales': 0, 'netSales': 0.0},
    };
  }

  @override
  Future<List<SaleModel>> listInvoices({
    required DateTime from,
    required DateTime to,
    String? customerId,
    bool includeDeleted = true,
    int? limit,
  }) {
    if (salesNeverComplete) {
      return Completer<List<SaleModel>>().future;
    }
    return Future<List<SaleModel>>.value(detail);
  }
}
