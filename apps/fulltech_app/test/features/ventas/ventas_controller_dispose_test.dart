import 'dart:async';

import 'package:daleventa_pos/core/models/product_model.dart';
import 'package:daleventa_pos/modules/clientes/cliente_model.dart';
import 'package:daleventa_pos/modules/ventas/application/ventas_controller.dart';
import 'package:daleventa_pos/modules/ventas/data/ventas_repository.dart';
import 'package:daleventa_pos/modules/ventas/sales_models.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'ignores pending load results after VentasController is disposed',
    () async {
      final repo = _FakeVentasRepository();
      final container = ProviderContainer(
        overrides: [ventasRepositoryProvider.overrideWithValue(repo)],
      );

      container.read(ventasControllerProvider);
      await Future<void>.delayed(Duration.zero);
      container.dispose();

      repo.cachedSalesCompleter.complete(const <SaleModel>[]);
      repo.cachedSummaryCompleter.complete(null);
      await Future<void>.delayed(Duration.zero);

      repo.listSalesCompleter.complete(const <SaleModel>[]);
      repo.summaryCompleter.complete(SalesSummaryModel.empty());
      await Future<void>.delayed(Duration.zero);
    },
  );
}

class _FakeVentasRepository implements VentasRepository {
  final cachedSalesCompleter = Completer<List<SaleModel>>();
  final cachedSummaryCompleter = Completer<SalesSummaryModel?>();
  final listSalesCompleter = Completer<List<SaleModel>>();
  final summaryCompleter = Completer<SalesSummaryModel>();

  @override
  Future<List<SaleModel>> cachedSales({
    required DateTime from,
    required DateTime to,
    String? userId,
    String? customerId,
    bool includeDeleted = false,
  }) {
    return cachedSalesCompleter.future;
  }

  @override
  Future<SalesSummaryModel?> cachedSummary({
    required DateTime from,
    required DateTime to,
    String? userId,
    String? customerId,
  }) {
    return cachedSummaryCompleter.future;
  }

  @override
  Future<List<SaleModel>> listSales({
    required DateTime from,
    required DateTime to,
    String? userId,
    String? customerId,
    bool includeDeleted = false,
  }) {
    return listSalesCompleter.future;
  }

  @override
  Future<SalesSummaryModel> summary({
    required DateTime from,
    required DateTime to,
    String? userId,
    String? customerId,
  }) {
    return summaryCompleter.future;
  }

  @override
  Future<SaleModel> returnSale(String id) {
    throw UnimplementedError();
  }

  @override
  Future<void> deleteSale(String id) async {}

  @override
  Future<Map<String, dynamic>> purgeAllDebug() async {
    return const {'deletedSales': 0};
  }

  @override
  Future<SaleModel> addCreditPayment({
    required String saleId,
    required double cashAmount,
    required double transferAmount,
    String? note,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<List<SaleModel>> adminListSalesByUser({
    required DateTime from,
    required DateTime to,
    required String userId,
    bool includeDeleted = false,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<AdminSalesUsersSummary> adminSummaryByUser({
    required DateTime from,
    required DateTime to,
    String? userId,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<List<SaleModel>> cachedCredits() {
    throw UnimplementedError();
  }

  @override
  Future<List<SaleModel>> cachedInvoices({
    required DateTime from,
    required DateTime to,
    String? customerId,
    bool includeDeleted = true,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<SaleModel?> createSale({
    String? sourceQuotationId,
    String? customerId,
    String? customerName,
    String? customerPhone,
    String? note,
    String? paymentMethod,
    double? paymentCashAmount,
    double? paymentTransferAmount,
    double? creditAmount,
    double? expectedTotalSold,
    double? globalDiscountAmount,
    String? fiscalVoucherType,
    String? fiscalCustomerTaxId,
    String? fiscalCustomerName,
    bool? saveFiscalCustomer,
    required List<SaleDraftItem> items,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<ClienteModel> createQuickClient({
    required String nombre,
    required String telefono,
    String? taxId,
    String? businessName,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<List<ProductModel>> fetchProducts({bool forceRefresh = false}) {
    throw UnimplementedError();
  }

  @override
  Future<SaleModel> getById(String id) {
    throw UnimplementedError();
  }

  @override
  Future<List<SaleModel>> listCredits({bool includePaid = false}) {
    throw UnimplementedError();
  }

  @override
  Future<List<SaleModel>> listInvoices({
    required DateTime from,
    required DateTime to,
    String? customerId,
    bool includeDeleted = true,
  }) {
    throw UnimplementedError();
  }

  @override
  void registerSyncHandlers() {}

  @override
  Future<Map<String, dynamic>> reportsSalesOverview({
    required DateTime from,
    required DateTime to,
    String? category,
  }) {
    throw UnimplementedError();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
