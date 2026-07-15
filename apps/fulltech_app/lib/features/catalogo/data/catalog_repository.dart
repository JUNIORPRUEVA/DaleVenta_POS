import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_routes.dart';
import '../../../core/auth/auth_repository.dart';
import '../../../core/errors/api_exception.dart';
import '../../../core/models/product_model.dart';
import '../../../core/utils/file_utils.dart';

final catalogRepositoryProvider = Provider<CatalogRepository>((ref) {
  return CatalogRepository(ref.watch(dioProvider));
});

class CatalogRepository {
  final Dio _dio;
  CatalogRepository(this._dio);

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

  String _formatDioError(DioException e, String fallback) {
    final status = e.response?.statusCode;
    final endpoint = e.requestOptions.path;
    final uri = e.requestOptions.uri.toString();
    final baseUrl = _dio.options.baseUrl;
    final rawMessage = _extractMessage(e.response?.data, fallback);

    if (status == null) {
      return '[NETWORK] $rawMessage\nEndpoint: $endpoint\nURI: $uri\nBaseURL: $baseUrl\nDetalle: ${e.message ?? 'Sin respuesta del servidor'}';
    }

    return '[HTTP $status] $rawMessage\nEndpoint: $endpoint\nURI: $uri';
  }

  Future<List<ProductModel>> fetchProducts({
    bool forceRefresh = false,
    bool silent = false,
  }) async {
    try {
      final res = await _dio.get(
        ApiRoutes.catalogProducts,
        queryParameters: null,
        options: Options(
          headers: {
            'Cache-Control': 'no-cache, no-store, must-revalidate',
            'Pragma': 'no-cache',
            'Expires': '0',
          },
          extra: {'silent': silent},
        ),
      );
      final rows = _extractRows(res.data);
      return rows
          .whereType<Map>()
          .map((row) => ProductModel.fromJson(Map<String, dynamic>.from(row)))
          .toList();
    } on DioException catch (e) {
      throw ApiException(
        _formatDioError(e, 'No se pudieron cargar los productos'),
        e.response?.statusCode,
      );
    } catch (e) {
      throw ApiException('No se pudieron cargar los productos: $e');
    }
  }

  Future<String> uploadImage({
    required List<int> bytes,
    required String filename,
  }) async {
    try {
      final formData = FormData.fromMap({
        'file': MultipartFile.fromBytes(
          bytes,
          filename: filename,
          contentType: detectImageMime(filename),
        ),
      });
      final res = await _dio.post(ApiRoutes.productsUpload, data: formData);
      final data = res.data;
      if (data is Map && data['url'] is String) {
        return data['url'] as String;
      }
      if (data is Map && data['path'] is String) {
        return data['path'] as String;
      }
      throw ApiException('No se recibió la ruta de la imagen');
    } on DioException catch (e) {
      throw ApiException(
        _extractMessage(e.response?.data, 'No se pudo subir la imagen'),
        e.response?.statusCode,
      );
    }
  }

  Future<ProductModel> createProduct({
    required String nombre,
    required double precio,
    required double costo,
    required double stock,
    String? fotoUrl,
    required String categoria,
  }) async {
    try {
      final res = await _dio.post(
        ApiRoutes.products,
        data: {
          'nombre': nombre,
          'precio': precio,
          'costo': costo,
          'stock': stock,
          if ((fotoUrl ?? '').trim().isNotEmpty) 'fotoUrl': fotoUrl!.trim(),
          'categoria': categoria,
        },
      );
      return ProductModel.fromJson((res.data as Map).cast<String, dynamic>());
    } on DioException catch (e) {
      throw ApiException(
        _extractMessage(e.response?.data, 'No se pudo crear el producto'),
        e.response?.statusCode,
      );
    }
  }

  Future<ProductModel> updateProduct({
    required String id,
    required String nombre,
    required double precio,
    required double costo,
    required double stock,
    String? fotoUrl,
    String? categoria,
  }) async {
    try {
      final res = await _dio.patch(
        ApiRoutes.updateProduct(id),
        data: {
          'nombre': nombre,
          'precio': precio,
          'costo': costo,
          'stock': stock,
          'fotoUrl': fotoUrl,
          'categoria': categoria,
        },
      );
      return ProductModel.fromJson((res.data as Map).cast<String, dynamic>());
    } on DioException catch (e) {
      throw ApiException(
        _extractMessage(e.response?.data, 'No se pudo actualizar el producto'),
        e.response?.statusCode,
      );
    }
  }

  Future<void> deleteProduct(String id) async {
    try {
      await _dio.delete(ApiRoutes.deleteProduct(id));
    } on DioException catch (e) {
      throw ApiException(
        _extractMessage(e.response?.data, 'No se pudo eliminar el producto'),
        e.response?.statusCode,
      );
    }
  }

  Future<Map<String, dynamic>> purgeAllDebug() async {
    try {
      final res = await _dio.delete(ApiRoutes.productsDebugPurge);
      return Map<String, dynamic>.from(
        (res.data as Map?) ?? const <String, dynamic>{},
      );
    } on DioException catch (e) {
      throw ApiException(
        _extractMessage(
          e.response?.data,
          'No se pudieron limpiar los productos',
        ),
        e.response?.statusCode,
      );
    }
  }
}
