import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_routes.dart';
import '../../../core/auth/auth_repository.dart';
import '../../../core/errors/api_exception.dart';
import '../../../core/models/product_model.dart';
import '../../clientes/cliente_model.dart';
import '../sales_models.dart';

final ventasRepositoryProvider = Provider<VentasRepository>((ref) {
  return VentasRepository(ref.watch(dioProvider));
});

class VentasRepository {
  final Dio _dio;

  VentasRepository(this._dio);

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
  }) async {
    try {
      final res = await _dio.get(
        ApiRoutes.sales,
        queryParameters: {
          'from': _dateOnly(from),
          'to': _dateOnly(to),
          if ((userId ?? '').trim().isNotEmpty) 'userId': userId!.trim(),
          if ((customerId ?? '').trim().isNotEmpty)
            'customerId': customerId!.trim(),
          if (includeDeleted) 'includeDeleted': 'true',
        },
        options: Options(extra: const {'skipLoader': true}),
      );

      final rows = res.data is List ? (res.data as List) : const [];
      return rows
          .whereType<Map>()
          .map((e) => SaleModel.fromJson(e.cast<String, dynamic>()))
          .toList();
    } on DioException catch (e) {
      throw ApiException(
        _extractMessage(e.response?.data, 'No se pudieron cargar las ventas'),
        e.response?.statusCode,
      );
    }
  }

  Future<List<SaleModel>> listInvoices({
    required DateTime from,
    required DateTime to,
    String? customerId,
    bool includeDeleted = true,
  }) async {
    try {
      final res = await _dio.get(
        ApiRoutes.salesInvoices,
        queryParameters: {
          'from': _dateOnly(from),
          'to': _dateOnly(to),
          if ((customerId ?? '').trim().isNotEmpty)
            'customerId': customerId!.trim(),
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
        _extractMessage(e.response?.data, 'No se pudieron cargar las facturas'),
        e.response?.statusCode,
      );
    }
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
      return SalesSummaryModel.fromJson(
        (res.data as Map).cast<String, dynamic>(),
      );
    } on DioException catch (e) {
      throw ApiException(
        _extractMessage(e.response?.data, 'No se pudo cargar el resumen'),
        e.response?.statusCode,
      );
    }
  }

  Future<Map<String, dynamic>> reportsSalesOverview({
    required DateTime from,
    required DateTime to,
  }) async {
    try {
      final res = await _dio.get(
        ApiRoutes.reportsSalesOverview,
        queryParameters: {
          'from': _dateOnly(from),
          'to': _dateOnly(to),
        },
        options: Options(extra: const {'skipLoader': true}),
      );
      return ((res.data as Map?) ?? const <String, dynamic>{})
          .cast<String, dynamic>();
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
    required String customerId,
    String? note,
    String? paymentMethod,
    double? paymentCashAmount,
    double? paymentTransferAmount,
    required List<SaleDraftItem> items,
  }) async {
    if (items.isEmpty) {
      throw ApiException('Agrega al menos un item');
    }
    if (customerId.trim().isEmpty) {
      throw ApiException('Debes seleccionar un cliente');
    }

    try {
      final res = await _dio.post(
        ApiRoutes.sales,
        data: {
          'customerId': customerId,
          if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
          if ((paymentMethod ?? '').trim().isNotEmpty)
            'paymentMethod': paymentMethod!.trim(),
          if (paymentCashAmount != null) 'paymentCashAmount': paymentCashAmount,
          if (paymentTransferAmount != null)
            'paymentTransferAmount': paymentTransferAmount,
          'items': items.map((item) => item.toPayload()).toList(),
        },
      );
      if (res.data is Map) {
        return SaleModel.fromJson((res.data as Map).cast<String, dynamic>());
      }
      return null;
    } on DioException catch (e) {
      throw ApiException(
        _extractMessage(e.response?.data, 'No se pudo guardar la venta'),
        e.response?.statusCode,
      );
    }
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
  }) async {
    try {
      final res = await _dio.post(
        ApiRoutes.clients,
        data: {'nombre': nombre.trim(), 'telefono': telefono.trim()},
      );
      return ClienteModel.fromJson((res.data as Map).cast<String, dynamic>());
    } on DioException catch (e) {
      throw ApiException(
        _extractMessage(e.response?.data, 'No se pudo crear el cliente'),
        e.response?.statusCode,
      );
    }
  }

  String _dateOnly(DateTime date) {
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '${date.year}-$month-$day';
  }
}
