import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_routes.dart';
import '../../core/auth/auth_repository.dart';
import '../../core/errors/api_exception.dart';
import '../../core/utils/file_utils.dart';
import 'website_product_model.dart';

final websiteRepositoryProvider = Provider<WebsiteRepository>((ref) {
  return WebsiteRepository(ref.watch(dioProvider));
});

class WebsiteRepository {
  WebsiteRepository(this._dio);

  final Dio _dio;

  String _message(DioException e, String fallback) {
    final data = e.response?.data;
    if (data is Map && data['message'] is String) {
      return data['message'] as String;
    }
    return fallback;
  }

  Future<List<WebsiteProductModel>> fetchProducts() async {
    try {
      final response = await _dio.get(ApiRoutes.websiteProducts);
      final data = response.data;
      final rows = data is Map && data['items'] is List
          ? data['items'] as List
          : const [];
      return rows
          .whereType<Map>()
          .map(
            (row) =>
                WebsiteProductModel.fromJson(Map<String, dynamic>.from(row)),
          )
          .toList();
    } on DioException catch (e) {
      throw ApiException(
        _message(e, 'No se pudo cargar el sitio web'),
        e.response?.statusCode,
      );
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
      final response = await _dio.post(ApiRoutes.websiteUpload, data: formData);
      final data = response.data;
      if (data is Map && data['url'] is String) return data['url'] as String;
      if (data is Map && data['path'] is String) return data['path'] as String;
      throw ApiException('No se recibió la URL de la imagen');
    } on DioException catch (e) {
      throw ApiException(
        _message(e, 'No se pudo subir la imagen'),
        e.response?.statusCode,
      );
    }
  }

  Future<WebsiteProductModel> updateProduct({
    required String productId,
    required String title,
    required String description,
    required String category,
    required String? imageUrl,
    required bool visible,
    required bool featured,
    required int sortOrder,
    String? seoTitle,
    String? seoDescription,
  }) async {
    try {
      final response = await _dio.patch(
        ApiRoutes.websiteProduct(productId),
        data: {
          'title': title,
          'description': description,
          'category': category,
          'imageUrl': imageUrl,
          'visible': visible,
          'featured': featured,
          'sortOrder': sortOrder,
          'seoTitle': seoTitle,
          'seoDescription': seoDescription,
        },
      );
      return WebsiteProductModel.fromJson(
        Map<String, dynamic>.from(response.data as Map),
      );
    } on DioException catch (e) {
      throw ApiException(
        _message(e, 'No se pudo guardar el producto web'),
        e.response?.statusCode,
      );
    }
  }
}
