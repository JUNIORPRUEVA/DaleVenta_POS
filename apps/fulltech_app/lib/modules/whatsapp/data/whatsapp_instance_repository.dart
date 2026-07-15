import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_repository.dart';
import '../../../core/errors/api_exception.dart';
import '../whatsapp_instance_model.dart';

final whatsappInstanceRepositoryProvider = Provider<WhatsappInstanceRepository>(
  (ref) {
    return WhatsappInstanceRepository(ref.watch(dioProvider));
  },
);

class WhatsappInstanceRepository {
  final Dio _dio;

  WhatsappInstanceRepository(this._dio);

  String _extractMessage(dynamic data, String fallback) {
    if (data is String) {
      final raw = data.trim();
      return raw.isEmpty ? fallback : raw;
    }
    if (data is Map) {
      final message = data['message'];
      if (message is String && message.trim().isNotEmpty) return message.trim();
      if (message is List && message.isNotEmpty) {
        final first = message.first;
        if (first is String) return first.trim();
      }
      final error = data['error'];
      if (error is String && error.trim().isNotEmpty) return error.trim();
    }
    return fallback;
  }

  ApiException _mapError(DioException e, String fallback) {
    final msg = _extractMessage(e.response?.data, fallback);
    return ApiException(msg, e.response?.statusCode);
  }

  /// POST /whatsapp/instance — crea instancia para el usuario autenticado.
  Future<WhatsappInstanceModel> createInstance({
    String? instanceName,
    String? phoneNumber,
  }) async {
    try {
      final data = <String, dynamic>{};
      if (instanceName != null) data['instanceName'] = instanceName;
      if (phoneNumber != null) data['phoneNumber'] = phoneNumber;
      final res = await _dio.post('/whatsapp/instance', data: data);
      return WhatsappInstanceModel.fromJson(
        (res.data as Map).cast<String, dynamic>(),
      );
    } on DioException catch (e) {
      throw _mapError(e, 'No se pudo crear la instancia de WhatsApp');
    }
  }

  /// GET /whatsapp/instance/status — estado del usuario autenticado.
  Future<WhatsappInstanceStatusResponse> getInstanceStatus() async {
    try {
      final res = await _dio.get('/whatsapp/instance/status');
      return WhatsappInstanceStatusResponse.fromJson(
        (res.data as Map).cast<String, dynamic>(),
      );
    } on DioException catch (e) {
      throw _mapError(e, 'No se pudo obtener el estado de WhatsApp');
    }
  }

  /// GET /whatsapp/instance/qr — QR para conectar.
  Future<WhatsappQrResponse> getQrCode() async {
    try {
      final res = await _dio.get('/whatsapp/instance/qr');
      return WhatsappQrResponse.fromJson(
        (res.data as Map).cast<String, dynamic>(),
      );
    } on DioException catch (e) {
      throw _mapError(e, 'No se pudo obtener el código QR');
    }
  }

  /// DELETE /whatsapp/instance — elimina instancia del usuario autenticado.
  Future<void> deleteInstance() async {
    try {
      await _dio.delete('/whatsapp/instance');
    } on DioException catch (e) {
      throw _mapError(e, 'No se pudo eliminar la instancia de WhatsApp');
    }
  }

  /// GET /whatsapp/admin/users — (solo admin) lista usuarios con estado WhatsApp.
  Future<List<WhatsappAdminUserEntry>> getAdminUsers() async {
    try {
      final res = await _dio.get('/whatsapp/admin/users');
      final list = res.data as List;
      return list
          .map(
            (item) => WhatsappAdminUserEntry.fromJson(
              (item as Map).cast<String, dynamic>(),
            ),
          )
          .toList(growable: false);
    } on DioException catch (e) {
      throw _mapError(e, 'No se pudo obtener los usuarios de WhatsApp');
    }
  }
}
