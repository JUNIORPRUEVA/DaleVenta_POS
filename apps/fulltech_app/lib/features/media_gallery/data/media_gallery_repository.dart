import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_error_mapper.dart';
import '../../../core/api/api_routes.dart';
import '../../../core/auth/auth_repository.dart';
import '../../../core/errors/api_exception.dart';
import '../media_gallery_models.dart';

final mediaGalleryRepositoryProvider = Provider<MediaGalleryRepository>((ref) {
  return MediaGalleryRepository(ref.watch(dioProvider));
});

class MediaGalleryRepository {
  MediaGalleryRepository(this._dio);

  final Dio _dio;

  static final _backgroundOptions = Options(extra: {'skipLoader': true});

  Never _rethrow(DioException error, String fallback) {
    throw ApiErrorMapper.fromDio(error, fallbackMessage: fallback, dio: _dio);
  }

  Future<MediaGalleryPage> fetchPage({
    String? cursor,
    int limit = 48,
    MediaGalleryTypeFilter typeFilter = MediaGalleryTypeFilter.all,
    MediaGalleryInstallationFilter installationFilter =
        MediaGalleryInstallationFilter.all,
    bool silent = true,
    bool forceRefresh = false,
  }) async {
    try {
      final res = await _dio.get(
        ApiRoutes.mediaGallery,
        queryParameters: {
          'limit': limit,
          'type': _typeValue(typeFilter),
          'installationStatus': _installationValue(installationFilter),
          if ((cursor ?? '').trim().isNotEmpty) 'cursor': cursor!.trim(),
        },
        options: _backgroundOptions.copyWith(
          extra: {...?_backgroundOptions.extra, 'silent': silent},
        ),
      );
      return MediaGalleryPage.fromJson(
        (res.data as Map).cast<String, dynamic>(),
      );
    } on DioException catch (error) {
      _rethrow(error, 'No se pudo cargar la galería de medios');
    } catch (error) {
      throw ApiException.detailed(
        message:
            'No se pudo cargar la galería de medios. El servidor respondió con un formato inválido.',
        type: ApiErrorType.parse,
        displayCode: 'PARSE_ERROR',
        technicalDetails: error.toString(),
        retryable: false,
      );
    }
  }

  Future<void> deleteItem(String id) async {
    try {
      await _dio.delete(
        ApiRoutes.mediaGalleryDelete(id),
        options: _backgroundOptions,
      );
    } on DioException catch (error) {
      _rethrow(error, 'No se pudo eliminar la evidencia');
    }
  }

  Future<void> markForPublicidad(String id) async {
    try {
      await _dio.patch(
        ApiRoutes.mediaGalleryMarkPublicidad(id),
        options: _backgroundOptions,
      );
    } on DioException catch (error) {
      _rethrow(error, 'No se pudo marcar la evidencia para publicidad');
    }
  }

  Future<void> unmarkForPublicidad(String id) async {
    try {
      await _dio.patch(
        ApiRoutes.mediaGalleryUnmarkPublicidad(id),
        options: _backgroundOptions,
      );
    } on DioException catch (error) {
      _rethrow(error, 'No se pudo quitar la evidencia de publicidad');
    }
  }

  Future<List<MediaGalleryItem>> fetchPublicidad() async {
    try {
      final res = await _dio.get(
        ApiRoutes.mediaGalleryPublicidad,
        options: _backgroundOptions,
      );
      final data = (res.data as Map).cast<String, dynamic>();
      final rawItems = (data['items'] as List?) ?? const [];
      return rawItems
          .whereType<Map>()
          .map((row) => MediaGalleryItem.fromJson(row.cast<String, dynamic>()))
          .toList(growable: false);
    } on DioException catch (error) {
      _rethrow(error, 'No se pudo cargar la galería de publicidad');
    } catch (error) {
      throw ApiException.detailed(
        message:
            'No se pudo cargar la galería de publicidad. Formato inválido.',
        type: ApiErrorType.parse,
        displayCode: 'PARSE_ERROR',
        technicalDetails: error.toString(),
        retryable: false,
      );
    }
  }

  String _typeValue(MediaGalleryTypeFilter filter) {
    switch (filter) {
      case MediaGalleryTypeFilter.image:
        return 'image';
      case MediaGalleryTypeFilter.video:
        return 'video';
      case MediaGalleryTypeFilter.all:
        return 'all';
    }
  }

  String _installationValue(MediaGalleryInstallationFilter filter) {
    switch (filter) {
      case MediaGalleryInstallationFilter.completed:
        return 'completed';
      case MediaGalleryInstallationFilter.pending:
        return 'pending';
      case MediaGalleryInstallationFilter.all:
        return 'all';
    }
  }
}
