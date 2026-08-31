import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_routes.dart';
import '../../../core/auth/auth_repository.dart';
import '../../../core/auth/token_storage.dart';
import '../../../core/cache/local_json_cache.dart';
import '../../../core/debug/trace_log.dart';
import '../../../core/errors/api_exception.dart';
import '../../../core/models/product_model.dart';
import '../../../core/offline/offline_store.dart';
import '../../../core/offline/pending_sync_action.dart';
import '../../../core/offline/sync_queue_service.dart';
import '../../../core/usage/client_telemetry_headers.dart';
import '../../../features/warehouses/data/warehouse_repository.dart';
import '../../clientes/cliente_model.dart';
import '../sales_models.dart';

final ventasRepositoryProvider = Provider<VentasRepository>((ref) {
  final repository = VentasRepository(
    ref.watch(dioProvider),
    ref.read(syncQueueServiceProvider.notifier),
    ref.read(warehouseRepositoryProvider),
  );
  repository.registerSyncHandlers();
  return repository;
});

class VentasRepository {
  final Dio _dio;
  final SyncQueueService _syncQueue;
  final WarehouseRepository _warehouseRepository;
  final LocalJsonCache _cache = LocalJsonCache();
  final OfflineStore _offlineStore = OfflineStore.instance;
  final TokenStorage _tokenStorage = TokenStorage();
  static const String _createSaleSyncType = 'sales.create';
  static const String _creditsCacheKey = 'sales.credits.v1';
  bool _handlersRegistered = false;

  VentasRepository(this._dio, this._syncQueue, this._warehouseRepository);

  void registerSyncHandlers() {
    if (_handlersRegistered) return;
    _handlersRegistered = true;
    _syncQueue.registerHandler(_createSaleSyncType, (payload) async {
      final clientRequestId = payload['clientRequestId']?.toString().trim();
      final user = await _tokenStorage.getUserSnapshot();
      final companyId = user?.companyId?.trim();
      SaleModel? sale;
      try {
        sale = await _createSaleRemote(
          customerId: payload['customerId']?.toString(),
          note: payload['note']?.toString(),
          paymentMethod: payload['paymentMethod']?.toString(),
          paymentCashAmount: _nullableDouble(payload['paymentCashAmount']),
          paymentTransferAmount: _nullableDouble(
            payload['paymentTransferAmount'],
          ),
          creditAmount: _nullableDouble(payload['creditAmount']),
          expectedTotalSold: _nullableDouble(payload['expectedTotalSold']),
          globalDiscountAmount: _nullableDouble(
            payload['globalDiscountAmount'],
          ),
          fiscalVoucherType: payload['fiscalVoucherType']?.toString(),
          fiscalCustomerTaxId: payload['fiscalCustomerTaxId']?.toString(),
          fiscalCustomerName: payload['fiscalCustomerName']?.toString(),
          clientRequestId: clientRequestId,
          terminalId: payload['terminalId']?.toString(),
          warehouseId: payload['warehouseId']?.toString(),
          deviceFingerprint: payload['deviceFingerprint']?.toString(),
          saleOccurredAt: payload['saleOccurredAt']?.toString(),
          items: ((payload['items'] as List?) ?? const [])
              .whereType<Map>()
              .map(
                (item) =>
                    SaleDraftItem.fromPayload(item.cast<String, dynamic>()),
              )
              .toList(growable: false),
        );
      } on DioException catch (error) {
        if (error.response?.statusCode == 409 &&
            (clientRequestId ?? '').isNotEmpty &&
            (companyId ?? '').isNotEmpty) {
          await _offlineStore.markOfflineSaleConflict(
            companyId: companyId!,
            clientRequestId: clientRequestId!,
            conflict: _conflictPayloadFromResponse(error.response?.data),
          );
        }
        rethrow;
      }
      if (sale != null &&
          (clientRequestId ?? '').isNotEmpty &&
          (companyId ?? '').isNotEmpty) {
        await _offlineStore.markOfflineSaleSynced(
          companyId: companyId!,
          clientRequestId: clientRequestId!,
          serverSaleId: sale.id,
        );
      }
    });
  }

  List<dynamic> _extractRows(dynamic data) {
    if (data is List) return data;
    if (data is Map) {
      const keys = ['items', 'data', 'products', 'rows'];
      for (final key in keys) {
        final candidate = data[key];
        if (candidate is List) return candidate;
      }
    }
    return const [];
  }

  String _extractMessage(dynamic data, String fallback) {
    if (data is Map) {
      final message = data['message'];
      if (message is String && message.trim().isNotEmpty) return message;
      if (message is List && message.isNotEmpty) {
        final first = message.first;
        if (first is String && first.trim().isNotEmpty) return first;
      }
    }
    return fallback;
  }

  Future<List<SaleModel>> listSales({
    required DateTime from,
    required DateTime to,
    String? userId,
    String? customerId,
    bool includeDeleted = false,
    int? limit,
  }) async {
    final requestedLimit = (limit != null && limit > 0) ? limit : null;
    try {
      return await _requestSalesRows(
        path: ApiRoutes.sales,
        from: from,
        to: to,
        userId: userId,
        customerId: customerId,
        includeDeleted: includeDeleted,
        limit: requestedLimit,
        cacheKey: _salesListCacheKey(
          from: from,
          to: to,
          userId: userId,
          customerId: customerId,
          includeDeleted: includeDeleted,
          limit: requestedLimit,
        ),
      );
    } on DioException catch (e, stackTrace) {
      _logRecentSalesError('GET ${ApiRoutes.sales}', e, stackTrace);
      if (requestedLimit != null && _isLimitPropertyRejected(e)) {
        // Compatibilidad temporal con backend anterior (version skew):
        // el backend NO acepta `limit`; reintentamos UNA vez sin él y
        // recortamos localmente. Solo aplica a este rechazo específico.
        try {
          final compatRows = await _requestSalesRows(
            path: ApiRoutes.sales,
            from: from,
            to: to,
            userId: userId,
            customerId: customerId,
            includeDeleted: includeDeleted,
            limit: null,
            cacheKey: _salesListCacheKey(
              from: from,
              to: to,
              userId: userId,
              customerId: customerId,
              includeDeleted: includeDeleted,
              limit: null,
            ),
          );
          return compatRows.take(requestedLimit).toList(growable: false);
        } on DioException catch (retryError, retryStack) {
          _logRecentSalesError(
            'GET ${ApiRoutes.sales} (compat retry sin limit)',
            retryError,
            retryStack,
          );
        }
      }
      throw ApiException(
        _extractMessage(e.response?.data, 'No se pudieron cargar las ventas'),
        e.response?.statusCode,
      );
    }
  }

  Future<List<SaleModel>> cachedSales({
    required DateTime from,
    required DateTime to,
    String? userId,
    String? customerId,
    bool includeDeleted = false,
    int? limit,
  }) async {
    final data = await _cache.readMap(
      _salesListCacheKey(
        from: from,
        to: to,
        userId: userId,
        customerId: customerId,
        includeDeleted: includeDeleted,
        limit: limit,
      ),
    );
    final rows = _extractRows(data);
    return rows
        .whereType<Map>()
        .map((e) => SaleModel.fromJson(e.cast<String, dynamic>()))
        .toList(growable: false);
  }

  Future<List<SaleModel>> listInvoices({
    required DateTime from,
    required DateTime to,
    String? customerId,
    bool includeDeleted = true,
    int? limit,
  }) async {
    final requestedLimit = (limit != null && limit > 0) ? limit : null;
    try {
      return await _requestSalesRows(
        path: ApiRoutes.salesInvoices,
        from: from,
        to: to,
        customerId: customerId,
        includeDeleted: includeDeleted,
        limit: requestedLimit,
        cacheKey: _salesInvoicesCacheKey(
          from: from,
          to: to,
          customerId: customerId,
          includeDeleted: includeDeleted,
          limit: requestedLimit,
        ),
      );
    } on DioException catch (e, stackTrace) {
      _logRecentSalesError('GET ${ApiRoutes.salesInvoices}', e, stackTrace);
      if (requestedLimit != null && _isLimitPropertyRejected(e)) {
        try {
          final compatRows = await _requestSalesRows(
            path: ApiRoutes.salesInvoices,
            from: from,
            to: to,
            customerId: customerId,
            includeDeleted: includeDeleted,
            limit: null,
            cacheKey: _salesInvoicesCacheKey(
              from: from,
              to: to,
              customerId: customerId,
              includeDeleted: includeDeleted,
              limit: null,
            ),
          );
          return compatRows.take(requestedLimit).toList(growable: false);
        } on DioException catch (retryError, retryStack) {
          _logRecentSalesError(
            'GET ${ApiRoutes.salesInvoices} (compat retry sin limit)',
            retryError,
            retryStack,
          );
        }
      }
      final cached = await cachedInvoices(
        from: from,
        to: to,
        customerId: customerId,
        includeDeleted: includeDeleted,
        limit: limit,
      );
      if (cached.isNotEmpty) return cached;
      throw ApiException(
        _extractMessage(e.response?.data, 'No se pudieron cargar las facturas'),
        e.response?.statusCode,
      );
    }
  }

  Future<List<SaleModel>> cachedInvoices({
    required DateTime from,
    required DateTime to,
    String? customerId,
    bool includeDeleted = true,
    int? limit,
  }) async {
    final data = await _cache.readMap(
      _salesInvoicesCacheKey(
        from: from,
        to: to,
        customerId: customerId,
        includeDeleted: includeDeleted,
        limit: limit,
      ),
    );
    final rows = _extractRows(data);
    return rows
        .whereType<Map>()
        .map((e) => SaleModel.fromJson(e.cast<String, dynamic>()))
        .toList(growable: false);
  }

  Future<SalesSummaryModel> summary({
    required DateTime from,
    required DateTime to,
    String? userId,
    String? customerId,
  }) async {
    try {
      final res = await _dio.get(
        ApiRoutes.salesSummary,
        queryParameters: {
          'from': _dateOnly(from),
          'to': _dateOnly(to),
          if ((userId ?? '').trim().isNotEmpty) 'userId': userId!.trim(),
          if ((customerId ?? '').trim().isNotEmpty)
            'customerId': customerId!.trim(),
        },
        options: Options(extra: const {'skipLoader': true}),
      );
      final raw = res.data;
      if (raw is! Map) {
        throw ApiException(
          'El servidor devolvió una respuesta vacía o inválida al cargar el resumen',
          res.statusCode,
        );
      }
      final data = raw.cast<String, dynamic>();
      await _cache.writeMap(
        _salesSummaryCacheKey(
          from: from,
          to: to,
          userId: userId,
          customerId: customerId,
        ),
        data,
      );
      return SalesSummaryModel.fromJson(data);
    } on DioException catch (e) {
      throw ApiException(
        _extractMessage(e.response?.data, 'No se pudo cargar el resumen'),
        e.response?.statusCode,
      );
    }
  }

  Future<SalesSummaryModel?> cachedSummary({
    required DateTime from,
    required DateTime to,
    String? userId,
    String? customerId,
  }) async {
    final data = await _cache.readMap(
      _salesSummaryCacheKey(
        from: from,
        to: to,
        userId: userId,
        customerId: customerId,
      ),
    );
    if (data == null) return null;
    return SalesSummaryModel.fromJson(data);
  }

  Future<List<SaleModel>> listCredits({bool includePaid = false}) async {
    try {
      final res = await _dio.get(
        ApiRoutes.salesCredits,
        queryParameters: {if (includePaid) 'includePaid': 'true'},
        options: Options(extra: const {'skipLoader': true}),
      );
      final rows = res.data is List ? (res.data as List) : const [];
      if (includePaid) {
        await _cache.writeMap(_creditsCacheKey, {'items': rows});
      }
      return rows
          .whereType<Map>()
          .map((e) => SaleModel.fromJson(e.cast<String, dynamic>()))
          .toList(growable: false);
    } on DioException catch (e) {
      throw ApiException(
        _extractMessage(e.response?.data, 'No se pudieron cargar los créditos'),
        e.response?.statusCode,
      );
    }
  }

  Future<List<SaleModel>> cachedCredits() async {
    final data = await _cache.readMap(_creditsCacheKey);
    final rows = _extractRows(data);
    return rows
        .whereType<Map>()
        .map((e) => SaleModel.fromJson(e.cast<String, dynamic>()))
        .toList(growable: false);
  }

  Future<SaleModel> addCreditPayment({
    required String saleId,
    required double cashAmount,
    required double transferAmount,
    String? note,
  }) async {
    try {
      final res = await _dio.post(
        ApiRoutes.saleCreditPayments(saleId),
        data: {
          'cashAmount': cashAmount,
          'transferAmount': transferAmount,
          if ((note ?? '').trim().isNotEmpty) 'note': note!.trim(),
        },
      );
      final data = (res.data as Map).cast<String, dynamic>();
      final sale = data['sale'];
      return SaleModel.fromJson((sale as Map).cast<String, dynamic>());
    } on DioException catch (e) {
      throw ApiException(
        _extractMessage(e.response?.data, 'No se pudo registrar el abono'),
        e.response?.statusCode,
      );
    }
  }

  Future<Map<String, dynamic>> reportsSalesOverview({
    required DateTime from,
    required DateTime to,
    String? category,
  }) async {
    try {
      final res = await _dio.get(
        ApiRoutes.reportsSalesOverview,
        queryParameters: {
          'from': _dateOnly(from),
          'to': _dateOnly(to),
          if ((category ?? '').trim().isNotEmpty) 'category': category!.trim(),
        },
        options: Options(extra: const {'skipLoader': true}),
      );
      final raw = res.data;
      if (raw is! Map) {
        throw ApiException(
          'El servidor devolvió una respuesta vacía o inválida al cargar el reporte',
          res.statusCode,
        );
      }
      return raw.cast<String, dynamic>();
    } on DioException catch (e) {
      throw ApiException(
        _extractMessage(e.response?.data, 'No se pudo cargar el reporte'),
        e.response?.statusCode,
      );
    }
  }

  Future<AdminSalesUsersSummary> adminSummaryByUser({
    required DateTime from,
    required DateTime to,
    String? userId,
  }) async {
    try {
      final res = await _dio.get(
        ApiRoutes.adminSalesSummary,
        queryParameters: {
          'from': _dateOnly(from),
          'to': _dateOnly(to),
          if ((userId ?? '').trim().isNotEmpty) 'userId': userId!.trim(),
        },
        options: Options(extra: const {'skipLoader': true}),
      );
      return AdminSalesUsersSummary.fromJson(
        (res.data as Map).cast<String, dynamic>(),
      );
    } on DioException catch (e) {
      throw ApiException(
        _extractMessage(
          e.response?.data,
          'No se pudo cargar el resumen administrativo de ventas',
        ),
        e.response?.statusCode,
      );
    }
  }

  Future<List<SaleModel>> adminListSalesByUser({
    required DateTime from,
    required DateTime to,
    required String userId,
    bool includeDeleted = false,
  }) async {
    try {
      final res = await _dio.get(
        ApiRoutes.adminSales,
        queryParameters: {
          'from': _dateOnly(from),
          'to': _dateOnly(to),
          'userId': userId.trim(),
          if (includeDeleted) 'includeDeleted': 'true',
        },
        options: Options(extra: const {'skipLoader': true}),
      );

      final rows = res.data is List ? (res.data as List) : const [];
      return rows
          .whereType<Map>()
          .map((e) => SaleModel.fromJson(e.cast<String, dynamic>()))
          .toList(growable: false);
    } on DioException catch (e) {
      throw ApiException(
        _extractMessage(
          e.response?.data,
          'No se pudieron cargar las ventas del usuario',
        ),
        e.response?.statusCode,
      );
    }
  }

  Future<void> deleteSale(String id) async {
    try {
      await _dio.delete(ApiRoutes.saleDetail(id));
    } on DioException catch (e) {
      throw ApiException(
        _extractMessage(e.response?.data, 'No se pudo eliminar la venta'),
        e.response?.statusCode,
      );
    }
  }

  Future<SaleModel> returnSale(String id) async {
    try {
      final res = await _dio.post(ApiRoutes.saleReturn(id));
      return SaleModel.fromJson((res.data as Map).cast<String, dynamic>());
    } on DioException catch (e) {
      throw ApiException(
        _extractMessage(e.response?.data, 'No se pudo devolver la venta'),
        e.response?.statusCode,
      );
    }
  }

  Future<String> createInvoicePdfShareLink({
    required String saleId,
    required List<int> pdfBytes,
    String? fileName,
  }) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        ApiRoutes.salesPdfShareLink,
        data: {
          'saleId': saleId.trim(),
          'pdfBase64': base64Encode(pdfBytes),
          if (fileName != null && fileName.trim().isNotEmpty)
            'fileName': fileName.trim(),
        },
      );
      final pdfUrl = (response.data?['pdfUrl'] ?? '').toString().trim();
      if (pdfUrl.isEmpty) {
        throw ApiException('No se pudo generar el enlace de la factura');
      }
      return pdfUrl;
    } on DioException catch (e) {
      throw ApiException(
        _extractMessage(
          e.response?.data,
          'No se pudo generar el enlace de la factura',
        ),
        e.response?.statusCode,
      );
    }
  }

  Future<Map<String, dynamic>> purgeAllDebug() async {
    try {
      final res = await _dio.delete(ApiRoutes.salesDebugPurge);
      return Map<String, dynamic>.from(
        (res.data as Map?) ?? const <String, dynamic>{},
      );
    } on DioException catch (e) {
      throw ApiException(
        _extractMessage(e.response?.data, 'No se pudieron limpiar las ventas'),
        e.response?.statusCode,
      );
    }
  }

  Future<SaleModel> getById(String id) async {
    try {
      final res = await _dio.get(ApiRoutes.saleDetail(id));
      return SaleModel.fromJson((res.data as Map).cast<String, dynamic>());
    } on DioException catch (e) {
      throw ApiException(
        _extractMessage(e.response?.data, 'No se pudo cargar la venta'),
        e.response?.statusCode,
      );
    }
  }

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
    required List<SaleDraftItem> items,
  }) async {
    if (items.isEmpty) {
      throw ApiException('Agrega al menos un item');
    }
    final normalizedCustomerId = (customerId ?? '').trim();
    final normalizedSourceQuotationId = (sourceQuotationId ?? '').trim();
    final clientRequestId = 'sale_req_${DateTime.now().microsecondsSinceEpoch}';
    final occurredAt = DateTime.now().toUtc();
    final syncIdentity = await _resolveSaleSyncIdentity();
    final payload = {
      'clientRequestId': clientRequestId,
      'saleOccurredAt': occurredAt.toIso8601String(),
      if ((syncIdentity.deviceFingerprint ?? '').isNotEmpty)
        'deviceFingerprint': syncIdentity.deviceFingerprint,
      if ((syncIdentity.terminalId ?? '').isNotEmpty)
        'terminalId': syncIdentity.terminalId,
      if ((syncIdentity.warehouseId ?? '').isNotEmpty)
        'warehouseId': syncIdentity.warehouseId,
      if (normalizedSourceQuotationId.isNotEmpty)
        'sourceQuotationId': normalizedSourceQuotationId,
      if (normalizedCustomerId.isNotEmpty) 'customerId': normalizedCustomerId,
      if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
      if ((paymentMethod ?? '').trim().isNotEmpty)
        'paymentMethod': paymentMethod!.trim(),
      if (paymentCashAmount != null) 'paymentCashAmount': paymentCashAmount,
      if (paymentTransferAmount != null)
        'paymentTransferAmount': paymentTransferAmount,
      if (creditAmount != null) 'creditAmount': creditAmount,
      if (expectedTotalSold != null) 'expectedTotalSold': expectedTotalSold,
      if (globalDiscountAmount != null)
        'globalDiscountAmount': globalDiscountAmount,
      if ((fiscalVoucherType ?? '').trim().isNotEmpty)
        'fiscalVoucherType': fiscalVoucherType!.trim().toUpperCase(),
      if ((fiscalCustomerTaxId ?? '').trim().isNotEmpty)
        'fiscalCustomerTaxId': fiscalCustomerTaxId!.trim(),
      if ((fiscalCustomerName ?? '').trim().isNotEmpty)
        'fiscalCustomerName': fiscalCustomerName!.trim(),
      'items': items.map((item) => item.toPayload()).toList(),
    };

    try {
      return await _createSaleRemote(
        customerId: customerId,
        sourceQuotationId: sourceQuotationId,
        note: note,
        paymentMethod: paymentMethod,
        paymentCashAmount: paymentCashAmount,
        paymentTransferAmount: paymentTransferAmount,
        creditAmount: creditAmount,
        expectedTotalSold: expectedTotalSold,
        globalDiscountAmount: globalDiscountAmount,
        fiscalVoucherType: fiscalVoucherType,
        fiscalCustomerTaxId: fiscalCustomerTaxId,
        fiscalCustomerName: fiscalCustomerName,
        clientRequestId: clientRequestId,
        terminalId: syncIdentity.terminalId,
        warehouseId: syncIdentity.warehouseId,
        deviceFingerprint: syncIdentity.deviceFingerprint,
        saleOccurredAt: occurredAt.toIso8601String(),
        items: items,
      );
    } on DioException catch (e) {
      if (!_shouldQueueNetworkFailure(e)) {
        throw ApiException(
          _extractMessage(e.response?.data, 'No se pudo guardar la venta'),
          e.response?.statusCode,
        );
      }
      if ((fiscalVoucherType ?? '').trim().isNotEmpty) {
        throw ApiException(
          'La factura fiscal requiere conexión para que el backend asigne el NCF. Mantén el carrito y vuelve a emitir cuando regrese la conexión.',
          e.response?.statusCode,
        );
      }
      final user = await _tokenStorage.getUserSnapshot();
      final companyId = user?.companyId?.trim();
      final userId = user?.id.trim();
      if ((companyId ?? '').isEmpty || (userId ?? '').isEmpty) {
        throw ApiException(
          'No se pudo guardar la venta offline porque la sesión local no tiene empresa/usuario confiable.',
          e.response?.statusCode,
        );
      }
      final localId = 'local_$clientRequestId';
      final pendingAction = PendingSyncAction(
        id: '$_createSaleSyncType:$localId',
        type: _createSaleSyncType,
        scope: 'sales',
        companyId: companyId,
        userId: userId,
        entityType: 'sale',
        entityId: localId,
        terminalId: syncIdentity.terminalId,
        idempotencyKey: clientRequestId,
        payload: payload,
        status: 'pending',
        attempts: 0,
        createdAt: occurredAt,
        updatedAt: occurredAt,
      );
      final itemPayloads = items.map((item) => item.toPayload()).toList();
      await _offlineStore.saveOfflineSaleAtomically(
        localSaleId: localId,
        companyId: companyId!,
        userId: userId!,
        clientRequestId: clientRequestId,
        salePayload: payload,
        itemPayloads: itemPayloads,
        paymentPayload: {
          'paymentMethod': paymentMethod ?? 'cash',
          'paymentCashAmount': paymentCashAmount ?? expectedTotalSold ?? 0,
          'paymentTransferAmount': paymentTransferAmount ?? 0,
          'creditAmount': creditAmount ?? 0,
        },
        pendingAction: pendingAction,
        totalSold: expectedTotalSold ?? _sumItems(items),
        saleOccurredAt: occurredAt,
      );
      await _syncQueue.refreshStats();
      return _optimisticSale(
        id: localId,
        userId: userId,
        userName: _displayNameFromUserSnapshot(user),
        customerId: normalizedCustomerId.isEmpty ? null : normalizedCustomerId,
        customerName: customerName,
        customerPhone: customerPhone,
        note: note,
        paymentMethod: paymentMethod ?? 'cash',
        paymentCashAmount: paymentCashAmount ?? expectedTotalSold ?? 0,
        paymentTransferAmount: paymentTransferAmount ?? 0,
        creditAmount: creditAmount ?? 0,
        items: items,
        totalSold: expectedTotalSold,
      );
    }
  }

  Future<SaleModel?> _createSaleRemote({
    String? customerId,
    String? sourceQuotationId,
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
    String? clientRequestId,
    String? terminalId,
    String? warehouseId,
    String? deviceFingerprint,
    String? saleOccurredAt,
    required List<SaleDraftItem> items,
  }) async {
    final normalizedCustomerId = (customerId ?? '').trim();
    final normalizedSourceQuotationId = (sourceQuotationId ?? '').trim();
    final res = await _dio.post(
      ApiRoutes.sales,
      data: {
        if ((clientRequestId ?? '').trim().isNotEmpty)
          'clientRequestId': clientRequestId!.trim(),
        if ((saleOccurredAt ?? '').trim().isNotEmpty)
          'saleOccurredAt': saleOccurredAt!.trim(),
        if ((deviceFingerprint ?? '').trim().isNotEmpty)
          'deviceFingerprint': deviceFingerprint!.trim(),
        if ((terminalId ?? '').trim().isNotEmpty)
          'terminalId': terminalId!.trim(),
        if ((warehouseId ?? '').trim().isNotEmpty)
          'warehouseId': warehouseId!.trim(),
        if (normalizedSourceQuotationId.isNotEmpty)
          'sourceQuotationId': normalizedSourceQuotationId,
        if (normalizedCustomerId.isNotEmpty) 'customerId': normalizedCustomerId,
        if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
        if ((paymentMethod ?? '').trim().isNotEmpty)
          'paymentMethod': paymentMethod!.trim(),
        if (paymentCashAmount != null) 'paymentCashAmount': paymentCashAmount,
        if (paymentTransferAmount != null)
          'paymentTransferAmount': paymentTransferAmount,
        if (creditAmount != null) 'creditAmount': creditAmount,
        if (expectedTotalSold != null) 'expectedTotalSold': expectedTotalSold,
        if (globalDiscountAmount != null)
          'globalDiscountAmount': globalDiscountAmount,
        if ((fiscalVoucherType ?? '').trim().isNotEmpty)
          'fiscalVoucherType': fiscalVoucherType!.trim().toUpperCase(),
        if ((fiscalCustomerTaxId ?? '').trim().isNotEmpty)
          'fiscalCustomerTaxId': fiscalCustomerTaxId!.trim(),
        if ((fiscalCustomerName ?? '').trim().isNotEmpty)
          'fiscalCustomerName': fiscalCustomerName!.trim(),
        'items': items.map((item) => item.toPayload()).toList(),
      },
    );
    if (res.data is Map) {
      return SaleModel.fromJson((res.data as Map).cast<String, dynamic>());
    }
    return null;
  }

  bool _shouldQueueNetworkFailure(DioException error) {
    final status = error.response?.statusCode;
    return status == null || status >= 500;
  }

  Future<_SaleSyncIdentity> _resolveSaleSyncIdentity() async {
    String? deviceId;
    try {
      final headers = await ClientTelemetryHeaders.instance.headers();
      deviceId = headers['x-client-device-id']?.trim();
    } catch (_) {
      deviceId = null;
    }

    List<TerminalWarehouseModel> terminals = const [];
    try {
      terminals = await _warehouseRepository.fetchTerminals();
    } on Object {
      terminals = await _warehouseRepository.cachedTerminals();
    }

    TerminalWarehouseModel? selected;
    for (final terminal in terminals) {
      if (terminal.isActive && terminal.deviceBound) {
        selected = terminal;
        break;
      }
    }
    selected ??= terminals
        .where((terminal) => terminal.isActive && terminal.isDefault)
        .cast<TerminalWarehouseModel?>()
        .firstWhere((terminal) => terminal != null, orElse: () => null);
    selected ??= terminals
        .where((terminal) => terminal.isActive)
        .cast<TerminalWarehouseModel?>()
        .firstWhere((terminal) => terminal != null, orElse: () => null);

    return _SaleSyncIdentity(
      deviceFingerprint: deviceId,
      terminalId: selected?.id,
      warehouseId: selected?.defaultWarehouseId,
    );
  }

  Map<String, dynamic> _conflictPayloadFromResponse(dynamic data) {
    if (data is Map) {
      return Map<String, dynamic>.from(data);
    }
    return {
      'code': 'OFFLINE_SYNC_CONFLICT',
      'message':
          'Esta venta no pudo sincronizarse porque el stock cambió mientras el dispositivo estaba sin conexión.',
    };
  }

  SaleModel _optimisticSale({
    required String id,
    required String userId,
    required String userName,
    String? customerId,
    String? customerName,
    String? customerPhone,
    String? note,
    required String paymentMethod,
    required double paymentCashAmount,
    required double paymentTransferAmount,
    required double creditAmount,
    required List<SaleDraftItem> items,
    double? totalSold,
  }) {
    final saleItems = items
        .asMap()
        .entries
        .map((entry) {
          final item = entry.value;
          return SaleItemModel(
            id: '${id}_item_${entry.key}',
            productId: item.productId,
            productNameSnapshot: item.name,
            productImageSnapshot: item.imageUrl,
            qty: item.qty,
            priceSoldUnit: item.priceSoldUnit,
            costUnitSnapshot: item.costUnitSnapshot,
            subtotalSold: item.subtotalSold,
            subtotalCost: item.subtotalCost,
            profit: item.profit,
            category: item.product?.categoriaLabel,
          );
        })
        .toList(growable: false);
    final resolvedTotal =
        totalSold ??
        saleItems.fold<double>(0, (sum, item) => sum + item.subtotalSold);
    final totalCost = saleItems.fold<double>(
      0,
      (sum, item) => sum + item.subtotalCost,
    );
    final totalProfit = resolvedTotal - totalCost;
    final paid = paymentCashAmount + paymentTransferAmount;
    final balance = paymentMethod == 'credit'
        ? (resolvedTotal - paid).clamp(0, double.infinity).toDouble()
        : 0.0;

    return SaleModel(
      id: id,
      userId: userId,
      userName: userName,
      customerId: customerId,
      customerName: customerName,
      customerPhone: customerPhone,
      saleDate: DateTime.now(),
      note: note,
      totalSold: resolvedTotal,
      totalCost: totalCost,
      totalProfit: totalProfit,
      commissionAmount: totalProfit > 0 ? totalProfit * 0.1 : 0,
      paymentMethod: paymentMethod,
      paymentCashAmount: paymentCashAmount,
      paymentTransferAmount: paymentTransferAmount,
      creditAmount: creditAmount,
      creditPaidAmount: paid,
      creditBalance: balance,
      creditStatus: paymentMethod == 'credit'
          ? (balance > 0 ? 'open' : 'paid')
          : 'none',
      isDeleted: false,
      deletedAt: null,
      items: saleItems,
    );
  }

  String _displayNameFromUserSnapshot(dynamic user) {
    final name = (user?.nombreCompleto ?? '').toString().trim();
    if (name.isNotEmpty) return name;
    final email = (user?.email ?? '').toString().trim();
    if (email.isNotEmpty) return email;
    return 'No disponible';
  }

  Future<List<ProductModel>> fetchProducts({bool forceRefresh = false}) async {
    try {
      final res = await _dio.get(
        ApiRoutes.catalogProducts,
        queryParameters: null,
        options: Options(
          extra: const {'skipLoader': true},
          headers: {
            'Cache-Control': 'no-cache, no-store, must-revalidate',
            'Pragma': 'no-cache',
            'Expires': '0',
          },
        ),
      );
      final rows = _extractRows(res.data);
      final parsed = rows
          .whereType<Map>()
          .map((row) => ProductModel.fromJson(row.cast<String, dynamic>()))
          .toList();

      final raw = res.data;
      final rawLooksInvalid = raw != null && raw is! List && raw is! Map;
      if (rawLooksInvalid) {
        throw ApiException('Respuesta inválida al cargar productos');
      }

      return parsed;
    } on DioException catch (e) {
      throw ApiException(
        _extractMessage(
          e.response?.data,
          'No se pudieron cargar los productos',
        ),
        e.response?.statusCode,
      );
    }
  }

  Future<List<ClienteModel>> searchClients(String search) async {
    try {
      const pageSize = 100;
      final normalizedSearch = search.trim();
      final clients = <ClienteModel>[];
      var page = 1;
      var totalPages = 1;

      while (page <= totalPages) {
        final res = await _dio.get(
          ApiRoutes.clients,
          queryParameters: {
            if (normalizedSearch.isNotEmpty) 'search': normalizedSearch,
            'page': page,
            'pageSize': pageSize,
          },
          options: Options(extra: const {'skipLoader': true}),
        );

        final raw = res.data;
        final rows = _extractRows(raw);
        clients.addAll(
          rows.whereType<Map>().map(
            (row) => ClienteModel.fromJson(row.cast<String, dynamic>()),
          ),
        );

        totalPages = raw is Map && raw['totalPages'] is num
            ? (raw['totalPages'] as num).toInt()
            : 1;
        if (rows.isEmpty || totalPages <= page) {
          break;
        }
        page += 1;
      }

      return clients;
    } on DioException catch (e) {
      throw ApiException(
        _extractMessage(e.response?.data, 'No se pudieron cargar clientes'),
        e.response?.statusCode,
      );
    }
  }

  Future<ClienteModel> createQuickClient({
    required String nombre,
    required String telefono,
    String? taxId,
    String? businessName,
  }) async {
    try {
      final res = await _dio.post(
        ApiRoutes.clients,
        data: {
          'nombre': nombre.trim(),
          'telefono': telefono.trim(),
          if ((taxId ?? '').trim().isNotEmpty) 'taxId': taxId!.trim(),
          if ((businessName ?? '').trim().isNotEmpty)
            'businessName': businessName!.trim(),
          if ((taxId ?? '').trim().isNotEmpty) 'taxIdType': 'RNC',
        },
      );
      return ClienteModel.fromJson((res.data as Map).cast<String, dynamic>());
    } on DioException catch (e) {
      throw ApiException(
        _extractMessage(e.response?.data, 'No se pudo crear el cliente'),
        e.response?.statusCode,
      );
    }
  }

  /// Actualiza/completa los datos fiscales de un Cliente existente
  /// (PATCH /clients/:id). Respetado el ownership por empresa en el backend.
  Future<ClienteModel> updateClientFiscal({
    required String id,
    String? taxId,
    String? nombre,
  }) async {
    try {
      final res = await _dio.patch(
        ApiRoutes.clientDetail(id),
        data: {
          if ((taxId ?? '').trim().isNotEmpty) 'taxId': taxId!.trim(),
          if ((nombre ?? '').trim().isNotEmpty) 'nombre': nombre!.trim(),
        },
      );
      return ClienteModel.fromJson((res.data as Map).cast<String, dynamic>());
    } on DioException catch (e) {
      throw ApiException(
        _extractMessage(e.response?.data, 'No se pudo actualizar el cliente'),
        e.response?.statusCode,
      );
    }
  }

  String _dateOnly(DateTime date) {
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '${date.year}-$month-$day';
  }

  String _salesListCacheKey({
    required DateTime from,
    required DateTime to,
    String? userId,
    String? customerId,
    required bool includeDeleted,
    int? limit,
  }) {
    final user = _cacheKeyPart(userId);
    final customer = _cacheKeyPart(customerId);
    final capped = limit != null && limit > 0 ? 'l$limit' : 'all';
    return 'sales.list.v1.${_dateOnly(from)}.${_dateOnly(to)}.$user.$customer.$includeDeleted.$capped';
  }

  String _salesSummaryCacheKey({
    required DateTime from,
    required DateTime to,
    String? userId,
    String? customerId,
  }) {
    final user = _cacheKeyPart(userId);
    final customer = _cacheKeyPart(customerId);
    return 'sales.summary.v1.${_dateOnly(from)}.${_dateOnly(to)}.$user.$customer';
  }

  String _salesInvoicesCacheKey({
    required DateTime from,
    required DateTime to,
    String? customerId,
    required bool includeDeleted,
    int? limit,
  }) {
    final customer = _cacheKeyPart(customerId);
    final capped = limit != null && limit > 0 ? 'l$limit' : 'all';
    return 'sales.invoices.v1.${_dateOnly(from)}.${_dateOnly(to)}.$customer.$includeDeleted.$capped';
  }

  /// Escribe en caché sin bloquear/fallar la respuesta de red: un problema
  /// local (p. ej. base SQLite ocupada) NUNCA debe dejar colgada la carga
  /// de ventas recientes.
  Future<void> _tryWriteCache(String key, Map<String, dynamic> value) async {
    try {
      await _cache.writeMap(key, value);
    } catch (error, stackTrace) {
      TraceLog.log(
        'ventas_cache',
        'write fallo key=$key (no bloquea la respuesta)',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  /// Ejecuta GET /sales o /sales/invoices con `limit` opcional, escribe la
  /// caché y mapea a SaleModel. Lanza [DioException] hacia arriba.
  Future<List<SaleModel>> _requestSalesRows({
    required String path,
    required DateTime from,
    required DateTime to,
    String? userId,
    String? customerId,
    required bool includeDeleted,
    int? limit,
    required String cacheKey,
  }) async {
    final requestedLimit = (limit != null && limit > 0) ? limit : null;
    final query = <String, dynamic>{
      'from': _dateOnly(from),
      'to': _dateOnly(to),
      if ((userId ?? '').trim().isNotEmpty) 'userId': userId!.trim(),
      if ((customerId ?? '').trim().isNotEmpty)
        'customerId': customerId!.trim(),
      if (includeDeleted) 'includeDeleted': 'true',
      if (requestedLimit != null) 'limit': requestedLimit,
    };
    TraceLog.log('RECENT_SALES', 'request GET $path params=$query');
    final res = await _dio.get(
      path,
      queryParameters: query,
      options: Options(extra: const {'skipLoader': true}),
    );
    final rows = res.data is List ? (res.data as List) : const [];
    await _tryWriteCache(cacheKey, {'items': rows});
    final mapped = rows
        .whereType<Map>()
        .map((e) => SaleModel.fromJson(e.cast<String, dynamic>()))
        .toList(growable: false);
    TraceLog.log(
      'RECENT_SALES',
      'response GET $path status=${res.statusCode} items=${mapped.length}',
    );
    return mapped;
  }

  /// Detecta SOLO el rechazo específico de la validación NestJS por
  /// whitelist/forbidNonWhitelisted de la propiedad `limit` (version skew:
  /// backend anterior sin el parámetro). NO cubre 401/403/500/timeouts/DB.
  bool _isLimitPropertyRejected(DioException error) {
    if (error.response?.statusCode != 400) return false;
    final data = error.response?.data;
    final messages = <String>[];
    if (data is Map) {
      final msg = data['message'];
      if (msg is String) messages.add(msg);
      if (msg is List) messages.addAll(msg.whereType<String>());
    } else if (data is String) {
      messages.add(data);
    }
    final joined = messages.join(' ').toLowerCase();
    return joined.contains('limit should not exist') ||
        joined.contains('property limit') ||
        joined.contains('unknown property limit') ||
        joined.contains('unknown argument limit') ||
        joined.contains('unknown field limit');
  }

  void _logRecentSalesError(
    String label,
    DioException error,
    StackTrace stackTrace,
  ) {
    var bodyPreview = 'n/a';
    try {
      final raw = error.response?.data;
      if (raw != null) {
        bodyPreview = raw is String ? raw : jsonEncode(raw);
        if (bodyPreview.length > 600) {
          bodyPreview = '${bodyPreview.substring(0, 600)}...';
        }
      }
    } catch (_) {
      bodyPreview = 'n/a';
    }
    TraceLog.log(
      'RECENT_SALES',
      'ERROR $label status=${error.response?.statusCode} '
          'type=${error.type} message=${error.message ?? ''} body=$bodyPreview',
      error: error,
      stackTrace: stackTrace,
    );
  }

  String _cacheKeyPart(String? value) {
    final normalized = (value ?? '').trim();
    return normalized.isEmpty ? 'all' : normalized;
  }

  double _sumItems(List<SaleDraftItem> items) {
    return items.fold<double>(0, (sum, item) => sum + item.subtotalSold);
  }
}

double? _nullableDouble(dynamic value) {
  if (value == null) return null;
  if (value is num) return value.toDouble();
  return double.tryParse(value.toString());
}

class _SaleSyncIdentity {
  const _SaleSyncIdentity({
    this.deviceFingerprint,
    this.terminalId,
    this.warehouseId,
  });

  final String? deviceFingerprint;
  final String? terminalId;
  final String? warehouseId;
}
