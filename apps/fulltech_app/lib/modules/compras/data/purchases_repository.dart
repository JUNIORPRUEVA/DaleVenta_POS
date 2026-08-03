import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http_parser/http_parser.dart';

import '../../../core/api/api_routes.dart';
import '../../../core/auth/auth_repository.dart';
import '../../../core/cache/local_json_cache.dart';
import '../../../core/errors/api_exception.dart';
import '../purchase_models.dart';

final purchasesRepositoryProvider = Provider<PurchasesRepository>((ref) {
  return PurchasesRepository(ref.watch(dioProvider));
});

class PurchasesRepository {
  PurchasesRepository(this._dio);
  final Dio _dio;
  final LocalJsonCache _cache = LocalJsonCache();

  static const _suppliersCacheKey = 'purchases.suppliers.v1';
  static const _ordersCacheKey = 'purchases.orders.v1';
  static const _recommendationsCacheKey = 'purchases.recommendations.v1';
  static const _invoicesCacheKey = 'purchases.invoices.v1';

  List<dynamic> _rows(dynamic data) {
    if (data is List) return data;
    if (data is Map) {
      for (final key in ['items', 'data', 'rows']) {
        final value = data[key];
        if (value is List) return value;
      }
    }
    return const [];
  }

  Future<List<T>> _readCachedList<T>(
    String key,
    T Function(Map<String, dynamic>) decode,
  ) async {
    final data = await _cache.readMap(key);
    return _rows(data)
        .whereType<Map>()
        .map((row) => decode(Map<String, dynamic>.from(row)))
        .toList();
  }

  Future<void> _writeCachedRows(String key, List<dynamic> rows) async {
    try {
      await _cache.writeMap(key, {'items': rows});
    } catch (_) {
      // Cache is an acceleration layer; failed writes must never block compras.
    }
  }

  String _message(dynamic data, String fallback) {
    if (data is Map && data['message'] is String) {
      return data['message'] as String;
    }
    return fallback;
  }

  Future<List<SupplierModel>> listSuppliers({String? query}) async {
    try {
      final res = await _dio.get(
        ApiRoutes.purchaseSuppliers,
        queryParameters: {'q': query},
      );
      final rows = _rows(res.data);
      if ((query ?? '').trim().isEmpty) {
        await _writeCachedRows(_suppliersCacheKey, rows);
      }
      return rows
          .whereType<Map>()
          .map((row) => SupplierModel.fromJson(Map<String, dynamic>.from(row)))
          .toList();
    } on DioException catch (e) {
      throw ApiException(
        _message(e.response?.data, 'No se pudieron cargar suplidores'),
        e.response?.statusCode,
      );
    }
  }

  Future<List<SupplierModel>> cachedSuppliers() =>
      _readCachedList(_suppliersCacheKey, SupplierModel.fromJson);

  Future<SupplierModel> saveSupplier(SupplierModel supplier) async {
    try {
      final res = supplier.id.isEmpty
          ? await _dio.post(
              ApiRoutes.purchaseSuppliers,
              data: supplier.toPayload(),
            )
          : await _dio.patch(
              ApiRoutes.purchaseSupplier(supplier.id),
              data: supplier.toPayload(),
            );
      return SupplierModel.fromJson(Map<String, dynamic>.from(res.data as Map));
    } on DioException catch (e) {
      throw ApiException(
        _message(e.response?.data, 'No se pudo guardar suplidor'),
        e.response?.statusCode,
      );
    }
  }

  Future<void> deactivateSupplier(String id) async {
    try {
      await _dio.delete(ApiRoutes.purchaseSupplier(id));
    } on DioException catch (e) {
      throw ApiException(
        _message(e.response?.data, 'No se pudo desactivar suplidor'),
        e.response?.statusCode,
      );
    }
  }

  Future<List<PurchaseOrderModel>> listOrders({
    String? query,
    String? status,
    String? supplierId,
  }) async {
    try {
      final res = await _dio.get(
        ApiRoutes.purchaseOrders,
        queryParameters: {
          'q': query,
          'status': status,
          'supplierId': supplierId,
        }..removeWhere((_, value) => value == null || '$value'.trim().isEmpty),
      );
      final rows = _rows(res.data);
      if ([
        query,
        status,
        supplierId,
      ].every((value) => value == null || value.toString().trim().isEmpty)) {
        await _writeCachedRows(_ordersCacheKey, rows);
      }
      return rows
          .whereType<Map>()
          .map(
            (row) =>
                PurchaseOrderModel.fromJson(Map<String, dynamic>.from(row)),
          )
          .toList();
    } on DioException catch (e) {
      throw ApiException(
        _message(e.response?.data, 'No se pudieron cargar compras'),
        e.response?.statusCode,
      );
    }
  }

  Future<List<PurchaseOrderModel>> cachedOrders() =>
      _readCachedList(_ordersCacheKey, PurchaseOrderModel.fromJson);

  Future<PurchaseOrderModel> createOrder({
    required String? supplierId,
    required List<PurchaseDraftItem> items,
    required double discount,
    required double shippingCost,
    required double additionalCost,
    required double tax,
    String? notes,
    String? supplierInstructions,
    String? expectedDeliveryDate,
  }) async {
    try {
      final res = await _dio.post(
        ApiRoutes.purchaseOrders,
        data: {
          'supplierId': supplierId,
          'discount': discount,
          'shippingCost': shippingCost,
          'additionalCost': additionalCost,
          'tax': tax,
          'notes': notes,
          'supplierInstructions': supplierInstructions,
          'expectedDeliveryDate': expectedDeliveryDate,
          'items': items.map((item) => item.toPayload()).toList(),
        }..removeWhere((_, value) => value == null),
      );
      return PurchaseOrderModel.fromJson(
        Map<String, dynamic>.from(res.data as Map),
      );
    } on DioException catch (e) {
      throw ApiException(
        _message(e.response?.data, 'No se pudo guardar la orden'),
        e.response?.statusCode,
      );
    }
  }

  Future<PurchaseOrderModel> approve(String id) =>
      _postOrder(ApiRoutes.purchaseOrderApprove(id), 'No se pudo aprobar');
  Future<PurchaseOrderModel> markSent(String id) =>
      _postOrder(ApiRoutes.purchaseOrderSend(id), 'No se pudo marcar enviada');
  Future<PurchaseOrderModel> cancel(String id) =>
      _postOrder(ApiRoutes.purchaseOrderCancel(id), 'No se pudo cancelar');
  Future<PurchaseOrderModel> duplicate(String id) =>
      _postOrder(ApiRoutes.purchaseOrderDuplicate(id), 'No se pudo duplicar');

  Future<void> deleteOrder(String id) async {
    try {
      await _dio.delete(ApiRoutes.purchaseOrder(id));
    } on DioException catch (e) {
      throw ApiException(
        _message(e.response?.data, 'No se pudo eliminar la orden'),
        e.response?.statusCode,
      );
    }
  }

  Future<PurchaseOrderModel> _postOrder(String path, String fallback) async {
    try {
      final res = await _dio.post(path);
      return PurchaseOrderModel.fromJson(
        Map<String, dynamic>.from(res.data as Map),
      );
    } on DioException catch (e) {
      throw ApiException(
        _message(e.response?.data, fallback),
        e.response?.statusCode,
      );
    }
  }

  Future<PurchaseOrderModel> receive({
    required PurchaseOrderModel order,
    required bool updateInventory,
  }) async {
    try {
      final res = await _dio.post(
        ApiRoutes.purchaseOrderReceive(order.id),
        data: {
          'updateInventory': updateInventory,
          'items': [
            for (final item in order.items.where(
              (item) => item.pendingQuantity > 0,
            ))
              {
                'purchaseOrderItemId': item.id,
                'quantityReceived': item.pendingQuantity,
                'unitCost': item.unitCost,
                'condition': 'OK',
              },
          ],
        },
      );
      final data = Map<String, dynamic>.from(res.data as Map);
      return PurchaseOrderModel.fromJson(
        Map<String, dynamic>.from(data['order'] as Map),
      );
    } on DioException catch (e) {
      throw ApiException(
        _message(e.response?.data, 'No se pudo registrar recepción'),
        e.response?.statusCode,
      );
    }
  }

  Future<List<PurchaseRecommendationModel>> recommendations() async {
    try {
      final res = await _dio.get(ApiRoutes.purchaseRecommendations);
      final rows = _rows(res.data);
      await _writeCachedRows(_recommendationsCacheKey, rows);
      return rows
          .whereType<Map>()
          .map(
            (row) => PurchaseRecommendationModel.fromJson(
              Map<String, dynamic>.from(row),
            ),
          )
          .toList();
    } on DioException catch (e) {
      throw ApiException(
        _message(e.response?.data, 'No se pudieron cargar recomendaciones'),
        e.response?.statusCode,
      );
    }
  }

  Future<List<PurchaseRecommendationModel>> cachedRecommendations() =>
      _readCachedList(
        _recommendationsCacheKey,
        PurchaseRecommendationModel.fromJson,
      );

  Future<String> createPdfShareLink({
    required String purchaseOrderId,
    required List<int> pdfBytes,
    String? fileName,
  }) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        ApiRoutes.purchasePdfShareLink,
        data: {
          'purchaseOrderId': purchaseOrderId.trim(),
          'pdfBase64': base64Encode(pdfBytes),
          if (fileName != null && fileName.trim().isNotEmpty)
            'fileName': fileName.trim(),
        },
      );
      final pdfUrl = (res.data?['pdfUrl'] ?? '').toString().trim();
      if (pdfUrl.isEmpty) {
        throw ApiException('No se pudo generar el enlace del PDF');
      }
      return pdfUrl;
    } on DioException catch (e) {
      throw ApiException(
        _message(e.response?.data, 'No se pudo generar el enlace del PDF'),
        e.response?.statusCode,
      );
    }
  }

  Future<List<PurchaseInvoiceModel>> listInvoices({
    String? query,
    String? supplierId,
    String? purchaseOrderId,
  }) async {
    try {
      final res = await _dio.get(
        ApiRoutes.purchaseInvoices,
        queryParameters: {
          'q': query,
          'supplierId': supplierId,
          'purchaseOrderId': purchaseOrderId,
        }..removeWhere((_, value) => value == null || '$value'.trim().isEmpty),
      );
      final rows = _rows(res.data);
      if ([
        query,
        supplierId,
        purchaseOrderId,
      ].every((value) => value == null || value.toString().trim().isEmpty)) {
        await _writeCachedRows(_invoicesCacheKey, rows);
      }
      return rows
          .whereType<Map>()
          .map(
            (row) =>
                PurchaseInvoiceModel.fromJson(Map<String, dynamic>.from(row)),
          )
          .toList();
    } on DioException catch (e) {
      throw ApiException(
        _message(e.response?.data, 'No se pudieron cargar facturas de compra'),
        e.response?.statusCode,
      );
    }
  }

  Future<List<PurchaseInvoiceModel>> cachedInvoices() =>
      _readCachedList(_invoicesCacheKey, PurchaseInvoiceModel.fromJson);

  Future<PurchaseInvoiceModel> uploadInvoice({
    required PlatformFile file,
    required String supplierId,
    String? purchaseOrderId,
    String? invoiceNumber,
    String? invoiceDate,
    double? amount,
    String? notes,
  }) async {
    try {
      final bytes = file.bytes;
      if (bytes == null || bytes.isEmpty) {
        throw ApiException('No se pudo leer el archivo seleccionado');
      }
      final form = FormData.fromMap({
        'supplierId': supplierId,
        if ((purchaseOrderId ?? '').trim().isNotEmpty)
          'purchaseOrderId': purchaseOrderId!.trim(),
        if ((invoiceNumber ?? '').trim().isNotEmpty)
          'invoiceNumber': invoiceNumber!.trim(),
        if ((invoiceDate ?? '').trim().isNotEmpty)
          'invoiceDate': invoiceDate!.trim(),
        if (amount != null) 'amount': amount,
        if ((notes ?? '').trim().isNotEmpty) 'notes': notes!.trim(),
        'file': MultipartFile.fromBytes(
          bytes,
          filename: file.name,
          contentType: MediaType.parse(
            _contentTypeForExtension(file.extension),
          ),
        ),
      });
      final res = await _dio.post(ApiRoutes.purchaseInvoices, data: form);
      return PurchaseInvoiceModel.fromJson(
        Map<String, dynamic>.from(res.data as Map),
      );
    } on DioException catch (e) {
      throw ApiException(
        _message(e.response?.data, 'No se pudo subir la factura de compra'),
        e.response?.statusCode,
      );
    }
  }

  Future<void> deleteInvoice(String id) async {
    try {
      await _dio.delete(ApiRoutes.purchaseInvoice(id));
    } on DioException catch (e) {
      throw ApiException(
        _message(e.response?.data, 'No se pudo eliminar la factura'),
        e.response?.statusCode,
      );
    }
  }

  String _contentTypeForExtension(String? extension) {
    switch ((extension ?? '').toLowerCase()) {
      case 'png':
        return 'image/png';
      case 'webp':
        return 'image/webp';
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'doc':
        return 'application/msword';
      case 'docx':
        return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
      case 'xls':
        return 'application/vnd.ms-excel';
      case 'xlsx':
        return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
      case 'pdf':
      default:
        return 'application/pdf';
    }
  }
}
