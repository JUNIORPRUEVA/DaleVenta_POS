import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_routes.dart';
import '../../../core/auth/auth_repository.dart';
import '../../../core/errors/api_exception.dart';
import '../purchase_models.dart';

final purchasesRepositoryProvider = Provider<PurchasesRepository>((ref) {
  return PurchasesRepository(ref.watch(dioProvider));
});

class PurchasesRepository {
  PurchasesRepository(this._dio);
  final Dio _dio;

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
      return _rows(res.data)
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
      return _rows(res.data)
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
      return _rows(res.data)
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
}
