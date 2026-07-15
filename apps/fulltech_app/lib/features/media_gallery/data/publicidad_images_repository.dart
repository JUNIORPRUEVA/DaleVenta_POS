import 'dart:typed_data';
import 'dart:developer' as dev;

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_error_mapper.dart';
import '../../../core/api/api_routes.dart';
import '../../../core/auth/auth_repository.dart';
import '../models/publicidad_image_model.dart';

final publicidadImagesRepositoryProvider = Provider<PublicidadImagesRepository>(
  (ref) {
    return PublicidadImagesRepository(ref.watch(dioProvider));
  },
);

class PublicidadImagesRepository {
  final Dio _dio;

  PublicidadImagesRepository(this._dio);

  Never _rethrow(DioException error, String fallback) {
    throw ApiErrorMapper.fromDio(error, fallbackMessage: fallback, dio: _dio);
  }

  Future<PublicidadImage> create({required String url, String? caption}) async {
    try {
      final response = await _dio.post(
        ApiRoutes.publicidadImages,
        data: {
          'url': url,
          if (caption != null && caption.isNotEmpty) 'caption': caption,
        },
      );
      return PublicidadImage.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      _rethrow(e, 'No se pudo agregar la imagen');
    }
  }

  Future<List<PublicidadImage>> getAll() async {
    try {
      final response = await _dio.get(ApiRoutes.publicidadImages);
      final List<dynamic> items =
          (response.data is List ? response.data : response.data['items'] ?? [])
              as List;
      return items
          .map((e) => PublicidadImage.fromJson(e as Map<String, dynamic>))
          .toList();
    } on DioException catch (e) {
      _rethrow(e, 'No se pudo cargar las imágenes de publicidad');
    }
  }

  Future<void> delete(String id) async {
    try {
      await _dio.delete('${ApiRoutes.publicidadImages}/$id');
    } on DioException catch (e) {
      _rethrow(e, 'No se pudo eliminar la imagen');
    }
  }

  Future<PublicidadImage> update(String id, {String? caption}) async {
    try {
      final response = await _dio.patch(
        '${ApiRoutes.publicidadImages}/$id',
        data: {if (caption != null) 'caption': caption},
      );
      return PublicidadImage.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      _rethrow(e, 'No se pudo actualizar la imagen');
    }
  }

  /// Upload raw bytes as multipart/form-data directly to the API.
  /// The server saves the file locally (and optionally mirrors to R2) and
  /// creates the DB record in a single request.
  Future<PublicidadImage> uploadFile({
    required Uint8List bytes,
    required String contentType,
    required String filename,
    String? caption,
  }) async {
    try {
      final endpoint =
          '${_dio.options.baseUrl}${ApiRoutes.publicidadImages}/upload';
      dev.log(
        '[PublicidadUpload][request] endpoint=$endpoint filename=$filename contentType=$contentType bytes=${bytes.lengthInBytes}',
        name: 'PublicidadUpload',
      );
      final formData = FormData.fromMap({
        'file': MultipartFile.fromBytes(
          bytes,
          filename: filename,
          contentType: DioMediaType.parse(contentType),
        ),
        if (caption != null && caption.isNotEmpty) 'caption': caption,
      });
      final response = await _dio.post(
        '${ApiRoutes.publicidadImages}/upload',
        data: formData,
      );

      dev.log(
        '[PublicidadUpload][response] status=${response.statusCode} body=${response.data}',
        name: 'PublicidadUpload',
      );

      final payload = response.data as Map<String, dynamic>;
      final imageJson = payload['image'] is Map<String, dynamic>
          ? payload['image'] as Map<String, dynamic>
          : payload;
      return PublicidadImage.fromJson(imageJson);
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      final body = e.response?.data;
      dev.log(
        '[PublicidadUpload][error] endpoint=${_dio.options.baseUrl}${ApiRoutes.publicidadImages}/upload status=$status body=$body detail=${e.message}',
        name: 'PublicidadUpload',
        error: e,
        stackTrace: e.stackTrace,
      );
      _rethrow(e, 'No se pudo subir la imagen');
    }
  }
}
