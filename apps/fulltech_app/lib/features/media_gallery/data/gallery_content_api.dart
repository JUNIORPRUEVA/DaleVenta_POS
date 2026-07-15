// Gallery Content API Service
import 'package:dio/dio.dart';

import '../models/gallery_content_model.dart';

class GalleryContentApi {
  const GalleryContentApi(this._dio);

  final Dio _dio;

  static const _baseUrl = '/gallery/content';

  // ─── Load Content ───────────────────────────────────────────────────────

  Future<List<GalleryContentItem>> loadAllContent({
    String? filterId,
    String? searchQuery,
    int page = 1,
    int limit = 50,
  }) async {
    try {
      final params = <String, dynamic>{'page': page, 'limit': limit};
      if (filterId != null && filterId.isNotEmpty) {
        params['filter'] = filterId;
      }
      if (searchQuery != null && searchQuery.isNotEmpty) {
        params['search'] = searchQuery;
      }

      final response = await _dio.get<List>(
        '$_baseUrl',
        queryParameters: params,
      );

      final items = (response.data ?? [])
          .map(
            (item) => GalleryContentItem.fromJson(item as Map<String, dynamic>),
          )
          .toList();
      return items;
    } catch (e) {
      rethrow;
    }
  }

  Future<GalleryContentItem> loadItem(String id) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>('$_baseUrl/$id');
      return GalleryContentItem.fromJson(response.data ?? {});
    } catch (e) {
      rethrow;
    }
  }

  // ─── Import from Products ───────────────────────────────────────────────

  Future<List<GalleryContentItem>> importFromProducts({
    required List<String> productIds,
  }) async {
    try {
      final response = await _dio.post<List>(
        '$_baseUrl/import/productos',
        data: {'productIds': productIds},
      );

      final items = (response.data ?? [])
          .map(
            (item) => GalleryContentItem.fromJson(item as Map<String, dynamic>),
          )
          .toList();
      return items;
    } catch (e) {
      rethrow;
    }
  }

  // ─── Import from Global Gallery ────────────────────────────────────────

  Future<List<GalleryContentItem>> importFromGlobalGallery({
    required List<String> mediaIds,
  }) async {
    try {
      final response = await _dio.post<List>(
        '$_baseUrl/import/galeria-global',
        data: {'mediaIds': mediaIds},
      );

      final items = (response.data ?? [])
          .map(
            (item) => GalleryContentItem.fromJson(item as Map<String, dynamic>),
          )
          .toList();
      return items;
    } catch (e) {
      rethrow;
    }
  }

  // ─── Upload Content ────────────────────────────────────────────────────

  Future<GalleryContentItem> uploadContent({
    required String filePath,
    required ContentType type,
    required String categoria,
    required String descripcion,
    required List<String> tags,
    required List<ContentUsage> usadoEn,
  }) async {
    try {
      final formData = FormData.fromMap({
        'file': await MultipartFile.fromFile(filePath),
        'tipo': type == ContentType.video ? 'video' : 'imagen',
        'categoria': categoria,
        'descripcion': descripcion,
        'tags': tags.join(','),
        'usado_en': usadoEn.map((u) => _usageToString(u)).join(','),
      });

      final response = await _dio.post<Map<String, dynamic>>(
        '$_baseUrl/upload',
        data: formData,
      );

      return GalleryContentItem.fromJson(response.data ?? {});
    } catch (e) {
      rethrow;
    }
  }

  // ─── Update Metadata ───────────────────────────────────────────────────

  Future<GalleryContentItem> updateMetadata(
    String id, {
    String? categoria,
    String? descripcion,
    List<String>? tags,
    List<ContentUsage>? usadoEn,
  }) async {
    try {
      final data = <String, dynamic>{};
      if (categoria != null) data['categoria'] = categoria;
      if (descripcion != null) data['descripcion'] = descripcion;
      if (tags != null) data['tags'] = tags;
      if (usadoEn != null) {
        data['usado_en'] = usadoEn.map((u) => _usageToString(u)).toList();
      }

      final response = await _dio.patch<Map<String, dynamic>>(
        '$_baseUrl/$id',
        data: data,
      );

      return GalleryContentItem.fromJson(response.data ?? {});
    } catch (e) {
      rethrow;
    }
  }

  // ─── Toggle Favorite ───────────────────────────────────────────────────

  Future<void> toggleFavorite(String id, {required bool favorite}) async {
    try {
      await _dio.patch('$_baseUrl/$id/favorite', data: {'favorito': favorite});
    } catch (e) {
      rethrow;
    }
  }

  // ─── Toggle Published ───────────────────────────────────────────────────

  Future<void> togglePublished(String id, {required bool published}) async {
    try {
      await _dio.patch(
        '$_baseUrl/$id/published',
        data: {'publicado': published},
      );
    } catch (e) {
      rethrow;
    }
  }

  // ─── Delete Content ────────────────────────────────────────────────────

  Future<void> deleteContent(String id) async {
    try {
      await _dio.delete('$_baseUrl/$id');
    } catch (e) {
      rethrow;
    }
  }

  // ─── Bulk Operations ────────────────────────────────────────────────────

  Future<void> bulkToggleFavorite(
    List<String> ids, {
    required bool favorite,
  }) async {
    try {
      await _dio.patch(
        '$_baseUrl/bulk/favorite',
        data: {'ids': ids, 'favorito': favorite},
      );
    } catch (e) {
      rethrow;
    }
  }

  Future<void> bulkDelete(List<String> ids) async {
    try {
      await _dio.post('$_baseUrl/bulk/delete', data: {'ids': ids});
    } catch (e) {
      rethrow;
    }
  }

  Future<void> bulkUpdateUsage(
    List<String> ids, {
    required List<ContentUsage> usadoEn,
  }) async {
    try {
      await _dio.patch(
        '$_baseUrl/bulk/usage',
        data: {
          'ids': ids,
          'usado_en': usadoEn.map((u) => _usageToString(u)).toList(),
        },
      );
    } catch (e) {
      rethrow;
    }
  }
}

// Helper
String _usageToString(ContentUsage usage) {
  switch (usage) {
    case ContentUsage.estados:
      return 'estados';
    case ContentUsage.campanas:
      return 'campanas';
    case ContentUsage.marketplace:
      return 'marketplace';
    case ContentUsage.general:
      return 'general';
  }
}
